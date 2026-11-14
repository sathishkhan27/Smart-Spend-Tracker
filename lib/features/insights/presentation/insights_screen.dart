import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/common.dart';
import '../../dashboard/domain/period_aggregate.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../dashboard/presentation/widgets/charts.dart';
import '../../dashboard/presentation/widgets/period_selector.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../../upcoming/domain/recurring_expense.dart';

class _InsightsPeriod extends PeriodNotifier {
  @override
  DateRangePeriod build() => DateRangePeriod.year(AppClock.now().year);
}

final _periodProvider = NotifierProvider<_InsightsPeriod, DateRangePeriod>(_InsightsPeriod.new);

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  bool _exporting = false;

  Future<void> _export({required bool pdf}) async {
    final period = ref.read(_periodProvider);
    final agg = ref.read(periodAggregateProvider(period)).value;
    final wid = ref.read(activeWorkspaceIdProvider);
    if (agg == null || wid == null) return;
    setState(() => _exporting = true);
    try {
      final txs = await ref.read(transactionRepositoryProvider).getRange(wid, period.start, period.end);
      final svc = ref.read(exportServiceProvider);
      final file = pdf
          ? await svc.buildPdf(
              workspaceName: ref.read(activeWorkspaceProvider).value?.name ?? 'Workspace', period: period, agg: agg, transactions: txs)
          : await svc.buildExcel(period: period, agg: agg, transactions: txs);
      await svc.share(file, subject: 'Smart Spend report – ${period.label}');
    } catch (e) {
      if (mounted) showSnack(context, ErrorHandler.map(e).message, error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(_periodProvider);
    final aggAsync = ref.watch(periodAggregateProvider(period));
    final previous = ref.watch(periodAggregateProvider(period.previous())).value;
    final currency = ref.watch(activeWorkspaceProvider).value?.currency ?? 'INR';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights & Reports'),
        actions: [
          PopupMenuButton<bool>(
            enabled: !_exporting,
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_rounded),
            tooltip: 'Export',
            onSelected: (pdf) => _export(pdf: pdf),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Export PDF'))),
              PopupMenuItem(value: false, child: ListTile(leading: Icon(Icons.grid_on_rounded), title: Text('Export Excel'))),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 120), children: [
        ...aggAsync.when(
          loading: () => [_band(period, const Skeleton(height: 190, radius: 20))],
          error: (e, _) => [_band(period, null), ErrorView(e)],
          data: (agg) {
            final items = _content(context, period, agg, previous, currency);
            return [_band(period, items.first), ...items.skip(1)];
          },
        ),
      ]),
    );
  }

  /// Period controls followed by the first content block.
  Widget _band(DateRangePeriod period, Widget? first) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: PeriodSelector(period: period, onChanged: ref.read(_periodProvider.notifier).set),
        ),
        ?first,
      ]);

  List<Widget> _content(BuildContext context, DateRangePeriod period, PeriodAggregate agg, PeriodAggregate? prev, String currency) {
    final yearly = period.type == PeriodType.yearly;
    final high = agg.highestSpendingMonth, low = agg.lowestSpendingMonth;
    String monthName(String key) => Fmt.month(DateTime.parse('$key-01'));
    double? change(double now, double? before) => before == null || before == 0 ? null : (now - before) / before * 100;
    final recurring = (ref.watch(recurringProvider).value ?? const <RecurringExpense>[]).where((r) => r.status == RecurringStatus.active).toList();

    return [
      GridView.count(
        padding: EdgeInsets.zero,
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
        children: [
          _Kpi('${yearly ? 'Yearly' : 'Total'} income', Fmt.money(agg.inflow, currency: currency), change(agg.inflow, prev?.inflow), AppColors.income, goodWhenUp: true),
          _Kpi('${yearly ? 'Yearly' : 'Total'} expenses', Fmt.money(agg.outflow, currency: currency), change(agg.outflow, prev?.outflow), AppColors.expense, goodWhenUp: false),
          _Kpi('Net savings', Fmt.money(agg.net, currency: currency), null, AppColors.blue),
          _Kpi('Transactions', '${agg.count}', change(agg.count.toDouble(), prev?.count.toDouble()), AppColors.navy),
        ],
      ),
      if (high != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _Highlight(Icons.trending_up_rounded, 'Highest spending', monthName(high.key), Fmt.money(high.value.outflow, currency: currency), AppColors.expense)),
          const SizedBox(width: 10),
          Expanded(child: _Highlight(Icons.trending_down_rounded, 'Lowest spending', monthName(low!.key), Fmt.money(low.value.outflow, currency: currency), AppColors.income)),
        ]),
      ],
      const SizedBox(height: 8),
      SectionHeader(yearly ? 'Monthly income vs expense' : 'Income vs expense'),
      AppCard(child: IncomeExpenseBarChart(buckets: flowBuckets(agg, period), currency: currency)),
      if (yearly || agg.byMonth.length > 1) ...[
        const SizedBox(height: 8),
        const SectionHeader('Yearly financial trend', subtitle: 'Monthly expenses'),
        AppCard(
          child: ExpenseTrendLine(
            currency: currency,
            points: [
              for (var c = DateTime(period.start.year, period.start.month); c.isBefore(period.end); c = DateTime(c.year, c.month + 1))
                (Fmt.monthShort(c), agg.byMonth[Fmt.monthKey(c)]?.outflow ?? 0),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SectionHeader('Month-over-month'),
        _MoMTable(agg: agg, currency: currency),
      ],
      const SizedBox(height: 8),
      SectionHeader(yearly ? 'Annual category breakdown' : 'Category-wise spending'),
      AppCard(child: CategoryDonut(agg: agg)),
      const SizedBox(height: 10),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          for (final c in agg.expenseCategories)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => context.go(Routes.transactionsFor(categoryId: c.category.id, period: period)),
              leading: CategoryAvatar(c.category, size: 38),
              title: Text(c.category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${c.count} transactions • ${Fmt.percent(c.percent)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(Fmt.money(c.amount, currency: currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: context.secondaryText),
              ]),
            ),
          if (agg.expenseCategories.isEmpty) const EmptyState(icon: Icons.pie_chart_outline_rounded, title: 'No expenses in this period'),
        ]),
      ),
      const SizedBox(height: 8),
      const SectionHeader('Income sources'),
      AppCard(child: BreakdownBars(data: {for (final c in agg.incomeCategories) c.category.name: c.amount}, currency: currency)),
      const SizedBox(height: 8),
      const SectionHeader('Top counterparties'),
      AppCard(
        child: BreakdownBars(
          data: {for (final e in agg.topCounterparties(8)) e.key: e.value.amount},
          currency: currency,
          max: 8,
          onTap: (name) => context.go(Routes.transactionsFor(search: name, outflowOnly: true, period: period)),
        ),
      ),
      const SizedBox(height: 8),
      const SectionHeader('Spending by member'),
      AppCard(child: BreakdownBars(data: agg.byUser, currency: currency, icons: (_) => Icons.person_outline_rounded)),
      const SizedBox(height: 8),
      const SectionHeader('Spending by bank'),
      AppCard(
        child: BreakdownBars(
          data: agg.byBank,
          currency: currency,
          icons: (_) => Icons.account_balance_outlined,
          onTap: (bank) => context.go(Routes.transactionsFor(bankName: bank, outflowOnly: true, period: period)),
        ),
      ),
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
      SectionHeader('Recurring expenses',
          subtitle: recurring.isEmpty
              ? null
              : '≈ ${Fmt.money(recurring.where((r) => r.currency == currency).fold<double>(0, (s, r) => s + r.expectedAmount * 30 / r.frequency.approxDays), currency: currency)} per month'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: recurring.isEmpty
            ? const EmptyState(icon: Icons.autorenew_rounded, title: 'No confirmed recurring expenses')
            : Column(children: [
                for (final r in recurring)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CategoryAvatar(r.category, size: 38),
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${r.frequency.label} • next ${Fmt.shortDate(r.nextOccurrenceAfter(AppClock.now()))}'),
                    trailing: Text(Fmt.money(r.expectedAmount, currency: r.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
      ),
    ];
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.change, this.color, {this.goodWhenUp});
  final String label;
  final String value;
  final double? change;
  final Color color;
  final bool? goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    final good = goodWhenUp == null ? null : (up == goodWhenUp);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: context.text.labelMedium?.copyWith(color: context.secondaryText), overflow: TextOverflow.ellipsis)),
        ]),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        if (change != null)
          Row(children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: good == null ? context.secondaryText : (good ? AppColors.income : AppColors.expense)),
            Text(' ${Fmt.percent(change!.abs())} vs previous', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
          ])
        else
          const SizedBox(height: 14),
      ]),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight(this.icon, this.label, this.month, this.value, this.color);
  final IconData icon;
  final String label;
  final String month;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
              Text(month, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              Text(value, style: context.text.labelMedium),
            ]),
          ),
        ]),
      );
}

