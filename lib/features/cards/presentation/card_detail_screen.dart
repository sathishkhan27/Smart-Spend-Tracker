import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';
import '../../upcoming/domain/due_status.dart';
import '../domain/card_cycle.dart';
import '../domain/credit_card.dart';
import 'card_providers.dart';
import 'credit_card_widgets.dart';

final _cardProvider = StreamProvider.family<CreditCard?, String>((ref, id) => ref.watch(creditCardRepositoryProvider).watchOne(id));
/// Keyed by (workspace, issuer, last4) so card updates don't refetch needlessly.
final _cardTxProvider = FutureProvider.autoDispose.family<List<FinancialTransaction>, (String, String, String)>(
  (ref, k) => ref
      .watch(creditCardRepositoryProvider)
      .recentTransactions(CreditCard(id: '', workspaceId: k.$1, issuer: k.$2, last4: k.$3)),
);

/// One card: limit / available / used, latest statement and its transactions.
class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _remove(BuildContext context, WidgetRef ref, CreditCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${card.issuer} ••${card.last4}?'),
        content: const Text(
            "It will no longer appear under Credit cards, and future messages won't add it again. Your transactions are not affected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(creditCardRepositoryProvider).hide(card.id);
      if (context.mounted) {
        Navigator.of(context).maybePop();
        showSnack(context, '${card.issuer} ••${card.last4} removed');
      }
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref, CreditCard card, CardCycle cycle) async {
    final amount = cycle.state == StatementState.partial ? cycle.remaining : (cycle.statementTotal ?? 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark statement as paid?'),
        content: Text('Records a payment of ${Fmt.money(amount)} for the ${cycle.lastStatementDate == null ? 'latest' : Fmt.shortDate(cycle.lastStatementDate!)} statement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark paid')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(creditCardRepositoryProvider).markPaid(card.id, amount);
      if (context.mounted) showSnack(context, 'Marked as paid');
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _editCycle(BuildContext context, WidgetRef ref, CreditCard card, CardCycle cycle) async {
    // Pre-fill from the statement SMS when we have one (not an old saved value).
    var statement = card.cycleMismatchDay ?? (card.statementFromSms && card.statementAt != null ? card.statementAt!.toLocal().day : null) ?? cycle.statementDay ?? 15;
    var due = card.dueDate?.day ?? cycle.dueDay ?? 5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Billing cycle'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Find these on your card statement or in your bank app.', style: ctx.text.bodySmall?.copyWith(color: ctx.secondaryText)),
            const SizedBox(height: 14),
            _DayPicker(label: 'Statement date', value: statement, onChanged: (v) => set(() => statement = v)),
            const SizedBox(height: 10),
            _DayPicker(label: 'Payment due date', value: due, onChanged: (v) => set(() => due = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(creditCardRepositoryProvider).setCycle(card.id, statementDay: statement, dueDay: due);
      if (context.mounted) showSnack(context, 'Billing cycle saved');
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _editLimit(BuildContext context, WidgetRef ref, CreditCard card) async {
    final c = TextEditingController(text: card.creditLimit?.toStringAsFixed(0) ?? '');
    final value = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Credit limit'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Enter the total limit shown in your bank app. It's used to work out how much of the limit you've used.",
              style: ctx.text.bodySmall?.copyWith(color: ctx.secondaryText)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(prefixText: '₹ ', hintText: 'e.g. 150000'),
          ),
        ]),
        actions: [
          if (card.limitSetManually) TextButton(onPressed: () => Navigator.pop(ctx, -1.0), child: const Text('Use bank SMS')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('Save')),
        ],
      ),
    );
    if (value == null) return;
    try {
      await ref.read(creditCardRepositoryProvider).setLimit(card.id, value < 0 ? null : value);
      if (context.mounted) showSnack(context, value < 0 ? 'Limit will be read from bank SMS' : 'Credit limit saved');
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_cardProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit card'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              final card = async.value;
              if (v == 'remove' && card != null) _remove(context, ref, card);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.credit_card_off_rounded, color: AppColors.expense),
                  title: Text('Not my credit card'),
                  subtitle: Text('Remove it from Smart Spend'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(e),
        data: (card) {
          if (card == null) return const EmptyState(icon: Icons.credit_card_off_rounded, title: 'Card not found');
          final txKey = (card.workspaceId, card.issuer, card.last4);
          final txs = ref.watch(_cardTxProvider(txKey));
          final now = AppClock.now();
          final cycle = ref.watch(cardCyclesProvider).value?[card.id];

          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            CreditCardVisual(card: card, cycle: cycle, compact: false),
            const SizedBox(height: 16),

            // ---- Limits ----
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _Stat(label: 'Available', value: _money(card.availableLimit), color: AppColors.income)),
                  Expanded(child: _Stat(label: 'Used', value: _money(card.used), color: AppColors.expense)),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _editLimit(context, ref, card),
                      child: _Stat(
                        label: 'Credit limit',
                        value: _money(card.creditLimit),
                        color: AppColors.blue,
                        trailing: Icons.edit_rounded,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                if (card.utilization != null) ...[
                  ProgressBar(value: card.utilization!, color: card.utilization! > 0.75 ? AppColors.expense : AppColors.blue, height: 8),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('${(card.utilization! * 100).round()}% of limit used',
                        style: context.text.labelSmall?.copyWith(color: context.secondaryText, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (card.availableAt != null)
                      Text('Updated ${Fmt.relativeDay(AppClock.toLocal(card.availableAt!), now)}',
                          style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
                  ]),
                ] else
                  Row(children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: context.secondaryText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        card.creditLimit == null
                            ? 'Tap "Credit limit" to enter it; then the used amount is shown.'
                            : 'The available limit appears after your next card spend SMS.',
                        style: context.text.labelSmall?.copyWith(color: context.secondaryText),
                      ),
                    ),
                  ]),
              ]),
            ),

            // ---- Billing cycle, statement & next due ----
            const SizedBox(height: 12),
            if (cycle == null)
              const AppCard(child: Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator())))
            else ...[
              if (card.cycleMismatchDay != null) ...[
                _CycleMismatch(
                  card: card,
                  onUse: () async {
                    try {
                      await ref.read(creditCardRepositoryProvider).setCycle(card.id, statementDay: card.cycleMismatchDay!, dueDay: card.dueDate?.day ?? cycle.dueDay ?? 3);
                      if (context.mounted) showSnack(context, 'Billing cycle updated to the ${_ordinal(card.cycleMismatchDay!)}');
                    } on AppFailure catch (e) {
                      if (context.mounted) showSnack(context, e.message, error: true);
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              _CycleCard(card: card, cycle: cycle, onEdit: () => _editCycle(context, ref, card, cycle)),
              const SizedBox(height: 12),
              _StatementCard(cycle: cycle, now: now, onMarkPaid: () => _markPaid(context, ref, card, cycle)),
              const SizedBox(height: 12),
              _HowCalculated(card: card, cycle: cycle),
            ],

            // ---- Transactions on this card ----
            const SizedBox(height: 8),
            const SectionHeader('Transactions on this card'),
            txs.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => AppCard(child: ErrorView(e, onRetry: () => ref.invalidate(_cardTxProvider(txKey)))),
              data: (list) => list.isEmpty
                  ? const AppCard(child: EmptyState(icon: Icons.credit_card_rounded, title: 'No card transactions yet'))
                  : AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(children: [for (final t in list) TransactionTile(t)]),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  static String _money(double? v) => v == null ? '—' : Fmt.money(v);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color, this.trailing});
  final String label;
  final String value;
  final Color color;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: context.secondaryText))),
            if (trailing != null) ...[const SizedBox(width: 3), Icon(trailing, size: 12, color: context.secondaryText)],
          ]),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ]),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.secondaryText))),
          Text(value, style: context.text.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

String _ordinal(int d) {
  if (d >= 11 && d <= 13) return '${d}th';
  return switch (d % 10) { 1 => '${d}st', 2 => '${d}nd', 3 => '${d}rd', _ => '${d}th' };
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: context.text.bodyMedium)),
        DropdownButton<int>(
          value: value,
          underline: const SizedBox(),
          borderRadius: BorderRadius.circular(12),
          items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('${_ordinal(d)} of month'))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ]);
}

