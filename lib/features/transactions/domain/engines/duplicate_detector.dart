import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../core/utils/app_clock.dart';

import '../transaction.dart';
import 'raw_message.dart';
import '../transaction_enums.dart';

/// Minimal shape needed to compare two financial events.
class DedupeCandidate {
  const DedupeCandidate({
    required this.transactionId,
    required this.amount,
    required this.direction,
    required this.dateUtc,
    this.referenceNumber,
    this.maskedAccount,
    this.counterparty,
    this.sourceMessageIds = const [],
    this.sources = const [],
    this.bankName,
    this.paymentMode,
  });

  factory DedupeCandidate.fromTransaction(FinancialTransaction t, {List<String> messageIds = const []}) => DedupeCandidate(
        transactionId: t.transactionId,
        amount: t.amount,
        direction: t.direction,
        dateUtc: t.transactionDate,
        referenceNumber: t.referenceNumber,
        maskedAccount: t.maskedAccountNumber,
        counterparty: t.counterparty,
        sourceMessageIds: messageIds,
        sources: t.sources,
        bankName: t.bankName,
        paymentMode: t.paymentMode,
      );

  /// Fills fields this record lacks with values from [other] (same event
  /// seen in another source, e.g. the email has the reference number).
  DedupeCandidate enrichedWith(DedupeCandidate other) => DedupeCandidate(
        transactionId: transactionId,
        amount: amount,
        direction: direction,
        dateUtc: dateUtc,
        referenceNumber: referenceNumber ?? other.referenceNumber,
        maskedAccount: maskedAccount ?? other.maskedAccount,
        counterparty: counterparty ?? other.counterparty,
        sourceMessageIds: sourceMessageIds,
        sources: {...sources, ...other.sources}.toList(),
        bankName: bankName ?? other.bankName,
        paymentMode: paymentMode == null || paymentMode == PaymentMode.other ? other.paymentMode : paymentMode,
      );

  final String transactionId;
  final double amount;
  final TxDirection direction;
  final DateTime dateUtc;
  final String? referenceNumber;
  final String? maskedAccount;
  final String? counterparty;
  final List<String> sourceMessageIds;
  final List<TxSource> sources;
  final String? bankName;
  final PaymentMode? paymentMode;
}

enum DuplicateKind { none, sameMessage, sameEvent }

class DuplicateResult {
  const DuplicateResult(this.kind, {this.match, this.score = 0});
  final DuplicateKind kind;
  final DedupeCandidate? match;
  final double score;
  bool get isDuplicate => kind != DuplicateKind.none;
}

/// Detects when two messages (e.g. an SMS and an email) describe the same
/// financial event so the amount is counted exactly once.
class DuplicateDetector {
  const DuplicateDetector({
    this.timeWindow = const Duration(hours: 36),
    this.sameSourceWindow = const Duration(minutes: 15),
  });

  final Duration timeWindow;

  /// How far apart two alerts from the same channel (e.g. two SMS) may be and
  /// still describe one payment.
  final Duration sameSourceWindow;

  /// Deterministic transaction ID. Using a stable ID makes Firestore writes
  /// idempotent: re-processing the same message never creates a new record.
  static String transactionIdFor({
    required String workspaceId,
    required double amount,
    required TxDirection direction,
    String? referenceNumber,
    required String sourceKey,
  }) {
    final basis = referenceNumber != null
        ? 'ref|$workspaceId|${referenceNumber.toUpperCase()}|${amount.toStringAsFixed(2)}|${direction.name}'
        : 'msg|$workspaceId|$sourceKey';
    return sha256.convert(utf8.encode(basis)).toString().substring(0, 28);
  }

  /// Content keys for one SMS: the same text from the same sender received
  /// within ~10 minutes. The live broadcast and the inbox row of a single SMS
  /// carry different ids (`live-<time>-<sender>` vs the inbox `_id`), so the
  /// id-based ledger alone lets the same message be saved twice.
  ///
  /// Returns `[own, previousBucket, nextBucket]`; the first is recorded after
  /// processing, all three are looked up before. Only hashes are stored,
  /// never the body. Empty for non-SMS messages.
  static List<String> smsContentKeys(RawMessage m, {Duration bucket = const Duration(minutes: 10)}) {
    if (m.source != TxSource.sms) return const [];
    // Operator prefixes vary between deliveries ("VM-HDFCBK" vs "AD-HDFCBK").
    final sender = m.sender.toUpperCase().replaceFirst(RegExp(r'^[A-Z]{2}-'), '').replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final body = m.body.trim().replaceAll(RegExp(r'\s+'), ' ');
    final hash = sha256.convert(utf8.encode('$sender|$body')).toString().substring(0, 24);
    final b = m.receivedAt.millisecondsSinceEpoch ~/ bucket.inMilliseconds;
    return ['smsbody:$hash:$b', 'smsbody:$hash:${b - 1}', 'smsbody:$hash:${b + 1}'];
  }

