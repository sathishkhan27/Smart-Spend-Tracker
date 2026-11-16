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
import '../../sync/data/sync_service.dart';
import '../../sync/domain/sync_progress.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';
import '../../budget/presentation/budget_card.dart';
import '../../cards/presentation/credit_cards_section.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../notifications/presentation/notification_permission_banner.dart';
import '../../sync/presentation/gmail_widgets.dart';
import '../../upcoming/presentation/widgets/due_alert_banner.dart';
import '../../upcoming/presentation/widgets/upcoming_card.dart';
import '../domain/period_aggregate.dart';
import 'dashboard_providers.dart';
import 'widgets/cash_flow_hero.dart';
import 'widgets/charts.dart';
import 'widgets/period_selector.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final aggAsync = ref.watch(periodAggregateProvider(period));
    final txAsync = ref.watch(periodTransactionsProvider(period));
    final currency = ref.watch(activeWorkspaceProvider).value?.currency ?? 'INR';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final ctx = ref.read(processingContextProvider);
          if (ctx == null) return;
          if (ref.read(onlineProvider).value == false) {
            showSnack(context, "You're offline. New messages will sync when you're back online.", error: true);
            return;
          }
          final result = await ref.read(syncServiceProvider).run(SyncRequest(ctx: ctx));
          // New transactions are announced by the sync itself (banner + notification).
          if (!context.mounted || result.newTransactions.isNotEmpty) return;
          showSnack(
            context,
            result.progress.hasFailures ? "Some sources couldn't sync. Check Profile → Connected sources." : "You're up to date. No new transactions.",
            error: result.progress.hasFailures,
          );
        },
        child: CustomScrollView(
          slivers: [
            const _Header(),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList.list(children: [
                ...aggAsync.when(
                  loading: () => [
                    _band(ref, period, const Skeleton(height: 190, radius: 20)),
                    const SizedBox(height: 14),
                    const Skeleton(height: 90, radius: 20),
                  ],
                  error: (e, _) => [_band(ref, period, null), ErrorView(e, onRetry: () => ref.invalidate(periodTransactionsProvider(period)))],
                  data: (agg) {
                    final items = _content(context, ref, period, agg, currency, txAsync.value ?? const []);
                    return [_band(ref, period, items.first), ...items.skip(1)];
                  },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// Period controls, then alerts and the hero card.
  Widget _band(WidgetRef ref, DateRangePeriod period, Widget? hero) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: PeriodSelector(period: period, onChanged: ref.read(dashboardPeriodProvider.notifier).set),
        ),
        if (hero != null) ...[const NotificationPermissionBanner(), const _SyncBanner(), const DueAlertBanner(), hero],
      ]);

  static double _share(double part, PeriodAggregate agg) {
    final total = agg.inflow + agg.outflow;
    return total == 0 ? 0 : part / total;
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, DateRangePeriod period, PeriodAggregate agg, String currency, List txs) {
    final upcoming = ref.watch(upcomingForPeriodProvider(period));
    final upcomingTotal = upcoming.where((u) => u.expense.currency == currency).fold<double>(0, (s, u) => s + u.expense.expectedAmount);
    final recent = txs.take(6).toList();
    return [
      CashFlowHero(
        inflow: agg.inflow,
        outflow: agg.outflow,
        currency: agg.currency,
        periodLabel: period.label,
        onInflowTap: () => context.go(Routes.transactionsFor(inflowOnly: true, period: period)),
        onOutflowTap: () => context.go(Routes.transactionsFor(outflowOnly: true, period: period)),
        footer: agg.refunds > 0 || agg.needsReview > 0
            ? Wrap(spacing: 8, runSpacing: 6, children: [
                if (agg.refunds > 0) _Pill('Refunds ${Fmt.money(agg.refunds, currency: agg.currency)}'),
                if (agg.needsReview > 0) _Pill('${agg.needsReview} need review'),
                if (agg.failed > 0) _Pill('${agg.failed} failed (excluded)'),
              ])
            : null,
      ),
      if (period.type == PeriodType.monthly) ...[
        const SizedBox(height: 14),
        BudgetCard(
          period: period,
          spent: agg.outflow,
          currency: agg.currency,
          onTap: () => context.push(Routes.budgetFor(period)),
        ),
      ],
      const SizedBox(height: 14),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: _MiniStat(
                icon: Icons.south_west_rounded, color: AppColors.income, label: 'Total inflow', value: Fmt.compact(agg.inflow, currency: currency), share: _share(agg.inflow, agg),
                onTap: () => context.go(Routes.transactionsFor(inflowOnly: true, period: period)))),
        const SizedBox(width: 10),
        Expanded(
            child: _MiniStat(
                icon: Icons.north_east_rounded, color: AppColors.expense, label: 'Total outflow', value: Fmt.compact(agg.outflow, currency: currency), share: _share(agg.outflow, agg),
                onTap: () => context.go(Routes.transactionsFor(outflowOnly: true, period: period)))),
        const SizedBox(width: 10),
        Expanded(
            child: _MiniStat(
                icon: Icons.receipt_long_rounded,
                color: AppColors.blue,
                label: 'Transactions',
                value: '${agg.count}',
                onTap: () => context.go(Routes.transactionsFor(period: period)))),
        ]),
      ),
      const ConnectEmailPrompt(),
      const CreditCardsSection(),
      if (agg.otherCurrencies.isNotEmpty) ...[
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 16, runSpacing: 6, children: [
            Text('Other currencies (not converted):', style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
            for (final e in agg.otherCurrencies.entries)
              Text('${e.key}: +${Fmt.money(e.value.inflow, currency: e.key)} / −${Fmt.money(e.value.outflow, currency: e.key)}',
                  style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
      if (agg.isEmpty && txs.isEmpty) ...[
        const SizedBox(height: 16),
        AppCard(
          child: EmptyState(
            icon: Icons.inbox_rounded,
            title: 'No transactions yet',
            message: 'Nothing recorded for ${period.label}. Pull down to refresh or add one manually.',
            action: 'Add transaction',
            onAction: () => context.push(Routes.addTransaction),
          ),
        ),
      ],
      const SizedBox(height: 20),
      _FlowBreakdown(agg: agg, currency: currency),
      const SizedBox(height: 8),
      const SectionHeader('Income vs expense'),
      AppCard(child: IncomeExpenseBarChart(buckets: flowBuckets(agg, period), currency: currency)),
      const SizedBox(height: 8),
      const SectionHeader('Spending by category'),
      AppCard(child: CategoryDonut(agg: agg)),
      const SizedBox(height: 8),
      SectionHeader(period.type == PeriodType.yearly ? 'Monthly expense trend' : 'Cumulative spending'),
      AppCard(child: ExpenseTrendLine(points: _trend(agg, period), currency: currency)),
      const SizedBox(height: 8),
      const SectionHeader('Payment modes'),
      AppCard(
        child: BreakdownBars(
          data: agg.byPaymentMode,
          currency: currency,
          icons: (k) => CategoryIcons.paymentMode(PaymentMode.values.firstWhere((m) => m.label == k, orElse: () => PaymentMode.other)),
          onTap: (k) => context.go(Routes.transactionsFor(
            paymentMode: PaymentMode.values.firstWhere((m) => m.label == k, orElse: () => PaymentMode.other).name,
            outflowOnly: true,
            period: period,
          )),
        ),
      ),
      const SizedBox(height: 8),
      SectionHeader('Category-wise spending', action: 'Insights', onAction: () => context.go(Routes.insights)),
      _CategoryList(agg: agg, currency: currency, period: period),
      const SizedBox(height: 8),
      SectionHeader('Upcoming spend',
          subtitle: upcoming.isEmpty ? null : '${Fmt.money(upcomingTotal, currency: currency)} predicted • not included in totals',
          action: 'Manage',
          onAction: () => context.go(Routes.upcoming)),
      if (upcoming.isEmpty)
        AppCard(
          child: EmptyState(
            icon: Icons.event_available_rounded,
            title: 'No upcoming payments',
            message: 'Confirm detected recurring payments or add your bills.',
            action: 'Add recurring',
            onAction: () => context.push(Routes.recurringEdit),
          ),
        )
      else
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: upcoming.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(width: 210, child: UpcomingCard(item: upcoming[i])),
          ),
        ),
      const SizedBox(height: 8),
      SectionHeader('Recent transactions', action: 'View all', onAction: () => context.go(Routes.transactions)),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: recent.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Nothing here yet')
            : Column(children: [for (final t in recent) TransactionTile(t)]),
      ),
    ];
  }

  List<(String, double)> _trend(PeriodAggregate agg, DateRangePeriod period) {
    if (period.type == PeriodType.yearly || period.end.difference(period.start).inDays > 92) {
      return [
        for (var c = DateTime(period.start.year, period.start.month); c.isBefore(period.end); c = DateTime(c.year, c.month + 1))
          (Fmt.monthShort(c), agg.byMonth[Fmt.monthKey(c)]?.outflow ?? 0),
      ];
    }
    final now = AppClock.now();
    final last = period.end.isAfter(now) ? DateTime(now.year, now.month, now.day + 1) : period.end;
    var running = 0.0;
    return [
      for (var d = period.start; d.isBefore(last); d = d.add(const Duration(days: 1)))
        (Fmt.shortDate(d), running += agg.byDay[Fmt.dayKey(d)]?.outflow ?? 0),
    ];
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final workspace = ref.watch(activeWorkspaceProvider).value;
    final workspaces = ref.watch(myWorkspacesProvider).value ?? const [];
    return SliverAppBar(
      // Scrolls away with the page (a floating transparent bar would overlap content).
      toolbarHeight: 72,
      titleSpacing: 20,
      title: Row(children: [
        const AppLogo(size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${_greeting()}${profile?.firstName.isNotEmpty == true ? ', ${profile!.firstName}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: context.secondaryText, fontWeight: FontWeight.w500)),
            const SizedBox(height: 1),
            GestureDetector(
              onTap: workspaces.length > 1 ? () => _pickWorkspace(context, ref) : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(workspace?.name ?? 'Smart Spend',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.2,fontSize: 13)),
                ),
                if (workspaces.length > 1) Icon(Icons.unfold_more_rounded, size: 18, color: context.secondaryText),
              ]),
            ),
          ]),
        ),
      ]),
      actions: [
        _HeaderButton(
          onTap: () => context.push(Routes.notifications),
          child: const NotificationBell(),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: GestureDetector(
            onTap: () => context.go(Routes.profile),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [AppColors.navy, AppColors.blue], begin: Alignment.bottomLeft, end: Alignment.topRight),
              ),
              child: Text(profile?.initials ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ),
      ],
    );
  }

  static String _greeting() {
    final h = AppClock.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  void _pickWorkspace(BuildContext context, WidgetRef ref) {
    final workspaces = ref.read(myWorkspacesProvider).value ?? const [];
    final current = ref.read(activeWorkspaceIdProvider);
    showModalBottomSheet(
      context: context,
      // Open above the floating bottom nav bar, not inside the tab under it.
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Switch workspace', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          for (final w in workspaces)
            ListTile(
              leading: const Icon(Icons.home_work_outlined),
              title: Text(w.name),
              trailing: w.id == current ? const Icon(Icons.check_circle_rounded, color: AppColors.blue) : null,
              onTap: () {
                ref.read(workspaceRepositoryProvider).updateProfile(ref.read(authStateProvider).value!.uid, {'activeWorkspaceId': w.id});
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.isDark ? Colors.white10 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.isDark ? Colors.white12 : AppColors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(width: 42, height: 42, child: Center(child: child)),
        ),
      );
}

class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(syncProgressProvider).value;
    final profile = ref.watch(profileProvider).value;
    if (p == null) return const SizedBox();
    final show = p.isRunning || p.queued > 0 || (p.hasFailures && p.stage == SyncStage.completed);
    if (!show) return const SizedBox();
    final failed = p.hasFailures && !p.isRunning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: Color.alphaBlend((failed ? AppColors.warning : AppColors.blue).withValues(alpha: 0.1), context.cardColor),
        onTap: failed ? () => context.push(Routes.sources) : null,
        child: Row(children: [
          if (p.isRunning)
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, value: p.fraction))
          else
            Icon(failed ? Icons.warning_amber_rounded : Icons.cloud_upload_outlined, size: 20, color: failed ? AppColors.warning : AppColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.isRunning
                  ? '${profile?.initialSyncComplete == false ? 'Initial sync' : 'Syncing'} • ${p.stage.message}'
                  : failed
                      ? 'Some sources failed to sync. Tap to review.'
                      : '${p.queued} records waiting to upload (offline)',
              style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.color, required this.label, required this.value, this.share = 1, this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  /// 0–1 fill of the ring around the icon.
  final double share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share.clamp(0, 1)),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: v,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 14, color: color),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          Text(label, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
        ]),
      );
}

