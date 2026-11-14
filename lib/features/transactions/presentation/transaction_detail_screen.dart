import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/common.dart';
import '../domain/transaction.dart';
import '../domain/transaction_enums.dart';
import 'widgets/category_picker.dart';

final _txProvider = StreamProvider.family<FinancialTransaction?, String>((ref, id) => ref.watch(transactionRepositoryProvider).watch(id));
final _sourceProvider = FutureProvider.family<TransactionSourceDetails?, String>((ref, id) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return null;
  return ref.watch(transactionRepositoryProvider).sourceDetails(id, uid);
});

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(_txProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(e),
        data: (tx) => tx == null
            ? const EmptyState(icon: Icons.delete_outline_rounded, title: 'Transaction not found')
            : _Body(tx: tx, source: ref.watch(_sourceProvider(id)).value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.tx, this.source});
  final FinancialTransaction tx;
  final TransactionSourceDetails? source;

  bool _canEdit(WidgetRef ref) {
    final uid = ref.read(authStateProvider).value?.uid;
    return uid == tx.ownerUserId || (ref.read(myMembershipProvider)?.isAdmin ?? false);
  }

  Future<void> _editCategory(BuildContext context, WidgetRef ref) async {
    final pick = await showCategoryPicker(context,
        income: tx.isInflow, currentId: tx.categoryId, currentSub: tx.subcategory, counterparty: tx.counterparty);
    if (pick == null) return;
    try {
      await ref.read(transactionRepositoryProvider).updateClassification(tx,
          category: pick.category, subcategory: pick.subcategory, counterparty: pick.counterparty);
      final merchant = pick.counterparty ?? tx.counterparty ?? tx.merchant;
      if (pick.applyToMerchant && merchant != null) {
        await ref.read(rulesRepositoryProvider).saveMerchantMapping(
              workspaceId: tx.workspaceId,
              merchant: merchant,
              categoryId: pick.category.id,
              subcategory: pick.subcategory,
              userId: ref.read(authStateProvider).value!.uid,
            );
      }
      if (context.mounted) showSnack(context, 'Updated to ${pick.category.name}');
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This permanently removes it from the shared workspace for everyone. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense, minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(transactionRepositoryProvider).delete(tx.transactionId, ref.read(authStateProvider).value!.uid);
      if (context.mounted) context.pop();
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = AppClock.toLocal(tx.transactionDate);
    final canEdit = _canEdit(ref);
    final isOwner = ref.read(authStateProvider).value?.uid == tx.ownerUserId;
    final catColor = Color(tx.category.colorValue);
    final amountColor = tx.status == TxStatus.failed ? context.secondaryText : (tx.isInflow ? AppColors.income : null);

    String? orNull(String? v) => v == null || v.trim().isEmpty ? null : v;
    final details = <(String, String?, bool)>[
      ('Category', tx.categoryName, false),
      ('Subcategory', orNull(tx.subcategory), false),
      ('Counterparty', orNull(tx.counterparty), false),
      ('Merchant', tx.merchant != tx.counterparty ? orNull(tx.merchant) : null, false),
      ('Type', tx.transactionType.label, false),
      ('UPI ID', orNull(tx.upiId), true),
      ('Reference / UTR', orNull(tx.referenceNumber), true),
    ];
    final account = <(String, String?, bool)>[
      ('Bank', orNull(tx.bankName), false),
      ('Account', orNull(tx.maskedAccountNumber), false),
      ('Sources', tx.sources.map((s) => s.label).join(' + '), false),
      ('Contributed by', orNull(tx.ownerName), false),
      ('Currency', tx.currency, false),
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      // ---- Header ----
      Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.isDark ? Colors.white10 : AppColors.divider.withValues(alpha: 0.7)),
          boxShadow: context.isDark ? null : [BoxShadow(color: AppColors.navy.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            height: 6,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [catColor, catColor.withValues(alpha: 0.4)])),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(children: [
              CategoryAvatar(tx.category, size: 60),
              const SizedBox(height: 12),
              Text(tx.displayName,
                  maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Fmt.signed(tx.amount, inflow: tx.isInflow, currency: tx.currency),
                  style: context.text.headlineMedium?.copyWith(
                    fontSize: 32,
                    color: amountColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    decoration: tx.status == TxStatus.failed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                _Pill(
                  icon: tx.isInflow ? Icons.south_west_rounded : Icons.north_east_rounded,
                  label: tx.isInflow ? 'Money in' : 'Money out',
                  color: tx.isInflow ? AppColors.income : AppColors.expense,
                ),
                _Pill(icon: _statusIcon(tx.status), label: tx.status.label, color: _statusColor(tx.status)),
                if (tx.isInternalTransfer) const _Pill(icon: Icons.swap_horiz_rounded, label: 'Transfer', color: AppColors.textSecondary),
                if (tx.sources.length > 1) _Pill(icon: Icons.merge_type_rounded, label: tx.sources.map((s) => s.label).join(' + '), color: AppColors.blue),
              ]),
              if (tx.narration.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(tx.narration,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4)),
              ],
            ]),
          ),
        ]),
      ),

      if (tx.status == TxStatus.needsReview) ...[
        const SizedBox(height: 12),
        _Notice(
          icon: Icons.info_outline_rounded,
          color: AppColors.warning,
          text: 'Some details could not be extracted. Review and confirm to include it in totals.',
        ),
      ],
      if (tx.sources.length > 1) ...[
        const SizedBox(height: 12),
        _Notice(
          icon: Icons.merge_type_rounded,
          color: AppColors.blue,
          text: 'Found in ${tx.sources.map((s) => s.label).join(' and ')}. These alerts describe the same payment, so it is counted once.',
        ),
      ],

      // ---- Quick facts (2 × 2) ----
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _Fact(icon: Icons.calendar_today_rounded, label: 'Date', value: Fmt.date(local))),
        const SizedBox(width: 10),
        Expanded(child: _Fact(icon: Icons.schedule_rounded, label: 'Time', value: Fmt.time(local))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _Fact(icon: CategoryIcons.paymentMode(tx.paymentMode), label: 'Payment mode', value: tx.paymentMode.label)),
        const SizedBox(width: 10),
        Expanded(
          child: _Fact(
            icon: Icons.account_balance_rounded,
            label: orNull(tx.maskedAccountNumber) != null ? (orNull(tx.bankName) ?? 'Account') : 'Bank',
            value: orNull(tx.maskedAccountNumber) ?? orNull(tx.bankName) ?? '—',
          ),
        ),
      ]),

      // ---- Actions ----
      if (canEdit) ...[
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => _editCategory(context, ref),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit category'),
            ),
          ),
          if (tx.status == TxStatus.needsReview) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => ref.read(transactionRepositoryProvider).setStatus(tx.transactionId, TxStatus.success),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Confirm'),
              ),
            ),
          ],
        ]),
      ],

      // ---- Grouped details ----
      _Section(title: 'Details', rows: details),
      _Section(title: 'Account & source', rows: account),
      const _SectionTitle('Accuracy'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(children: [
          _Meter(label: 'Category match', value: tx.categoryConfidence),
          const SizedBox(height: 12),
          _Meter(label: 'Details extracted', value: tx.extractionConfidence),
        ]),
      ),

      if (canEdit) ...[
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SwitchListTile(
            value: tx.isInternalTransfer,
            onChanged: (v) => ref.read(transactionRepositoryProvider).setInternalTransfer(tx.transactionId, v),
            title: const Text('Internal transfer', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Exclude from income and expense (money moved between own accounts)'),
          ),
        ),
      ],

      if (isOwner && source != null) ...[
        const _SectionTitle('Original message', trailing: 'Only you can see this'),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (source!.smsSender != null) _MiniLine(Icons.sms_outlined, 'SMS from ${source!.smsSender}'),
            if (source!.emailSender != null) _MiniLine(Icons.mail_outline_rounded, 'Email from ${source!.emailSender}'),
            if (source!.emailSubject != null) _MiniLine(Icons.subject_rounded, source!.emailSubject!),
            if (source!.originalNarration != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.isDark ? Colors.white10 : AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: SelectableText(source!.originalNarration!, style: const TextStyle(fontSize: 12, height: 1.45, fontFamily: 'monospace')),
              ),
            ],
          ]),
        ),
      ],

      if (canEdit) ...[
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _delete(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.expense,
            side: BorderSide(color: AppColors.expense.withValues(alpha: 0.4)),
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Delete transaction'),
        ),
      ],
    ]);
  }

  static IconData _statusIcon(TxStatus s) => switch (s) {
        TxStatus.success => Icons.check_circle_rounded,
        TxStatus.failed => Icons.cancel_rounded,
        TxStatus.needsReview => Icons.flag_rounded,
        _ => Icons.timelapse_rounded,
      };

  static Color _statusColor(TxStatus s) => switch (s) {
        TxStatus.success => AppColors.income,
        TxStatus.failed => AppColors.expense,
        TxStatus.needsReview => AppColors.warning,
        _ => AppColors.blue,
      };
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: context.isDark ? 0.14 : 0.08), context.cardColor),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(height: 1.45))),
        ]),
      );
}

