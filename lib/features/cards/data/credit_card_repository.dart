import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/failures.dart';
import '../../transactions/data/transaction_mapper.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../domain/credit_card.dart';

/// Stores cards at credit_cards/{workspaceId}_{issuer}_{last4}. Each field is
/// only replaced by a value from a newer message.
class CreditCardRepository {
  CreditCardRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('credit_cards');

  Stream<List<CreditCard>> watch(String workspaceId) => _col
      .where('workspaceId', isEqualTo: workspaceId)
      .snapshots()
      .map((q) => _onePerNumber(q.docs
          .where((d) => d.data()['hidden'] != true) // removed by the user ("not my credit card")
          .where((d) => _confirmed(d.data()))
          .map((d) => _from(d.id, d.data())))
        ..sort((a, b) => b.pendingDue.compareTo(a.pendingDue)));

  /// Shown only if confirmed by the current reader, or set up by the user.
  static bool _confirmed(Map<String, dynamic> d) =>
      (d['v'] as num? ?? 0) >= 2 || d['limitSetManually'] == true || d['cycleSetManually'] == true;

  /// The same card saved twice (e.g. "Credit card ••4007" and "ICICI Bank
  /// ••4007") is shown once: the one with an issuer name and the most details.
  static List<CreditCard> _onePerNumber(Iterable<CreditCard> cards) {
    int score(CreditCard c) =>
        (c.issuer == 'Credit card' ? 0 : 10) +
        [c.creditLimit, c.availableLimit, c.totalDue, c.statementDay, c.lastPaymentAt].where((v) => v != null).length;
    final best = <String, CreditCard>{};
    for (final c in cards) {
      final cur = best[c.last4];
      if (cur == null || score(c) > score(cur)) best[c.last4] = c;
    }
    return best.values.toList();
  }

  Stream<CreditCard?> watchOne(String id) => _col.doc(id).snapshots().map((d) => d.exists ? _from(d.id, d.data()!) : null);

  /// Confirmed, visible cards (one per number).
  Future<List<CreditCard>> list(String workspaceId) async {
    final q = await _col.where('workspaceId', isEqualTo: workspaceId).get();
    return _onePerNumber(q.docs.where((d) => d.data()['hidden'] != true && _confirmed(d.data())).map((d) => _from(d.id, d.data())));
  }