  /// Removes records that describe the same payment as another record in
  /// [txs], keeping the original order. Uses the same rules as sync ([score]),
  /// plus identical records (same SMS saved twice) a couple of minutes apart.
  /// Applied wherever transactions are read, so lists and totals stay right
  /// even before duplicates already saved are cleaned up.
  static List<FinancialTransaction> collapse(List<FinancialTransaction> txs) {
    if (txs.length < 2) return txs;
    const detector = DuplicateDetector();
    bool same(FinancialTransaction a, FinancialTransaction b) {
      if (a.transactionId == b.transactionId) return true;
      if (detector.score(DedupeCandidate.fromTransaction(a), DedupeCandidate.fromTransaction(b)) >= 0.75) return true;
      return twinKey(a) == twinKey(b) &&
          a.sources.toSet().containsAll(b.sources) &&
          b.sources.toSet().containsAll(a.sources) &&
          a.transactionDate.difference(b.transactionDate).abs() <= const Duration(minutes: 2);
    }

    // Preferred copy first: more sources, user-corrected, has a reference
    // number, then oldest.
    int rank(FinancialTransaction a, FinancialTransaction b) {
      final bySources = b.sources.length.compareTo(a.sources.length);
      if (bySources != 0) return bySources;
      final byCorrected = (b.categoryConfidence >= 1 ? 1 : 0).compareTo(a.categoryConfidence >= 1 ? 1 : 0);
      if (byCorrected != 0) return byCorrected;
      final byRef = (b.referenceNumber != null ? 1 : 0).compareTo(a.referenceNumber != null ? 1 : 0);
      if (byRef != 0) return byRef;
      return a.createdAt.compareTo(b.createdAt);
    }

    final groups = <String, List<FinancialTransaction>>{};
    for (final t in txs) {
      groups.putIfAbsent('${t.amount.toStringAsFixed(2)}|${t.direction.name}', () => []).add(t);
    }
    final dropped = <FinancialTransaction>{};
    for (final g in groups.values) {
      if (g.length < 2) continue;
      final kept = <FinancialTransaction>[];
      for (final t in [...g]..sort(rank)) {
        if (kept.any((k) => same(k, t))) {
          dropped.add(t);
        } else {
          kept.add(t);
        }
      }
    }
    if (dropped.isEmpty) return txs;
    return [for (final t in txs) if (!dropped.contains(t)) t];
  }

  /// Coarse key: records that can only be duplicates if they share it.
  static String amountKey(FinancialTransaction t) => '${t.ownerUserId}|${t.amount.toStringAsFixed(2)}|${t.direction.name}';

  /// Grouping key for records that could be the same SMS saved twice.
  static String twinKey(FinancialTransaction t) => [
        t.ownerUserId,
        t.amount.toStringAsFixed(2),
        t.direction.name,
        t.narration,
        t.counterparty ?? '',
        t.maskedAccountNumber ?? '',
        t.bankName ?? '',
        t.referenceNumber ?? '',
      ].join('|');