/// Compact tile in the 2 × 2 quick-facts grid; fixed height keeps rows even.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: SizedBox(
          height: 40,
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: AppColors.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Text(title.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.secondaryText, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const Spacer(),
          if (trailing != null)
            Row(children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: context.secondaryText),
              const SizedBox(width: 4),
              Text(trailing!, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
            ]),
        ]),
      );
}

/// A titled card of label/value rows separated by hairlines. Empty values are skipped.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<(String, String?, bool)> rows; // (label, value, copyable)

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SectionTitle(title),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.isDark ? Colors.white10 : AppColors.divider),
            _InfoRow(label: visible[i].$1, value: visible[i].$2!, copyable: visible[i].$3),
          ],
        ]),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.copyable = false});
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(value, textAlign: TextAlign.right, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.35));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        Expanded(flex: 4, child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.secondaryText))),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            // Copy icon sits before the value so every value stays right-aligned.
            child: !copyable
                ? valueText
                : InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      showSnack(context, '$label copied');
                    },
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Icon(Icons.copy_rounded, size: 14, color: context.secondaryText),
                      const SizedBox(width: 6),
                      Flexible(child: valueText),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final pct = (value.clamp(0, 1) * 100).round();
    final color = pct >= 80 ? AppColors.income : (pct >= 50 ? AppColors.warning : AppColors.expense);
    return Column(children: [
      Row(children: [
        Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.secondaryText))),
        Text('$pct%', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 6),
      ProgressBar(value: value.clamp(0, 1).toDouble(), color: color),
    ]);
  }
}

class _MiniLine extends StatelessWidget {
  const _MiniLine(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 15, color: context.secondaryText),
          const SizedBox(width: 6),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.secondaryText))),
        ]),
      );
}