  /// Last-4 digits of the workspace's credit cards (hidden ones excluded).
  Future<Set<String>> cardNumbers(String workspaceId) async {
    try {
      final q = await _col.where('workspaceId', isEqualTo: workspaceId).get();
      return {
        for (final d in q.docs)
          if (d.data()['hidden'] != true && _confirmed(d.data()) && d.data()['last4'] is String) d.data()['last4'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Re-labels this user's past transactions on known credit cards that were
  /// saved as "Debit Card" (e.g. ICICI "Card XX4007" alerts). Returns the count.
  Future<int> fixPaymentModes(String workspaceId, String userId) async {
    try {
      final cardsSnap = await _col.where('workspaceId', isEqualTo: workspaceId).get();
      final cards = [for (final d in cardsSnap.docs) if (d.data()['hidden'] != true && _confirmed(d.data())) _from(d.id, d.data())];
      if (cards.isEmpty) return 0;
      final since = DateTime.now().toUtc().subtract(const Duration(days: 400));
      final q = await _db
          .collection('transactions')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('transactionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      var batch = _db.batch();
      var n = 0, inBatch = 0;
      for (final doc in q.docs) {
        final t = TransactionMapper.fromFirestore(doc);
        if (t.ownerUserId != userId || t.paymentMode == PaymentMode.creditCard) continue;
        // Spends on the card number are card spends, even "UPI-…" ones (UPI on a credit card).
        if (!cards.any((c) => _sameNumber(t, c))) continue;
        batch.update(doc.reference, {
          'paymentMode': PaymentMode.creditCard.name,
          if (!t.isInflow && t.transactionType == TxType.debitCardPayment) 'transactionType': TxType.creditCardPayment.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        n++;
        if (++inBatch == 400) {
          await batch.commit();
          batch = _db.batch();
          inBatch = 0;
        }
      }
      if (inBatch > 0) await batch.commit();
      return n;
    } catch (e, s) {
      ErrorHandler.log(e, s, 'cards.fixModes');
      return 0;
    }
  }

  /// The transaction's account digits are this card's number.
  static bool _sameNumber(FinancialTransaction t, CreditCard c) {
    final digits = (t.maskedAccountNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 3) return false;
    return digits.length >= 4 ? digits.substring(digits.length - 4) == c.last4 : c.last4.endsWith(digits);
  }

  /// Card-reader version stamped on cards it confirms (see [watch]).
  static const _version = 4;

  /// Probable bill payments from the paying bank, kept on the issuer's cards.
  Future<void> applyHints(String workspaceId, Iterable<BillPaymentHint> hints) async {
    if (hints.isEmpty) return;
    try {
      final q = await _col.where('workspaceId', isEqualTo: workspaceId).get();
      for (final doc in q.docs) {
        final issuer = (doc.data()['issuer'] as String? ?? '').toLowerCase().split(RegExp(r'\s+')).first;
        final mine = hints.where((h) => issuer.length >= 3 && h.issuer.toLowerCase().startsWith(issuer)).toList();
        if (mine.isEmpty) continue;
        final existing = [for (final m in (doc.data()['paymentHints'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
        for (final h in mine) {
          final dup = existing.any((e) => ((e['amount'] as num).toDouble() - h.amount).abs() < 0.01 && (e['at'] as Timestamp).toDate().difference(h.at).inDays.abs() <= 3);
          if (!dup) existing.add({'amount': h.amount, 'at': Timestamp.fromDate(h.at)});
        }
        existing.sort((a, b) => (b['at'] as Timestamp).compareTo(a['at'] as Timestamp));
        await doc.reference.update({'paymentHints': existing.take(12).toList()});
      }
    } catch (e, s) {
      ErrorHandler.log(e, s, 'cards.hints');
    }
  }

  /// Merges message snapshots (several per card are fine; newest wins per field).
  Future<void> apply(String workspaceId, String userId, Iterable<CardSnapshot> snapshots) async {
    final byCard = <String, List<CardSnapshot>>{};
    for (final s in snapshots) {
      byCard.putIfAbsent(s.key, () => []).add(s);
    }
    for (final entry in byCard.entries) {
      try {
        final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
        // Same card number already stored (perhaps under another issuer name)?
        final last4 = list.last.last4;
        final same = await _col.where('workspaceId', isEqualTo: workspaceId).where('last4', isEqualTo: last4).limit(1).get();
        final ref = same.docs.isNotEmpty ? same.docs.first.reference : _col.doc('${workspaceId}_${entry.key}');
        final cur = (same.docs.isNotEmpty ? same.docs.first.data() : null) ?? <String, dynamic>{};
        if (cur['hidden'] == true) continue; // the user said this isn't their credit card
        // Entries written by an older reader may hold wrong dates (e.g. a
        // payment reminder saved as the statement). Rebuild them from messages.
        final fresh = (cur['v'] as num? ?? 0) < _version;
        DateTime? ts(String k) => fresh ? null : (cur[k] as Timestamp?)?.toDate();
        final upd = <String, dynamic>{
          if (fresh && cur.isNotEmpty) ...{
            'statementAt': null,
            if (cur['cycleSetManually'] != true) 'statementDay': null,
            'totalDue': null,
            'minDue': null,
            'dueDate': null,
            'statementFromSms': false,
            // Older readers counted refunds as payments; rebuild from messages.
            'lastPaymentAmount': null,
            'lastPaymentAt': null,
            'paymentHints': <Map<String, dynamic>>[],
          },
        };
        for (final s in list) {
          final at = Timestamp.fromDate(s.at);
          bool newer(String k) {
            final prev = (upd[k] as Timestamp?)?.toDate() ?? ts(k);
            return prev == null || !s.at.isBefore(prev);
          }

          if (s.availableLimit != null && newer('availableAt')) {
            upd['availableLimit'] = s.availableLimit;
            upd['availableAt'] = at;
          }
          if (s.creditLimit != null && cur['limitSetManually'] != true && newer('limitAt')) {
            upd['creditLimit'] = s.creditLimit;
            upd['limitAt'] = at;
          }
          if (s.totalDue != null && s.isStatement && newer('statementAt')) {
            upd['totalDue'] = s.totalDue;
            upd['minDue'] = s.minDue;
            upd['dueDate'] = s.dueDate == null ? null : Timestamp.fromDate(s.dueDate!);
            upd['statementAt'] = at;
            upd['statementFromSms'] = true;
            // Learn the billing cycle from the statement unless the user set it.
            if (cur['cycleSetManually'] != true) {
              upd['statementDay'] = s.at.day;
              if (s.dueDate != null) upd['dueDay'] = s.dueDate!.day;
            }
          } else if (s.totalDue != null && !s.isStatement) {
            // "Pay Total Amount Due … by 03-Nov": same bill, sent near the due
            // date. Fills amounts/due date but never moves the statement date.
            final curDue = (upd['dueDate'] as Timestamp?)?.toDate() ?? ts('dueDate');
            if (curDue == null || s.dueDate == null || !s.dueDate!.isBefore(curDue)) {
              if (upd['statementAt'] == null && ts('statementAt') == null) upd['statementAt'] = Timestamp.fromDate(s.at.subtract(const Duration(days: 4)));
              upd['totalDue'] = s.totalDue;
              upd['minDue'] = s.minDue ?? upd['minDue'] ?? cur['minDue'];
              if (s.dueDate != null) upd['dueDate'] = Timestamp.fromDate(s.dueDate!);
              if (cur['cycleSetManually'] != true && s.dueDate != null) upd['dueDay'] = s.dueDate!.day;
            }
          }
          // "Revised total due Rs …" after a refund: replaces the open amount.
          if (s.revisedTotalDue != null) {
            final stmt = (upd['statementAt'] as Timestamp?)?.toDate() ?? ts('statementAt');
            if (stmt == null || s.at.isAfter(stmt)) {
              upd['totalDue'] = s.revisedTotalDue;
              if (s.revisedMinDue != null) upd['minDue'] = s.revisedMinDue;
              upd['revisedAt'] = at;
            }
          }
          if (s.paymentAmount != null && newer('lastPaymentAt')) {
            upd['lastPaymentAmount'] = s.paymentAmount;
            upd['lastPaymentAt'] = at;
          }
        }
        if (upd.isEmpty && cur.isNotEmpty && (cur['v'] as num? ?? 0) >= _version) continue;
        final last = list.last;
        await ref.set({
          'workspaceId': workspaceId,
          // Keep a specific issuer name over the generic "Credit card".
          'issuer': (cur['issuer'] == null || cur['issuer'] == 'Credit card') ? last.issuer : cur['issuer'],
          'last4': last.last4,
          if (cur.isEmpty) 'createdBy': userId,
          // Confirmed by the current (stricter) reader; older entries without
          // this were created by an earlier reader and may be wrong.
          'v': _version,
          ...upd,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e, s) {
        ErrorHandler.log(e, s, 'cards.apply');
      }
    }
  }

  /// "Not my credit card": hides it and stops future messages re-adding it.
  Future<void> hide(String id) async {
    try {
      await _col.doc(id).update({'hidden': true, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// "Mark as paid": records a payment the app couldn't see (no SMS).
  Future<void> markPaid(String id, double amount) async {
    try {
      await _col.doc(id).update({
        'lastPaymentAmount': amount,
        'lastPaymentAt': Timestamp.now(),
        'manualPaidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// User-set billing cycle (statement day and payment due day of month).
  Future<void> setCycle(String id, {required int statementDay, required int dueDay}) async {
    try {
      await _col.doc(id).update({
        'statementDay': statementDay,
        'dueDay': dueDay,
        'cycleSetManually': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// User-entered credit limit (kept even if later SMS say otherwise).
  Future<void> setLimit(String id, double? limit) async {
    try {
      await _col.doc(id).update({
        'creditLimit': limit,
        'limitSetManually': limit != null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Most recent transactions made with this card (last ~6 months).
  /// Uses the existing workspace+date index and matches on the client, so
  /// masks written differently ("XX4007", "4007", "…007") still match.
  Future<List<FinancialTransaction>> recentTransactions(CreditCard card, {int limit = 40}) async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 185));
      final q = await _db
          .collection('transactions')
          .where('workspaceId', isEqualTo: card.workspaceId)
          .where('transactionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('transactionDate', descending: true)
          .limit(2000)
          .get();
      return q.docs.map(TransactionMapper.fromFirestore).where((t) => belongsToCard(t, card)).take(limit).toList();
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Whether [t] was made with [card].
  static bool belongsToCard(FinancialTransaction t, CreditCard card) {
    // Paying the card bill from a bank account is not a card spend.
    if (t.transactionType == TxType.creditCardBillPayment && t.isInflow == false && t.paymentMode != PaymentMode.creditCard) return false;
    final digits = (t.maskedAccountNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3) {
      return digits.length >= 4 ? digits.substring(digits.length - 4) == card.last4 : card.last4.endsWith(digits);
    }
    // No number in the message: a credit-card payment from the same issuer.
    if (t.paymentMode != PaymentMode.creditCard) return false;
    final issuer = card.issuer.toLowerCase().split(RegExp(r'\s+')).first;
    return issuer.length >= 3 && (t.bankName ?? '').toLowerCase().contains(issuer);
  }

  CreditCard _from(String id, Map<String, dynamic> d) {
    double? n(String k) => (d[k] as num?)?.toDouble();
    DateTime? t(String k) => (d[k] as Timestamp?)?.toDate();
    return CreditCard(
      id: id,
      workspaceId: d['workspaceId'] as String? ?? '',
      issuer: d['issuer'] as String? ?? 'Credit card',
      last4: d['last4'] as String? ?? '••••',
      creditLimit: n('creditLimit'),
      availableLimit: n('availableLimit'),
      availableAt: t('availableAt'),
      totalDue: n('totalDue'),
      minDue: n('minDue'),
      dueDate: t('dueDate'),
      statementAt: t('statementAt'),
      lastPaymentAmount: n('lastPaymentAmount'),
      lastPaymentAt: t('lastPaymentAt'),
      limitSetManually: d['limitSetManually'] as bool? ?? false,
      statementDay: (d['statementDay'] as num?)?.toInt(),
      dueDay: (d['dueDay'] as num?)?.toInt(),
      cycleSetManually: d['cycleSetManually'] as bool? ?? false,
      statementFromSms: d['statementFromSms'] as bool? ?? false,
      paymentHints: [
        for (final m in (d['paymentHints'] as List? ?? const []))
          if (m is Map && m['amount'] is num && m['at'] is Timestamp) (amount: (m['amount'] as num).toDouble(), at: (m['at'] as Timestamp).toDate()),
      ],
    );
  }
}
