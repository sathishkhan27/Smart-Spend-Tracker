import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_clock.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/category_icon.dart';
import '../../domain/transaction.dart';
import '../../domain/transaction_enums.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile(this.tx, {super.key, this.showDetails = false});
  final FinancialTransaction tx;

  /// Shows bank / payment mode / contributor line (history screen).
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final local = AppClock.toLocal(tx.transactionDate);
    final muted = tx.status == TxStatus.failed || tx.isInternalTransfer;
    final amountColor = muted ? context.secondaryText : (tx.isInflow ? AppColors.income : context.text.bodyLarge?.color);
    return InkWell(
      onTap: () => context.push(Routes.transaction(tx.transactionId)),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Stack(clipBehavior: Clip.none, children: [
              CategoryAvatar(tx.category),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: context.cardColor, shape: BoxShape.circle),
                  child: Icon(
                    tx.isInflow ? Icons.south_west_rounded : Icons.north_east_rounded,
                    size: 13,
                    color: tx.isInflow ? AppColors.income : AppColors.expense,
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(tx.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (tx.status != TxStatus.success) ...[const SizedBox(width: 6), _StatusChip(tx.status)],
                    if (tx.isInternalTransfer) ...[const SizedBox(width: 6), const _Chip('Transfer', AppColors.textSecondary)],
                    // Seen in both SMS and email — merged, counted once.
                    if (tx.sources.length > 1) ...[const SizedBox(width: 6), _Chip(tx.sources.map((s) => s.label).join(' + '), AppColors.blue)],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${tx.categoryName} • ${Fmt.relativeDay(local, AppClock.now())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: context.secondaryText),
                  ),
                  if (showDetails) ...[
                    const SizedBox(height: 2),
                    Text(
                      [tx.paymentMode.label, ?tx.bankName, if (tx.ownerName != null) 'by ${tx.ownerName}'].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(color: context.secondaryText),
                    ),
                  ] else if (tx.narration.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(tx.narration, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                Fmt.signed(tx.amount, inflow: tx.isInflow, currency: tx.currency),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                  decoration: tx.status == TxStatus.failed ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(Fmt.time(local), style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final TxStatus status;

  @override
  Widget build(BuildContext context) => _Chip(
        status.label,
        switch (status) {
          TxStatus.failed => AppColors.expense,
          TxStatus.needsReview => AppColors.warning,
          _ => AppColors.textSecondary,
        },
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}
