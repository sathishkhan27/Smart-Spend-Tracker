import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../core/utils/app_clock.dart';

import '../transaction.dart';
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
  const DuplicateDetector({this.timeWindow = const Duration(hours: 36)});

  final Duration timeWindow;

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

    // Two events of the same amount from the SAME source type are probably two
    // genuine payments (e.g. two coffees) unless they share a reference.
    final sameSourceType = a.sources.isNotEmpty && b.sources.isNotEmpty && a.sources.toSet().intersection(b.sources.toSet()).isNotEmpty;
    if (sameSourceType) return 0;

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
