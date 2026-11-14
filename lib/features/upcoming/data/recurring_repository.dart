import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/failures.dart';
import '../domain/due_reminder_parser.dart';
import '../domain/recurring_detector.dart';
import '../domain/recurring_expense.dart';

class RecurringRepository {
  RecurringRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('recurring_expenses');

  Stream<List<RecurringExpense>> watch(String workspaceId) => _col
      .where('workspaceId', isEqualTo: workspaceId)
      .snapshots()
      .map((q) => q.docs.map((d) => _from(d.id, d.data())).where((r) => r.status != RecurringStatus.dismissed).toList()
        ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate)));

  Future<void> save(RecurringExpense r) async {
    try {
      await _col.doc(r.id).set(_to(r), SetOptions(merge: true));
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> setStatus(String id, RecurringStatus status) =>
      _col.doc(id).update({'status': status.name, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> delete(String id) async {
    try {
      await _col.doc(id).delete();
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  String newId() => _col.doc().id;

  Future<List<RecurringExpense>> list(String workspaceId) async {
    final q = await _col.where('workspaceId', isEqualTo: workspaceId).get();
    return q.docs.map((d) => _from(d.id, d.data())).toList();
  }

  /// Creates or refreshes the Upcoming entry for a bank due reminder.
  /// Bank reminders are explicit, so entries start as active (not suggested).
  /// Never resurrects a dismissed entry, and never moves a due back to a date
  /// that is already paid or older than the one stored.
  Future<void> upsertFromReminder(String workspaceId, String userId, DueReminder r) async {
    try {
      final ref = _col.doc('${workspaceId}_due_${r.key}');
      final snap = await ref.get();
      final due = Timestamp.fromDate(r.dueDate);
      if (!snap.exists) {
        await ref.set({
          ..._to(RecurringExpense(
            id: ref.id,
            workspaceId: workspaceId,
            name: r.title,
            expectedAmount: r.amount,
            currency: r.currency,
            frequency: r.frequency,
            nextDueDate: r.dueDate,
            categoryId: r.categoryId,
            counterparty: r.institution,
            status: RecurringStatus.active,
            confidence: 0.95,
            merchantKey: r.key,
            createdBy: userId,
          )),
          'origin': 'reminder',
          'maskedAccount': r.maskedAccount,
        });
        return;
      }
      final cur = _from(snap.id, snap.data()!);
      if (cur.status == RecurringStatus.dismissed) return;
      final lastPaid = cur.lastPaidDate;
      final alreadyPaid = lastPaid != null && !r.dueDate.isAfter(DateTime(lastPaid.year, lastPaid.month, lastPaid.day));
      final newer = !r.dueDate.isBefore(DateTime(cur.nextDueDate.year, cur.nextDueDate.month, cur.nextDueDate.day));
      await ref.update({
        if (!alreadyPaid && newer) 'nextDueDate': due,
        if (!alreadyPaid && newer) 'expectedAmount': r.amount,
        if (cur.status == RecurringStatus.suggested) 'status': RecurringStatus.active.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Upserts detector output as *suggestions*. Never overrides an entry the
  /// user already confirmed, paused or dismissed — except to roll its dates.
  Future<int> upsertSuggestions(String workspaceId, String userId, List<RecurringSuggestion> suggestions) async {
    var created = 0;
    for (final s in suggestions) {
      final id = '${workspaceId}_auto_${s.merchantKey}';
      final ref = _col.doc(id);
      final snap = await ref.get();
      if (snap.exists) {
        final status = RecurringExpense.statusFrom(snap.data()!['status']);
        if (status == RecurringStatus.dismissed) continue;
        await ref.update({
          'lastPaidDate': Timestamp.fromDate(s.lastPaidDate),
          'nextDueDate': Timestamp.fromDate(s.nextDueDate),
          'occurrences': s.occurrences,
          'confidence': s.confidence,
          if (status == RecurringStatus.suggested) 'expectedAmount': s.expectedAmount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        created++;
        await ref.set(_to(RecurringExpense(
          id: id,
          workspaceId: workspaceId,
          name: s.name,
          expectedAmount: s.expectedAmount,
          currency: s.currency,
          frequency: s.frequency,
          nextDueDate: s.nextDueDate,
          categoryId: s.categoryId,
          counterparty: s.name,
          status: RecurringStatus.suggested,
          confidence: s.confidence,
          lastPaidDate: s.lastPaidDate,
          occurrences: s.occurrences,
          merchantKey: s.merchantKey,
          createdBy: userId,
        )));
      }
    }
    return created;
  }

  /// Records the payment for [due] and moves the schedule to the next period.
  Future<void> markPaid(RecurringExpense r, DateTime due) async {
    try {
      await _col.doc(r.id).update({
        'lastPaidDate': Timestamp.fromDate(due),
        'nextDueDate': Timestamp.fromDate(r.frequency.advance(due)),
        'occurrences': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Map<String, dynamic> _to(RecurringExpense r) => {
        'workspaceId': r.workspaceId,
        'name': r.name,
        'expectedAmount': r.expectedAmount,
        'currency': r.currency,
        'frequency': r.frequency.name,
        'nextDueDate': Timestamp.fromDate(r.nextDueDate),
        'categoryId': r.categoryId,
        'counterparty': r.counterparty,
        'status': r.status.name,
        'confidence': r.confidence,
        'reminderEnabled': r.reminderEnabled,
        'reminderDaysBefore': r.reminderDaysBefore,
        'lastPaidDate': r.lastPaidDate == null ? null : Timestamp.fromDate(r.lastPaidDate!),
        'occurrences': r.occurrences,
        'merchantKey': r.merchantKey,
        'isManual': r.isManual,
        'createdBy': r.createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  RecurringExpense _from(String id, Map<String, dynamic> d) => RecurringExpense(
        id: id,
        workspaceId: d['workspaceId'] as String,
        name: d['name'] as String? ?? 'Payment',
        expectedAmount: (d['expectedAmount'] as num?)?.toDouble() ?? 0,
        currency: d['currency'] as String? ?? 'INR',
        frequency: RecurringExpense.frequencyFrom(d['frequency']),
        nextDueDate: (d['nextDueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        categoryId: d['categoryId'] as String? ?? 'others',
        counterparty: d['counterparty'] as String?,
        status: RecurringExpense.statusFrom(d['status']),
        confidence: (d['confidence'] as num?)?.toDouble() ?? 1,
        reminderEnabled: d['reminderEnabled'] as bool? ?? true,
        reminderDaysBefore: (d['reminderDaysBefore'] as num?)?.toInt() ?? 2,
        lastPaidDate: (d['lastPaidDate'] as Timestamp?)?.toDate(),
        occurrences: (d['occurrences'] as num?)?.toInt() ?? 0,
        merchantKey: d['merchantKey'] as String?,
        isManual: d['isManual'] as bool? ?? false,
        createdBy: d['createdBy'] as String? ?? '',
      );
}
