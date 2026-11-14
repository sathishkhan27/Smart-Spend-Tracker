import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/category_icon.dart';
import '../../../../core/widgets/common.dart';
import '../../../dashboard/presentation/dashboard_providers.dart';
import '../../domain/due_status.dart';

/// Upcoming payment card. Dues within two days, due today or overdue are
/// highlighted with a coloured outline, tint and a "Mark paid" action.
class UpcomingCard extends StatelessWidget {
  const UpcomingCard({super.key, required this.item});
  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final r = item.expense;
    final status = item.status;
    final level = status.level;
    final alert = level.isAlert;
    final c = level.color;
    return AppCard(
      padding: const EdgeInsets.all(14),
      borderColor: alert ? c.withValues(alpha: level.isCritical ? 0.9 : 0.6) : null,
      color: alert ? Color.alphaBlend(c.withValues(alpha: context.isDark ? 0.14 : 0.06), context.cardColor) : null,
      onTap: () => context.push(Routes.recurringEdit, extra: r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryAvatar(r.category, size: 38),
          const Spacer(),
          DueChip(status),
        ]),
        const Spacer(),
        Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(Fmt.money(r.expectedAmount, currency: r.currency), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [
          Icon(r.reminderEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 14, color: context.secondaryText),
          const SizedBox(width: 4),
          Expanded(
            child: Text(Fmt.shortDate(item.dueDate),
                style: context.text.labelSmall?.copyWith(color: context.secondaryText), overflow: TextOverflow.ellipsis),
          ),
          if (alert) MarkPaidButton(item: item, compact: true),
        ]),
      ]),
    );
  }
}

/// Coloured status pill: "Overdue 2d", "Due today", "Due tomorrow", "In 2 days"…
class DueChip extends StatelessWidget {
  const DueChip(this.status, {super.key});
  final DueStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.level.color;
    final solid = status.level.isCritical;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: solid ? c : c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status.level.isAlert) ...[
          Icon(status.level.icon, size: 12, color: solid ? Colors.white : c),
          const SizedBox(width: 3),
        ],
        Text(status.label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: solid ? Colors.white : c)),
      ]),
    );
  }
}

class MarkPaidButton extends ConsumerWidget {
  const MarkPaidButton({super.key, required this.item, this.compact = false});
  final UpcomingItem item;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> pay() async {
      try {
        await ref.read(recurringRepositoryProvider).markPaid(item.expense, item.dueDate);
        if (context.mounted) showSnack(context, '${item.expense.name} marked as paid');
      } catch (e) {
        if (context.mounted) showSnack(context, 'Could not update. Try again.', error: true);
      }
    }

    final c = item.status.level.color;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: pay,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 7),
        decoration: BoxDecoration(border: Border.all(color: c.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, size: compact ? 12 : 15, color: c),
          const SizedBox(width: 3),
          Text('Paid', style: TextStyle(fontSize: compact ? 10.5 : 12.5, fontWeight: FontWeight.w700, color: c)),
        ]),
      ),
    );
  }
}
