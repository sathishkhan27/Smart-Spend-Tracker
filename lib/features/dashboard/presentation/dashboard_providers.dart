import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../transactions/domain/transaction.dart';
import '../../upcoming/domain/due_status.dart';
import '../../upcoming/domain/recurring_expense.dart';
import '../domain/period_aggregate.dart';

class PeriodNotifier extends Notifier<DateRangePeriod> {
  @override
  DateRangePeriod build() {
    final now = AppClock.now();
    return DateRangePeriod.month(now.year, now.month);
  }

  void set(DateRangePeriod p) => state = p;
  void previous() => state = state.previous();
  void next() => state = state.next();
}

/// Period selected on the dashboard. Every dashboard widget follows it.
final dashboardPeriodProvider = NotifierProvider<PeriodNotifier, DateRangePeriod>(PeriodNotifier.new);

/// Period selected on the Insights tab (independent of the dashboard).
final insightsPeriodProvider = NotifierProvider<PeriodNotifier, DateRangePeriod>(PeriodNotifier.new);

/// Date-scoped transactions for a period, served from cache then server.
final periodTransactionsProvider = StreamProvider.family<List<FinancialTransaction>, DateRangePeriod>((ref, period) {
  final wid = ref.watch(activeWorkspaceIdProvider);
  if (wid == null) return Stream.value(const []);
  return ref.watch(transactionRepositoryProvider).watchRange(wid, period.start, period.end);
});

/// Server-side monthly aggregates covering a period (null if not available).
final periodStatsProvider = StreamProvider.family<PeriodAggregate?, DateRangePeriod>((ref, period) {
  final wid = ref.watch(activeWorkspaceIdProvider);
  if (wid == null) return Stream.value(null);
  final currency = ref.watch(activeWorkspaceProvider).value?.currency ?? 'INR';
  return ref.watch(monthlyStatsRepositoryProvider).watchMonths(wid, period.monthKeys, currency: currency).handleError((_) {});
});

/// The aggregate shown for a period. Yearly views prefer server aggregates so
/// the device doesn't download a year of transactions; monthly/custom views
/// aggregate the date-scoped query client-side (exact, live).
final periodAggregateProvider = Provider.family<AsyncValue<PeriodAggregate>, DateRangePeriod>((ref, period) {
  final currency = ref.watch(activeWorkspaceProvider).value?.currency ?? 'INR';
  if (period.type == PeriodType.yearly) {
    final stats = ref.watch(periodStatsProvider(period));
    final s = stats.value;
    if (s != null && !s.isEmpty) return AsyncValue.data(s);
  }
  return ref.watch(periodTransactionsProvider(period)).whenData((txs) => FinancialCalculator.aggregate(txs, currency: currency));
});

final recurringProvider = StreamProvider<List<RecurringExpense>>((ref) {
  final wid = ref.watch(activeWorkspaceIdProvider);
  if (wid == null) return Stream.value(const []);
  return ref.watch(recurringRepositoryProvider).watch(wid);
});

class UpcomingItem {
  const UpcomingItem(this.expense, this.dueDate);
  final RecurringExpense expense;
  final DateTime dueDate;

  DueStatus get status => DueStatus.of(dueDate, AppClock.now());
}

/// Active, unpaid dues that need attention now: overdue, due today,
/// tomorrow or in two days. Most urgent first.
final dueAlertsProvider = Provider<List<UpcomingItem>>((ref) {
  final list = ref.watch(recurringProvider).value ?? const [];
  final now = AppClock.now();
  final out = [
    for (final r in list)
      if (r.status == RecurringStatus.active) UpcomingItem(r, r.currentDue(now)),
  ].where((u) => u.status.level.isAlert).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return out;
});

/// Predicted payments (kept separate from actual transactions). For the
/// current/past period it shows the next 30 days; for a future period it shows
/// payments due within that period.
final upcomingForPeriodProvider = Provider.family<List<UpcomingItem>, DateRangePeriod>((ref, period) {
  final list = ref.watch(recurringProvider).value ?? const [];
  final now = AppClock.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = period.start.isAfter(today) ? period.start : today;
  final to = period.start.isAfter(today) ? period.end : today.add(const Duration(days: 30));
  final out = <UpcomingItem>[];
  for (final r in list) {
    if (r.status != RecurringStatus.active) continue;
    // Current period: include unpaid overdue dues; future periods: occurrences in range.
    var d = period.start.isAfter(today) ? r.nextOccurrenceAfter(from) : r.currentDue(now);
    var guard = 0;
    while (d.isBefore(to) && guard++ < 60) {
      out.add(UpcomingItem(r, d));
      d = r.frequency.advance(d);
    }
  }
  out.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return out;
});
