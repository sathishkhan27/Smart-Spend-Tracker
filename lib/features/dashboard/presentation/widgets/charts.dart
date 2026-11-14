import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../core/utils/formatters.dart';
import '../../../transactions/domain/category.dart';
import '../../domain/period_aggregate.dart';

Color incomeColor(BuildContext c) => c.isDark ? AppColors.chartIncomeDark : AppColors.chartIncome;
Color expenseColor(BuildContext c) => c.isDark ? AppColors.chartExpenseDark : AppColors.chartExpense;
List<Color> palette(BuildContext c) => c.isDark ? AppColors.chartPaletteDark : AppColors.chartPalette;

/// Legend chip — identity is never color-alone.
class LegendDot extends StatelessWidget {
  const LegendDot(this.color, this.label, {super.key});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
      ]);
}

/// Buckets for the income-vs-expense chart: weeks for a month, months for a
/// year, days/weeks/months for a custom range.
List<(String, CashFlow)> flowBuckets(PeriodAggregate agg, DateRangePeriod period) {
  final days = period.end.difference(period.start).inDays;
  if (period.type == PeriodType.yearly || days > 92) {
    final out = <(String, CashFlow)>[];
    var c = DateTime(period.start.year, period.start.month);
    while (c.isBefore(period.end)) {
      out.add((Fmt.monthShort(c), agg.byMonth[Fmt.monthKey(c)] ?? CashFlow()));
      c = DateTime(c.year, c.month + 1);
    }
    return out;
  }
  if (days <= 14) {
    return [
      for (var d = period.start; d.isBefore(period.end); d = d.add(const Duration(days: 1)))
        ('${d.day}', agg.byDay[Fmt.dayKey(d)] ?? CashFlow()),
    ];
  }
  final out = <(String, CashFlow)>[];
  var start = period.start;
  var i = 1;
  while (start.isBefore(period.end)) {
    final end = start.add(const Duration(days: 7));
    final f = CashFlow();
    for (var d = start; d.isBefore(end) && d.isBefore(period.end); d = d.add(const Duration(days: 1))) {
      final x = agg.byDay[Fmt.dayKey(d)];
      if (x != null) {
        f.inflow += x.inflow;
        f.outflow += x.outflow;
        f.count += x.count;
      }
    }
    out.add(('W$i', f));
    start = end;
    i++;
  }
  return out;
}

class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({super.key, required this.buckets, required this.currency});
  final List<(String, CashFlow)> buckets;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final inc = incomeColor(context), exp = expenseColor(context);
    final maxY = buckets.fold<double>(0, (m, b) => [m, b.$2.inflow, b.$2.outflow].reduce((a, c) => a > c ? a : c));
    final barW = buckets.length > 8 ? 6.0 : 10.0;
    return Column(children: [
      Row(children: [LegendDot(inc, 'Income'), const SizedBox(width: 16), LegendDot(exp, 'Expense')]),
      const SizedBox(height: 16),
      SizedBox(
        height: 190,
        child: BarChart(
          BarChartData(
            maxY: maxY == 0 ? 1 : maxY * 1.15,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY == 0 ? 1 : maxY / 3,
              getDrawingHorizontalLine: (_) => FlLine(color: context.theme.dividerColor, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: maxY == 0 ? 1 : maxY / 3,
                  getTitlesWidget: (v, meta) => v == meta.max
                      ? const SizedBox()
                      : Text(Fmt.compact(v, currency: currency), style: TextStyle(fontSize: 10, color: context.secondaryText)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(buckets[v.toInt()].$1, style: TextStyle(fontSize: 10, color: context.secondaryText)),
                  ),
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.navy,
                getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                  '${buckets[group.x].$1} • ${rodIndex == 0 ? 'Income' : 'Expense'}\n${Fmt.money(rod.toY, currency: currency)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < buckets.length; i++)
                BarChartGroupData(x: i, barsSpace: 2, barRods: [
                  BarChartRodData(toY: buckets[i].$2.inflow, color: inc, width: barW, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  BarChartRodData(toY: buckets[i].$2.outflow, color: exp, width: barW, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ]),
            ],
          ),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        ),
      ),
    ]);
  }
}

