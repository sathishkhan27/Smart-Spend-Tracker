import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../domain/budget.dart';

extension BudgetLevelX on BudgetLevel {
  Color get color => switch (this) {
        BudgetLevel.onTrack => AppColors.income,
        BudgetLevel.warning => AppColors.warning,
        BudgetLevel.over => AppColors.expense,
      };
}

/// Monthly budget progress for one month: that month's spending against the
/// budget. Shown only for monthly periods.
///
/// [onTap] opens the budget page from the home page; null where the card is
/// already on that page.
class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key, required this.period, required this.spent, required this.currency, this.onTap});

  final DateRangePeriod period;
  final double spent;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (period.type != PeriodType.monthly) return const SizedBox.shrink();
    final budget = ref.watch(profileProvider).value?.monthlyBudget;
    if (budget == null || budget <= 0) {
      if (onTap == null) return const SizedBox.shrink();
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('Set a monthly budget', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          Text('Get alerts', style: context.text.labelMedium?.copyWith(color: context.secondaryText)),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ]),
      );
    }
    final s = BudgetStatus(budget: budget, spent: spent);
    final c = s.level.color;
    String m(double v) => Fmt.money(v, currency: currency);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onTap,
      borderColor: s.level == BudgetLevel.onTrack ? null : c.withValues(alpha: 0.7),
      color: s.level == BudgetLevel.over ? Color.alphaBlend(c.withValues(alpha: context.isDark ? 0.14 : 0.06), context.cardColor) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(s.level == BudgetLevel.over ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.level == BudgetLevel.over ? 'Over budget' : 'Budget',
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: s.level == BudgetLevel.over ? c : null)),
              Text(Fmt.month(period.start), style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
            ]),
          ),
          Text('${s.percent}% used', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: c)),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20),
        ]),
        const SizedBox(height: 10),
        ProgressBar(value: s.fraction.clamp(0, 1).toDouble(), color: c, height: 8),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text('Spent ${m(spent)} of ${m(budget)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: context.secondaryText)),
          ),
          Text(s.level == BudgetLevel.over ? 'Over by ${m(s.overBy)}' : '${m(s.remaining)} left',
              style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: s.level == BudgetLevel.onTrack ? null : c)),
        ]),
      ]),
    );
  }
}
