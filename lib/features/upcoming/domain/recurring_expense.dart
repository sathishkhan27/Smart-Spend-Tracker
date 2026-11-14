import '../../transactions/domain/category.dart';
import '../../transactions/domain/transaction_enums.dart';
import 'due_status.dart';

enum RecurrenceFrequency {
  weekly('Weekly', 7),
  monthly('Monthly', 30),
  quarterly('Quarterly', 91),
  halfYearly('Half-yearly', 182),
  yearly('Yearly', 365);

  const RecurrenceFrequency(this.label, this.approxDays);
  final String label;
  final int approxDays;

  DateTime advance(DateTime from) => switch (this) {
        weekly => from.add(const Duration(days: 7)),
        monthly => _addMonths(from, 1),
        quarterly => _addMonths(from, 3),
        halfYearly => _addMonths(from, 6),
        yearly => _addMonths(from, 12),
      };

  static DateTime _addMonths(DateTime d, int months) {
    final target = DateTime(d.year, d.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
  }
}

/// suggested = detected, awaiting user confirmation; active = confirmed/manual.
enum RecurringStatus { suggested, active, paused, dismissed }

class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.expectedAmount,
    required this.frequency,
    required this.nextDueDate,
    required this.categoryId,
    required this.status,
    required this.createdBy,
    this.currency = 'INR',
    this.counterparty,
    this.confidence = 1,
    this.reminderEnabled = true,
    this.reminderDaysBefore = 2,
    this.lastPaidDate,
    this.occurrences = 0,
    this.merchantKey,
    this.isManual = false,
  });

  final String id;
  final String workspaceId;
  final String name;
  final double expectedAmount;
  final String currency;
  final RecurrenceFrequency frequency;

  /// Wall-clock date in workspace timezone.
  final DateTime nextDueDate;
  final String categoryId;
  final String? counterparty;
  final RecurringStatus status;
  final double confidence;
  final bool reminderEnabled;
  final int reminderDaysBefore;
  final DateTime? lastPaidDate;
  final int occurrences;
  final String? merchantKey;
  final bool isManual;
  final String createdBy;

  CategoryDef get category => Categories.byId(categoryId);

  /// Rolls the due date forward past [now] (missed periods are skipped).
  DateTime nextOccurrenceAfter(DateTime now) {
    var d = nextDueDate;
    var guard = 0;
    while (d.isBefore(DateTime(now.year, now.month, now.day)) && guard++ < 500) {
      d = frequency.advance(d);
    }
    return d;
  }

  /// The due date to act on now: an unpaid due up to [DueStatus.overdueGraceDays]
  /// in the past (overdue), otherwise the next occurrence from today.
  DateTime currentDue(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(nextDueDate.year, nextDueDate.month, nextDueDate.day);
    if (due.isBefore(today) && today.difference(due).inDays <= DueStatus.overdueGraceDays) return nextDueDate;
    return nextOccurrenceAfter(now);
  }

  DueStatus dueStatus(DateTime now) => DueStatus.of(currentDue(now), now);

  RecurringExpense copyWith({
    String? name,
    double? expectedAmount,
    RecurrenceFrequency? frequency,
    DateTime? nextDueDate,
    String? categoryId,
    String? counterparty,
    RecurringStatus? status,
    bool? reminderEnabled,
    int? reminderDaysBefore,
  }) =>
      RecurringExpense(
        id: id,
        workspaceId: workspaceId,
        name: name ?? this.name,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        currency: currency,
        frequency: frequency ?? this.frequency,
        nextDueDate: nextDueDate ?? this.nextDueDate,
        categoryId: categoryId ?? this.categoryId,
        counterparty: counterparty ?? this.counterparty,
        status: status ?? this.status,
        confidence: confidence,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
        lastPaidDate: lastPaidDate,
        occurrences: occurrences,
        merchantKey: merchantKey,
        isManual: isManual,
        createdBy: createdBy,
      );

  static RecurringStatus statusFrom(Object? v) => enumByName(RecurringStatus.values, v, RecurringStatus.suggested);
  static RecurrenceFrequency frequencyFrom(Object? v) => enumByName(RecurrenceFrequency.values, v, RecurrenceFrequency.monthly);
}