  /// Already-saved records that are copies of one SMS. [items] carries each
  /// record with its owner-only source details. Two records are copies when
  /// they agree on amount, direction, payee, account, bank and reference
  /// ([twinKey]), are within [window] of each other, came from different SMS
  /// rows, and either
  ///  * one came from the live listener (`sms:live-…`) and one from the inbox, or
  ///  * both carry the same sender and the same SMS text (the same message
  ///    stored twice in the inbox, e.g. after an SMS backup restore), or
  ///  * they are two differently worded SMS for one payment (same payee,
  ///    minutes apart, no conflicting reference — see [score]).
  ///
  /// Keeps the copy with more sources, then one the user corrected, then an
  /// inbox one, then the oldest. Triplicates collapse into one record.
  static List<({String keep, String drop, List<String> dropIds})> smsTwins(
    List<({FinancialTransaction tx, TransactionSourceDetails src})> items, {
    Duration window = const Duration(minutes: 30),
  }) {
    List<String> smsIds(TransactionSourceDetails d) => d.sourceMessageIds.where((i) => i.startsWith('sms:')).toList();
    bool isLive(TransactionSourceDetails d) {
      final ids = smsIds(d);
      return ids.isNotEmpty && ids.every((i) => i.startsWith('sms:live-'));
    }

    String sender(String? s) => (s ?? '').toUpperCase().replaceFirst(RegExp(r'^[A-Z]{2}-'), '').replaceAll(RegExp(r'[^A-Z0-9]'), '');
    String text(String? s) => (s ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

    bool twins(({FinancialTransaction tx, TransactionSourceDetails src}) a, ({FinancialTransaction tx, TransactionSourceDetails src}) b) {
      if (a.tx.transactionDate.difference(b.tx.transactionDate).abs() > window) return false;
      final ia = smsIds(a.src), ib = smsIds(b.src);
      if (ia.isEmpty || ib.isEmpty || ia.toSet().intersection(ib.toSet()).isNotEmpty) return false;
      if (const DuplicateDetector().score(DedupeCandidate.fromTransaction(a.tx), DedupeCandidate.fromTransaction(b.tx)) >= 0.75) return true;
      if (twinKey(a.tx) != twinKey(b.tx)) return false;
      if (isLive(a.src) != isLive(b.src)) return true;
      final ta = text(a.src.originalNarration);
      return ta.isNotEmpty &&
          ta == text(b.src.originalNarration) &&
          sender(a.src.smsSender).isNotEmpty &&
          sender(a.src.smsSender) == sender(b.src.smsSender);
    }

    int rank(({FinancialTransaction tx, TransactionSourceDetails src}) a, ({FinancialTransaction tx, TransactionSourceDetails src}) b) {
      final bySources = b.tx.sources.length.compareTo(a.tx.sources.length);
      if (bySources != 0) return bySources;
      final byCorrected = (b.tx.categoryConfidence >= 1 ? 1 : 0).compareTo(a.tx.categoryConfidence >= 1 ? 1 : 0);
      if (byCorrected != 0) return byCorrected;
      final byInbox = (isLive(a.src) ? 1 : 0).compareTo(isLive(b.src) ? 1 : 0);
      if (byInbox != 0) return byInbox;
      return a.tx.createdAt.compareTo(b.tx.createdAt);
    }

    final out = <({String keep, String drop, List<String> dropIds})>[];
    final groups = <String, List<({FinancialTransaction tx, TransactionSourceDetails src})>>{};
    for (final it in items) {
      if (!it.tx.sources.contains(TxSource.sms)) continue;
      groups.putIfAbsent(amountKey(it.tx), () => []).add(it);
    }
    for (final g in groups.values) {
      if (g.length < 2) continue;
      g.sort(rank);
      final keepers = <({FinancialTransaction tx, TransactionSourceDetails src})>[];
      for (final it in g) {
        final k = keepers.where((k) => twins(k, it)).firstOrNull;
        if (k == null) {
          keepers.add(it);
        } else {
          out.add((keep: k.tx.transactionId, drop: it.tx.transactionId, dropIds: it.src.sourceMessageIds));
        }
      }
    }
    return out;
  }

  /// Normalized fingerprint stored on the transaction for server-side checks.
  static String fingerprint({
    required double amount,
    required TxDirection direction,
    required DateTime dateUtc,
    String? maskedAccount,
    String? referenceNumber,
  }) {
    final day = '${dateUtc.year}-${dateUtc.month}-${dateUtc.day}';
    final basis = [
      amount.toStringAsFixed(2),
      direction.name,
      day,
      (maskedAccount ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
      (referenceNumber ?? '').toUpperCase(),
    ].join('|');
    return sha256.convert(utf8.encode(basis)).toString().substring(0, 24);
  }

  DuplicateResult check(DedupeCandidate incoming, Iterable<DedupeCandidate> existing, {required String sourceKey}) {
    DedupeCandidate? best;
    double bestScore = 0;
    for (final e in existing) {
      if (e.sourceMessageIds.contains(sourceKey)) {
        return DuplicateResult(DuplicateKind.sameMessage, match: e, score: 1);
      }
      final s = score(incoming, e);
      if (s > bestScore) {
        bestScore = s;
        best = e;
      }
    }
    if (best != null && bestScore >= 0.75) {
      return DuplicateResult(DuplicateKind.sameEvent, match: best, score: bestScore);
    }
    return const DuplicateResult(DuplicateKind.none);
  }

  /// 0..1 similarity. Hard mismatches (amount, direction, conflicting
  /// references, different accounts) return 0.
  ///
  /// Typical SMS + email pair for one payment:
  ///   amount+direction 0.55, same bank 0.10, within 2h 0.15 → 0.80 (merged).
  double score(DedupeCandidate a, DedupeCandidate b) {
    if ((a.amount - b.amount).abs() > 0.009) return 0;
    if (a.direction != b.direction) return 0;

    var penalty = 0.0;
    final refA = a.referenceNumber, refB = b.referenceNumber;
    if (refA != null && refB != null) {
      if (_refsMatch(refA, refB)) return 1;
      // Same kind of reference (e.g. two 12-digit UPI RRNs) that differ → two events.
      // Different kinds (order ID in an email vs UPI RRN in an SMS) are not conclusive.
      if (_sameRefShape(refA, refB)) return 0;
      penalty += 0.05;
    }

    final acct = _accountsMatch(a.maskedAccount, b.maskedAccount);
    if (acct == false) return 0;
    // Different institution names lower confidence but don't rule a match out:
    // a UPI payment can arrive as a bank SMS plus a payment-app email.
    final bank = _banksMatch(a.bankName, b.bankName);
    if (bank == false) penalty += 0.1;

    final gap = a.dateUtc.difference(b.dateUtc).abs();
    if (gap > timeWindow) return 0;

    // Same source type (e.g. two SMS): usually two genuine payments, but a
    // bank often sends two differently worded alerts for one payment (debit
    // alert + UPI confirmation). Treat them as one only when the payee matches
    // and they are minutes apart. Two different references of the same kind
    // were already ruled out above, so a real repeat payment with its own
    // UPI ref stays separate.
    final sameSourceType = a.sources.isNotEmpty && b.sources.isNotEmpty && a.sources.toSet().intersection(b.sources.toSet()).isNotEmpty;
    if (sameSourceType) {
      if (!_namesSimilar(a.counterparty, b.counterparty)) return 0;
      if (gap > sameSourceWindow) return 0;
      return (0.8 - penalty).clamp(0, 1).toDouble();
    }

    var s = 0.55; // amount + direction
    if (acct == true) s += 0.2;
    if (bank == true) s += 0.1;
    if (_isDateOnly(a.dateUtc) || _isDateOnly(b.dateUtc)) {
      // Emails often carry only a date; compare calendar days instead of hours.
      final days = _localDay(a.dateUtc).difference(_localDay(b.dateUtc)).inDays.abs();
      if (days == 0) {
        s += 0.1;
      } else if (days == 1) {
        s += 0.04;
      }
    } else if (gap < const Duration(hours: 2)) {
      s += 0.15;
    } else if (gap < const Duration(hours: 12)) {
      s += 0.08;
    }
    if (_namesSimilar(a.counterparty, b.counterparty)) s += 0.15;
    final modeA = a.paymentMode, modeB = b.paymentMode;
    if (modeA != null && modeA != PaymentMode.other && modeA == modeB) s += 0.05;
    return (s - penalty).clamp(0, 1).toDouble();
  }

  bool _refsMatch(String a, String b) {
    final x = a.toUpperCase(), y = b.toUpperCase();
    if (x == y) return true;
    // Some emails truncate references; accept a long common suffix.
    final n = x.length < y.length ? x.length : y.length;
    return n >= 8 && x.substring(x.length - n) == y.substring(y.length - n);
  }

  static final _numeric = RegExp(r'^[0-9]+$');
  bool _sameRefShape(String a, String b) =>
      a.length == b.length && _numeric.hasMatch(a) == _numeric.hasMatch(b);

  /// true = same account, false = definitely different, null = unknown.
  /// Masks differ in length ("XX234" vs "XXXXXXXX1234"), so compare the
  /// trailing digits both sides have (at least 3).
  bool? _accountsMatch(String? a, String? b) {
    final x = _digits(a), y = _digits(b);
    final n = x.length < y.length ? x.length : y.length;
    if (n < 3) return null;
    return x.substring(x.length - n) == y.substring(y.length - n);
  }

  /// true = same bank, false = clearly different banks, null = unknown.
  bool? _banksMatch(String? a, String? b) {
    final x = _norm(a), y = _norm(b);
    if (x.isEmpty || y.isEmpty) return null;
    return x.contains(y) || y.contains(x) || x.split(' ').first == y.split(' ').first;
  }

  static String _norm(String? s) => (s ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'\b(bank|ltd|limited|of|india|the|credit|card|cards)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isDateOnly(DateTime utc) {
    final l = AppClock.toLocal(utc);
    return l.hour == 0 && l.minute == 0 && l.second == 0;
  }

  static DateTime _localDay(DateTime utc) {
    final l = AppClock.toLocal(utc);
    return DateTime(l.year, l.month, l.day);
  }

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  /// Same payee if one name contains the other, or they share a word of 4+
  /// letters ("SWIGGY" vs "Swiggy Instamart", "swiggy@icici" vs "Swiggy").
  bool _namesSimilar(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final y = b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (x.isEmpty || y.isEmpty) return false;
    if (x.contains(y) || y.contains(x)) return true;
    Set<String> words(String s) => s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 4).toSet();
    return words(a).intersection(words(b)).isNotEmpty;
  }
}