/// Billing cycle + current cycle spend.
class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.card, required this.cycle, required this.onEdit});
  final CreditCard card;
  final CardCycle cycle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    final daysLeft = cycle.nextStatement.difference(DateTime(now.year, now.month, now.day)).inDays;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_repeat_rounded, size: 18, color: AppColors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cycle.cycleKnown
                  ? 'Statement on ${_ordinal(cycle.statementDay!)} • due on ${cycle.dueDay == null ? '—' : _ordinal(cycle.dueDay!)}'
                  : 'Billing cycle not set',
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: onEdit, child: Text(cycle.cycleKnown ? 'Edit' : 'Set')),
        ]),
        if (!cycle.cycleKnown)
          Text('Set your statement and due dates to see cycle-wise spending and payment status.',
              style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
        const Divider(height: 22),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cycle.cycleKnown ? 'Current cycle' : 'Last 30 days', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
              const SizedBox(height: 2),
              Text(
                cycle.cycleKnown
                    ? '${Fmt.shortDate(cycle.cycleStart)} – ${Fmt.shortDate(cycle.nextStatement)}'
                    : '${Fmt.shortDate(cycle.cycleStart)} – today',
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Spent so far', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
            const SizedBox(height: 2),
            Text(Fmt.money(cycle.cycleSpent), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ]),
        if (cycle.cycleKnown) ...[
          const SizedBox(height: 10),
          ProgressBar(
            value: (1 - daysLeft / 31).clamp(0.02, 1).toDouble(),
            color: AppColors.blue,
            height: 6,
          ),
          const SizedBox(height: 6),
          Text(daysLeft <= 0 ? 'Statement generates today' : 'Next statement in $daysLeft day${daysLeft == 1 ? '' : 's'} (${Fmt.date(cycle.nextStatement)})',
              style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
        ],
      ]),
    );
  }
}

