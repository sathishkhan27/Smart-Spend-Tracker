import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../dashboard/presentation/widgets/period_selector.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';
import 'budget_card.dart';

/// A month's budget picture (the monthly budget and that month's spending) plus setting, changing or removing the budgets. Opens on [month]
/// — the month selected on the home page — or the current month.
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key, this.month});

  final DateRangePeriod? month;

  /// `yyyy-MM` → that month, or null.
  static DateRangePeriod? parseMonth(String? key) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key ?? '');
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    return month < 1 || month > 12 ? null : DateRangePeriod.month(int.parse(m.group(1)!), month);
  }

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  final _amount = TextEditingController();
  late DateRangePeriod _month = widget.month ?? _thisMonth();
  bool _filled = false;

  static DateRangePeriod _thisMonth() {
    final now = AppClock.now();
    return DateRangePeriod.month(now.year, now.month);
  }

  /// Only months make sense here; a year/custom pick keeps its first month.
  void _setMonth(DateRangePeriod p) =>
      setState(() => _month = p.type == PeriodType.monthly ? p : DateRangePeriod.month(p.start.year, p.start.month));
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  static double? _parse(String s) {
    final v = double.tryParse(s.replaceAll(',', '').trim());
    return v == null || v <= 0 ? null : v;
  }

  String get _currency {
    final profile = ref.read(profileProvider).value;
    return ref.read(activeWorkspaceProvider).value?.currency ?? profile?.currency ?? 'INR';
  }

  /// Saves [fields] on the profile, then checks the budgets straight away
  /// with the new values so a budget that's already exceeded alerts now.
  Future<void> _write(Map<String, Object?> fields, {required double? overall, required String done}) async {
    final profile = ref.read(profileProvider).value;
    final wid = ref.read(activeWorkspaceIdProvider);
    if (profile == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(workspaceRepositoryProvider).updateProfile(profile.uid, fields);
      if (wid != null) {
        // Alerts for what changed were cleared above, so pass what's left.
        final cleared = ((fields['budgetAlerts'] as Map?) ?? const {}).keys.toSet();
        final alerted = {...profile.budgetAlerts}..removeWhere((k, _) => cleared.contains(k));
        await ref.read(budgetAlerterProvider).check(
              uid: profile.uid,
              workspaceId: wid,
              budget: overall,
              alerted: alerted,
              prefs: profile.notificationPrefs,
              currency: _currency,
            );
      }
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save the budget. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOverall({required bool remove}) async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final value = _parse(_amount.text);
    if (!remove && value == null) {
      showSnack(context, 'Enter a budget amount greater than 0', error: true);
      return;
    }
    final month = Fmt.monthKey(AppClock.now());
    await _write(
      {
        'monthlyBudget': remove ? FieldValue.delete() : value,
        // A changed budget starts this month's alerts afresh.
        'budgetAlerts': {month: FieldValue.delete()},
      },
      overall: remove ? null : value,
      done: remove ? 'Monthly budget removed' : 'Monthly budget saved',
    );
    if (remove) _amount.clear();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final currency = ref.watch(activeWorkspaceProvider).value?.currency ?? profile?.currency ?? 'INR';
    final budget = profile?.monthlyBudget;
    if (!_filled && profile != null) {
      _filled = true;
      if (budget != null) _amount.text = budget.toStringAsFixed(budget % 1 == 0 ? 0 : 2);
    }
    final month = _month;
    final agg = ref.watch(periodAggregateProvider(month)).value;
    final spending = (ref.watch(periodTransactionsProvider(month)).value ?? const [])
        .where((t) => !t.isInflow && t.countsTowardTotals && t.currency == currency)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly budget')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        PeriodSelector(period: month, onChanged: _setMonth, allowCustom: false, compact: true),
        const SizedBox(height: 12),
        if (budget != null && agg != null) ...[
          // Already on the budget screen, so the card isn't tappable here.
          BudgetCard(period: month, spent: agg.outflow, currency: currency),
          const SizedBox(height: 20),
        ],
        Text('Your monthly budget', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            prefixText: '${Fmt.currencySymbol(currency)} ',
            hintText: 'e.g. 30000',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Counts all spending in this workspace for the month (money out; refunds, failed payments and transfers between your own accounts are excluded). '
          "You'll get an alert at 80% and when spending crosses the budget.",
          style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : () => _saveOverall(remove: false),
              child: Text(budget == null ? 'Set budget' : 'Update budget'),
            ),
          ),
          if (budget != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: _saving ? null : () => _saveOverall(remove: true), child: const Text('Remove')),
          ],
        ]),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
            child: Text('Spending in ${Fmt.month(month.start)}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (spending.isNotEmpty)
            TextButton(
              onPressed: () => context.go(Routes.transactionsFor(outflowOnly: true, period: month)),
              child: const Text('See all'),
            ),
        ]),
        const SizedBox(height: 4),
        if (spending.isEmpty)
          Text('No spending recorded for this month.', style: context.text.bodySmall?.copyWith(color: context.secondaryText))
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(children: [for (final t in spending.take(10)) TransactionTile(t)]),
          ),
        if (spending.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('+${spending.length - 10} more — tap See all', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
          ),
        const SizedBox(height: 16),
        Text('Turn budget alerts off under Notification preferences.', style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
      ]),
    );
  }
}