/// Spending by dashboard group (fixed order → stable colors per group).
class CategoryDonut extends StatefulWidget {
  const CategoryDonut({super.key, required this.agg});
  final PeriodAggregate agg;

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final groups = widget.agg.groupTotals(income: false);
    final colors = palette(context);
    final entries = [
      for (var i = 0; i < Categories.expenseGroups.length; i++) (Categories.expenseGroups[i], groups[Categories.expenseGroups[i]] ?? 0, colors[i]),
    ];
    final total = widget.agg.outflow;
    final touched = _touched == null ? null : entries[_touched!];
    return Row(children: [
      SizedBox(
        width: 150,
        height: 150,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 46,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(touchCallback: (e, r) {
                if (!e.isInterestedForInteractions || r?.touchedSection == null) {
                  setState(() => _touched = null);
                  return;
                }
                final i = r!.touchedSection!.touchedSectionIndex;
                final visible = entries.where((e) => e.$2 > 0).toList();
                setState(() => _touched = i < 0 || i >= visible.length ? null : entries.indexOf(visible[i]));
              }),
              sections: [
                for (final e in entries.where((e) => e.$2 > 0))
                  PieChartSectionData(
                    value: e.$2,
                    color: e.$3,
                    showTitle: false,
                    radius: touched?.$1 == e.$1 ? 24 : 18,
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 600),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(touched?.$1 ?? 'Spent', style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
            Text(Fmt.compact(touched?.$2 ?? total, currency: widget.agg.currency), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: e.$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(e.$1, style: context.text.bodySmall)),
                Text(total == 0 ? '0%' : Fmt.percent(e.$2 / total * 100),
                    style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// Single-series spend trend (cumulative within a month, per month for a year).
class ExpenseTrendLine extends StatelessWidget {
  const ExpenseTrendLine({super.key, required this.points, required this.currency, this.label = 'Expense'});
  final List<(String, double)> points;
  final String currency;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = expenseColor(context);
    final maxY = points.fold<double>(0, (m, p) => p.$2 > m ? p.$2 : m);
    final step = (points.length / 6).ceil().clamp(1, 100);
    return SizedBox(
      height: 170,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY == 0 ? 1 : maxY / 3,
            getDrawingHorizontalLine: (_) => FlLine(color: context.theme.dividerColor, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: maxY == 0 ? 1 : maxY / 3,
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox()
                    : Text(Fmt.compact(v, currency: currency), style: TextStyle(fontSize: 10, color: context.secondaryText)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i % step != 0 || i >= points.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(points[i].$1, style: TextStyle(fontSize: 10, color: context.secondaryText)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.navy,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('${points[s.x.toInt()].$1} • $label\n${Fmt.money(s.y, currency: currency)}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2)],
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 600),
      ),
    );
  }
}

/// Horizontal magnitude bars (single hue) — payment modes, banks, users.
class BreakdownBars extends StatelessWidget {
  const BreakdownBars({super.key, required this.data, required this.currency, this.max = 6, this.icons, this.onTap});
  final Map<String, double> data;
  final String currency;
  final int max;
  final IconData Function(String key)? icons;

  /// Makes each row tappable (e.g. open the matching transactions).
  final void Function(String key)? onTap;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No spending in this period', style: TextStyle(color: context.secondaryText)),
      );
    }
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final top = entries.first.value;
    final color = incomeColor(context);
    return Column(children: [
      for (final e in entries.take(max))
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap == null ? null : () => onTap!(e.key),
          child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          child: Row(children: [
            if (icons != null) ...[Icon(icons!(e.key), size: 18, color: context.secondaryText), const SizedBox(width: 10)],
            SizedBox(width: 92, child: Text(e.key, style: context.text.bodySmall, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Tooltip(
                message: '${e.key}: ${Fmt.money(e.value, currency: currency)} (${Fmt.percent(e.value / total * 100)})',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: e.value / top),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 10,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              child: Text(Fmt.compact(e.value, currency: currency),
                  textAlign: TextAlign.right, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 18, color: context.secondaryText),
            ],
          ]),
        ),
        ),
    ]);
  }
}