class _FlowBreakdown extends StatelessWidget {
  const _FlowBreakdown({required this.agg, required this.currency});
  final PeriodAggregate agg;
  final String currency;

  static const _incomeIcons = {
    'Salary': Icons.work_outline_rounded,
    'Business Income': Icons.storefront_outlined,
    'Refund': Icons.replay_rounded,
    'Interest': Icons.savings_outlined,
    'Other Credits': Icons.add_card_rounded,
  };
  static const _expenseIcons = {
    'Food': Icons.restaurant_rounded,
    'Shopping': Icons.shopping_bag_outlined,
    'Travel': Icons.flight_takeoff_rounded,
    'Bills': Icons.receipt_rounded,
    'EMI': Icons.account_balance_outlined,
    'Healthcare': Icons.local_hospital_outlined,
    'Other Expenses': Icons.more_horiz_rounded,
  };

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Column(children: [
            TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [Tab(text: 'Outflow'), Tab(text: 'Inflow')],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 196,
              child: TabBarView(children: [
                _grid(context, agg.groupTotals(income: false), _expenseIcons, AppColors.expense),
                _grid(context, agg.groupTotals(income: true), _incomeIcons, AppColors.income),
              ]),
            ),
          ]),
        ),
      );

  Widget _grid(BuildContext context, Map<String, double> totals, Map<String, IconData> icons, Color color) => GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.15,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final e in icons.entries)
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(e.value, size: 18, color: color),
              ),
              const SizedBox(height: 6),
              Text(Fmt.compact(totals[e.key] ?? 0, currency: currency), style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(e.key, style: context.text.labelSmall?.copyWith(color: context.secondaryText), overflow: TextOverflow.ellipsis),
            ]),
        ],
      );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.agg, required this.currency, required this.period});
  final PeriodAggregate agg;
  final String currency;
  final DateRangePeriod period;

  @override
  Widget build(BuildContext context) {
    final cats = agg.expenseCategories;
    if (cats.isEmpty) {
      return const AppCard(child: EmptyState(icon: Icons.pie_chart_outline_rounded, title: 'No spending yet'));
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(children: [
        for (final c in cats.take(8))
          InkWell(
            borderRadius: BorderRadius.circular(14),
            // Opens Activity filtered to this category and period.
            onTap: () => context.go(Routes.transactionsFor(categoryId: c.category.id, period: period)),
            child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              CategoryAvatar(c.category, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c.category.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                    Text(Fmt.money(c.amount, currency: currency), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  ProgressBar(value: c.percent / 100, color: Color(c.category.colorValue)),
                  const SizedBox(height: 4),
                  Text('${Fmt.percent(c.percent)} of spending • ${c.count} txn${c.count == 1 ? '' : 's'}',
                      style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 20, color: context.secondaryText),
            ]),
          ),
          ),
      ]),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        Skeleton(height: 190, radius: 20),
        SizedBox(height: 14),
        Row(children: [
          Expanded(child: Skeleton(height: 96, radius: 20)),
          SizedBox(width: 10),
          Expanded(child: Skeleton(height: 96, radius: 20)),
          SizedBox(width: 10),
          Expanded(child: Skeleton(height: 96, radius: 20)),
        ]),
        SizedBox(height: 20),
        Skeleton(height: 220, radius: 20),
      ]);
}