/// Last statement with payment status, then next due.
class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.cycle, required this.now, required this.onMarkPaid});
  final CardCycle cycle;
  final DateTime now;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final (badge, color) = switch (cycle.state) {
      StatementState.paid => ('Paid ✓', AppColors.income),
      StatementState.partial => ('Partially paid', AppColors.warning),
      StatementState.overdue => ('Overdue', AppColors.expense),
      StatementState.due => (cycle.statementDueDate == null ? 'Due' : DueStatus.of(cycle.statementDueDate!, now).label, AppColors.warning),
      StatementState.none => ('Nothing due', AppColors.income),
      StatementState.unconfirmed => ('Not confirmed', AppColors.textSecondary),
    };
    String m(double? v) => v == null ? '—' : Fmt.money(v);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              cycle.lastStatementDate == null ? 'Statement' : 'Statement of ${Fmt.shortDate(cycle.lastStatementDate!)}',
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _Badge(text: badge, color: color),
        ]),
        const SizedBox(height: 10),
        _Line(cycle.statementEstimated ? 'Statement amount (estimated)' : 'Total amount due', m(cycle.statementTotal), bold: true),
        if (cycle.minDue != null) _Line('Minimum due', m(cycle.minDue)),
        if (cycle.statementDueDate != null) _Line('Due date', Fmt.date(cycle.statementDueDate!)),
        _Line('Paid since statement', m(cycle.paidTowardsStatement)),
        if (cycle.state.owing) _Line('Remaining', m(cycle.remaining), bold: true),
        if (cycle.lastPayment != null)
          _Line('Last payment', '${m(cycle.lastPayment!.amount)} • ${Fmt.date(cycle.lastPayment!.date)}'),
        if (cycle.statementEstimated)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                cycle.state == StatementState.unconfirmed
                    ? "Worked out from card spends; your bank didn't send a statement or payment SMS for this card. If you've paid it, tap Mark as paid."
                    : 'Worked out from card transactions in that cycle. A statement SMS gives the exact amount.',
                style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
          ),
        if (!cycle.state.settled && (cycle.statementTotal ?? 0) > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onMarkPaid,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Mark as paid'),
            ),
          ),
        ],
        const Divider(height: 24),
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: (cycle.state.settled ? AppColors.blue : color).withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.event_rounded, size: 18, color: cycle.state.settled ? AppColors.blue : color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Next due', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
              Text(cycle.nextDueDate == null ? 'Set your billing cycle' : Fmt.date(cycle.nextDueDate!),
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(cycle.state.owing ? 'To pay' : 'Next due amount (so far)', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
            Text(Fmt.money(cycle.state.owing ? cycle.remaining : cycle.cycleSpent), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ]),
    );
  }
}