class _MoMTable extends StatelessWidget {
  const _MoMTable({required this.agg, required this.currency});
  final PeriodAggregate agg;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final months = agg.byMonth.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(flex: 3, child: Text('Month', style: context.text.labelMedium?.copyWith(color: context.secondaryText))),
            Expanded(flex: 3, child: Text('Income', textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(color: context.secondaryText))),
            Expanded(flex: 3, child: Text('Expense', textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(color: context.secondaryText))),
            Expanded(flex: 2, child: Text('Δ exp.', textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(color: context.secondaryText))),
          ]),
        ),
        const Divider(),
        for (var i = 0; i < months.length; i++)
          Builder(builder: (_) {
            final m = months[i];
            final prev = i == 0 ? null : months[i - 1].value.outflow;
            final delta = prev == null || prev == 0 ? null : (m.value.outflow - prev) / prev * 100;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(flex: 3, child: Text(Fmt.monthShort(DateTime.parse('${m.key}-01')) + m.key.substring(2, 4), style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(flex: 3, child: Text(Fmt.compact(m.value.inflow, currency: currency), textAlign: TextAlign.right)),
                Expanded(flex: 3, child: Text(Fmt.compact(m.value.outflow, currency: currency), textAlign: TextAlign.right)),
                Expanded(
                  flex: 2,
                  child: Text(
                    delta == null ? '—' : '${delta >= 0 ? '▲' : '▼'}${delta.abs().toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w700, color: delta == null ? null : (delta > 0 ? AppColors.expense : AppColors.income)),
                  ),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}
