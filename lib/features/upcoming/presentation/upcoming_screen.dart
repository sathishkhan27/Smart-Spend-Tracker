import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/common.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../domain/due_status.dart';
import '../domain/recurring_expense.dart';
import 'widgets/due_alert_banner.dart';
import 'widgets/upcoming_card.dart';

class UpcomingScreen extends ConsumerWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = AppClock.now();
    final async = ref.watch(recurringProvider);
    final upcoming = ref.watch(upcomingForPeriodProvider(DateRangePeriod.month(now.year, now.month)));
    final currency = ref.watch(activeWorkspaceProvider).value?.currency ?? 'INR';
    final total = upcoming.where((u) => u.expense.currency == currency).fold<double>(0, (s, u) => s + u.expense.expectedAmount);

    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming')),
      floatingActionButton: Padding(
        // Sit above the floating bottom menu.
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.recurringEdit),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add recurring'),
      ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(e),
        data: (list) {
          final suggested = list.where((r) => r.status == RecurringStatus.suggested).toList();
          final active = list.where((r) => r.status == RecurringStatus.active || r.status == RecurringStatus.paused).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 180), children: [
            AppCard(
              gradient: AppColors.heroGradient,
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Next 30 days', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(Fmt.money(total, currency: currency),
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ),
                    Text('${upcoming.length} predicted payment${upcoming.length == 1 ? '' : 's'} • not counted as spent',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 24),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            const DueAlertBanner(showAll: true),
            if (upcoming.isNotEmpty) ...[
              const SectionHeader('Due soon'),
              SizedBox(
                height: 176,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: upcoming.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(width: 210, child: UpcomingCard(item: upcoming[i])),
                ),
              ),
            ],
            if (suggested.isNotEmpty) ...[
              const SectionHeader('Detected recurring payments', subtitle: 'Confirm to track them as upcoming spend'),
              for (final r in suggested) _SuggestionTile(r),
            ],
            const SectionHeader('Your schedules'),
            if (active.isEmpty)
              const AppCard(
                child: EmptyState(
                  icon: Icons.autorenew_rounded,
                  title: 'No recurring schedules yet',
                  message: 'Add rent, EMIs, bills or subscriptions to get reminders.',
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(children: [for (final r in active) _ScheduleTile(r)]),
              ),
          ]);
        },
      ),
    );
  }
}

class _SuggestionTile extends ConsumerWidget {
  const _SuggestionTile(this.r);
  final RecurringExpense r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(recurringRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            CategoryAvatar(r.category, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('${r.frequency.label} • ~${Fmt.money(r.expectedAmount, currency: r.currency)} • seen ${r.occurrences}×',
                    style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${(r.confidence * 100).round()}% sure', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.blue)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                onPressed: () => repo.setStatus(r.id, RecurringStatus.dismissed),
                child: const Text('Not recurring'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                onPressed: () => repo.setStatus(r.id, RecurringStatus.active),
                child: const Text('Confirm'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ScheduleTile extends ConsumerWidget {
  const _ScheduleTile(this.r);
  final RecurringExpense r;

  /// Paid within the last 25 days (current cycle) — e.g. EMI auto-debit matched.
  static bool _recentlyPaid(RecurringExpense r, DateTime now) {
    final p = r.lastPaidDate;
    return p != null && now.difference(p).inDays.abs() <= 25;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = AppClock.now();
    final next = r.currentDue(now);
    final status = r.dueStatus(now);
    final paused = r.status == RecurringStatus.paused;
    return Opacity(
      opacity: paused ? 0.55 : 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        onTap: () => context.push(Routes.recurringEdit, extra: r),
        leading: CategoryAvatar(r.category, size: 40),
        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(paused ? 'Paused • ${r.frequency.label}' : '${r.frequency.label} • ${status.level == DueLevel.overdue ? 'was due' : 'next'} ${Fmt.relativeDay(next, now)}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Fmt.money(r.expectedAmount, currency: r.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (!paused && status.level.isAlert)
            DueChip(status)
          else if (_recentlyPaid(r, now))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.income.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text('Paid ✓ ${Fmt.shortDate(r.lastPaidDate!)}',
                  style: const TextStyle(color: AppColors.income, fontSize: 10.5, fontWeight: FontWeight.w700)),
            )
          else
            Icon(r.reminderEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 16, color: context.secondaryText),
        ]),
      ),
    );
  }
}