/// Shows the inputs behind the figures above, so a wrong figure can be traced
/// to the message (or missing message) it came from.
class _HowCalculated extends StatelessWidget {
  const _HowCalculated({required this.card, required this.cycle});
  final CreditCard card;
  final CardCycle cycle;

  @override
  Widget build(BuildContext context) {
    String d(DateTime? v) => v == null ? '—' : Fmt.date(AppClock.toLocal(v));
    String day(DateTime? v) => v == null ? '—' : Fmt.date(v);
    String m(double? v) => v == null ? '—' : Fmt.money(v);
    final rows = <(String, String)>[
      ('Statement SMS received', d(card.statementAt)),
      ('Statement amount (SMS)', m(card.totalDue)),
      ('Minimum due (SMS)', m(card.minDue)),
      ('Due date (SMS)', day(card.dueDate)),
      ('Billing cycle', cycle.cycleKnown ? 'statement ${cycle.statementDay}, due ${cycle.dueDay ?? '—'}${card.statementDay == null ? ' (from SMS)' : ''}' : 'not set'),
      ('Statement used', '${day(cycle.lastStatementDate)} • ${m(cycle.statementTotal)}${cycle.statementEstimated ? ' (estimated from spends)' : ''}'),
      ('Issuer payment SMS', card.lastPaymentAt == null ? 'none' : '${m(card.lastPaymentAmount)} on ${d(card.lastPaymentAt)}'),
      ('Bank-side payments seen', card.paymentHints.isEmpty ? 'none' : card.paymentHints.map((h) => '${m(h.amount)} on ${d(h.at)}').join('\n')),
      ('Payments counted', cycle.countedPayments.isEmpty ? 'none' : cycle.countedPayments.map((p) => '${m(p.amount)} on ${day(p.date)}').join('\n')),
      ('Available limit', card.availableLimit == null ? '—' : '${m(card.availableLimit)} (${d(card.availableAt)})'),
      ('Credit limit', card.creditLimit == null ? 'not known' : '${m(card.creditLimit)}${card.limitSetManually ? ' (set by you)' : ''}'),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: const Icon(Icons.manage_search_rounded, color: AppColors.blue),
          title: Text('How this was calculated', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text('The messages and dates behind these figures', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: Text(k, style: context.text.bodySmall?.copyWith(color: context.secondaryText))),
                  const SizedBox(width: 10),
                  Expanded(flex: 6, child: Text(v, textAlign: TextAlign.right, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Your statement SMS came on 23 Oct, but the cycle is set to the 27th."
class _CycleMismatch extends StatelessWidget {
  const _CycleMismatch({required this.card, required this.onUse});
  final CreditCard card;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final day = card.cycleMismatchDay!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(AppColors.warning.withValues(alpha: context.isDark ? 0.16 : 0.09), context.cardColor),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.event_busy_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your statement SMS came on ${Fmt.date(card.statementAt!.toLocal())}, but the billing cycle is set to the ${_ordinal(card.statementDay!)}. '
              'Dates and "spent so far" use the saved cycle.',
              style: context.text.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
            onPressed: onUse,
            child: Text('Use ${_ordinal(day)}'),
          ),
        ),
      ]),
    );
  }
}
