import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/category_icon.dart';
import '../../../../core/widgets/common.dart';
import '../../../dashboard/presentation/dashboard_providers.dart';
import '../../domain/due_status.dart';
import 'upcoming_card.dart';

/// In-app reminder: lists overdue payments and those due within two days.
/// Hidden when nothing needs attention.
class DueAlertBanner extends ConsumerWidget {
  const DueAlertBanner({super.key, this.showAll = false});

  /// false = compact summary (dashboard), true = every item (Upcoming tab).
  final bool showAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(dueAlertsProvider);
    if (alerts.isEmpty) return const SizedBox.shrink();
    final overdue = alerts.where((a) => a.status.level == DueLevel.overdue).length;
    final top = alerts.first.status.level;
    final c = top.color;
    final shown = showAll ? alerts : alerts.take(2).toList();
    final title = overdue > 0
        ? '$overdue payment${overdue == 1 ? '' : 's'} overdue'
        : '${alerts.length} payment${alerts.length == 1 ? '' : 's'} due soon';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        borderColor: c.withValues(alpha: 0.7),
        color: Color.alphaBlend(c.withValues(alpha: context.isDark ? 0.14 : 0.07), context.cardColor),
        onTap: showAll ? null : () => context.go(Routes.upcoming),
        child: Column(children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(11)),
              child: Icon(top.icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: c)),
                Text('Reminders 2 days & 1 day before due', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
              ]),
            ),
            if (!showAll && alerts.length > shown.length)
              Text('+${alerts.length - shown.length} more', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: c)),
          ]),
          const SizedBox(height: 6),
          for (final a in shown) _Row(a),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.item);
  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final r = item.expense;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        CategoryAvatar(r.category, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text('${Fmt.money(r.expectedAmount, currency: r.currency)} • ${Fmt.shortDate(item.dueDate)}',
                style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
          ]),
        ),
        DueChip(item.status),
        const SizedBox(width: 6),
        MarkPaidButton(item: item, compact: true),
      ]),
    );
  }
}
