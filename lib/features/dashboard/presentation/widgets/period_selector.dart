import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/date_range.dart';

/// Monthly / Yearly / Custom period control with prev/next stepping.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.period, required this.onChanged, this.allowCustom = true, this.compact = false});
  final DateRangePeriod period;
  final ValueChanged<DateRangePeriod> onChanged;
  final bool allowCustom;

  /// Single slim row (◀ label ▾ ▶); the period type is chosen from the label's sheet.
  final bool compact;

  Future<void> _pickMonth(BuildContext context) async {
    final now = AppClock.now();
    var year = period.start.year;
    final picked = await showModalBottomSheet<DateRangePeriod>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(onPressed: () => set(() => year--), icon: const Icon(Icons.chevron_left_rounded)),
              Text('$year', style: ctx.text.titleLarge),
              IconButton(onPressed: year >= now.year ? null : () => set(() => year++), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            const SizedBox(height: 8),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              shrinkWrap: true,
              childAspectRatio: 1.8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  Builder(builder: (_) {
                    final selected = period.type == PeriodType.monthly && period.start.year == year && period.start.month == m;
                    final future = DateTime(year, m).isAfter(now);
                    return Material(
                      color: selected ? AppColors.navy : (ctx.isDark ? Colors.white10 : AppColors.background),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, DateRangePeriod.month(year, m)),
                        child: Center(
                          child: Text(
                            const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : (future ? ctx.secondaryText : null),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ]),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  Future<void> _pickYear(BuildContext context) async {
    final now = AppClock.now();
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var y = now.year; y >= now.year - 5; y--)
            ListTile(
              title: Text('$y'),
              trailing: period.start.year == y ? const Icon(Icons.check_rounded, color: AppColors.blue) : null,
              onTap: () => Navigator.pop(ctx, y),
            ),
        ]),
      ),
    );
    if (picked != null) onChanged(DateRangePeriod.year(picked));
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = AppClock.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: period.start, end: period.lastDay.isAfter(now) ? now : period.lastDay),
    );
    if (r != null) onChanged(DateRangePeriod.custom(r.start, r.end));
  }

  void _setType(BuildContext context, PeriodType t) {
    final now = AppClock.now();
    switch (t) {
      case PeriodType.monthly:
        onChanged(DateRangePeriod.month(now.year, now.month));
      case PeriodType.yearly:
        onChanged(DateRangePeriod.year(period.start.year));
      case PeriodType.custom:
        _pickCustom(context);
    }
  }

  Future<void> _pickAny(BuildContext context) async {
    const options = [
      (PeriodType.monthly, Icons.calendar_view_month_rounded, 'Month'),
      (PeriodType.yearly, Icons.calendar_today_rounded, 'Year'),
      (PeriodType.custom, Icons.date_range_rounded, 'Custom range'),
    ];
    final type = await showModalBottomSheet<PeriodType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Show transactions for', style: ctx.text.titleMedium)),
            for (final (t, icon, label) in options)
              if (allowCustom || t != PeriodType.custom)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(icon, color: AppColors.blue),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: period.type == t ? const Icon(Icons.check_circle_rounded, color: AppColors.blue) : const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(ctx, t),
                ),
          ]),
        ),
      ),
    );
    if (type == null || !context.mounted) return;
    switch (type) {
      case PeriodType.monthly:
        await _pickMonth(context);
      case PeriodType.yearly:
        await _pickYear(context);
      case PeriodType.custom:
        await _pickCustom(context);
    }
  }

  Widget _compact(BuildContext context, bool canNext) {
    return Row(children: [
        _ArrowButton(icon: Icons.chevron_left_rounded, tooltip: 'Previous', size: 34, onTap: () => onChanged(period.previous())),
        const SizedBox(width: 6),
        Expanded(
          child: Material(
            color: context.isDark ? Colors.white10 : AppColors.navy.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickAny(context),
              child: SizedBox(
                height: 34,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.blue),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(period.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: context.secondaryText),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _ArrowButton(icon: Icons.chevron_right_rounded, tooltip: 'Next', size: 34, onTap: canNext ? () => onChanged(period.next()) : null),
      ]);
  }

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    final canNext = period.end.isBefore(DateTime(now.year, now.month, now.day).add(const Duration(days: 1)));
    final types = [PeriodType.monthly, PeriodType.yearly, if (allowCustom) PeriodType.custom];
    const labels = {PeriodType.monthly: 'Monthly', PeriodType.yearly: 'Yearly', PeriodType.custom: 'Custom'};
    if (compact) return _compact(context, canNext);
    final selectedText = context.isDark ? Colors.white : AppColors.navy;
    final idleText = context.secondaryText;
    return Column(children: [
      // Pill tab control with a sliding highlight.
      Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white10 : AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / types.length;
          final i = types.indexOf(period.type);
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: w * i,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  color: context.isDark ? AppColors.blue : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2))],
                ),
              ),
            ),
            Row(children: [
              for (final t in types)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setType(context, t),
                    child: Center(
                      child: Text(
                        labels[t]!,
                        style: context.text.labelLarge?.copyWith(
                          fontWeight: t == period.type ? FontWeight.w700 : FontWeight.w500,
                          color: t == period.type ? selectedText : idleText,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _ArrowButton(icon: Icons.chevron_left_rounded, tooltip: 'Previous', onTap: () => onChanged(period.previous())),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => switch (period.type) {
              PeriodType.monthly => _pickMonth(context),
              PeriodType.yearly => _pickYear(context),
              PeriodType.custom => _pickCustom(context),
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.blue),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(period.label,
                      style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 20, color: idleText),
              ]),
            ),
          ),
        ),
        _ArrowButton(icon: Icons.chevron_right_rounded, tooltip: 'Next', onTap: canNext ? () => onChanged(period.next()) : null),
      ]),
    ]);
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.tooltip, this.onTap, this.size = 38});
  final double size;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = !enabled ? Colors.transparent : (context.isDark ? Colors.white10 : Colors.white);
    final border = context.isDark ? Colors.white12 : AppColors.divider;
    final fg = enabled ? null : context.secondaryText.withValues(alpha: 0.4);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: 22, color: fg)),
        ),
      ),
    );
  }
}
