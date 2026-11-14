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
import '../../transactions/domain/category.dart';
import '../../transactions/presentation/widgets/category_picker.dart';
import '../domain/recurring_expense.dart';

/// Create / edit / delete a recurring expense schedule.
class RecurringEditScreen extends ConsumerStatefulWidget {
  const RecurringEditScreen({super.key, this.existing});
  final RecurringExpense? existing;

  @override
  ConsumerState<RecurringEditScreen> createState() => _RecurringEditScreenState();
}

class _RecurringEditScreenState extends ConsumerState<RecurringEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(text: widget.existing?.expectedAmount.toStringAsFixed(0) ?? '');
  late final _counterparty = TextEditingController(text: widget.existing?.counterparty ?? '');
  late RecurrenceFrequency _freq = widget.existing?.frequency ?? RecurrenceFrequency.monthly;
  late CategoryDef _category = widget.existing?.category ?? Categories.rent;
  late DateTime _due = widget.existing?.nextOccurrenceAfter(AppClock.now()) ?? AppClock.now().add(const Duration(days: 7));
  late bool _reminder = widget.existing?.reminderEnabled ?? true;
  late int _daysBefore = widget.existing?.reminderDaysBefore ?? 2;
  late bool _paused = widget.existing?.status == RecurringStatus.paused;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _counterparty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ctx = ref.read(processingContextProvider);
    if (ctx == null) return;
    setState(() => _busy = true);
    final repo = ref.read(recurringRepositoryProvider);
    final e = widget.existing;
    try {
      await repo.save(RecurringExpense(
        id: e?.id ?? repo.newId(),
        workspaceId: ctx.workspaceId,
        name: _name.text.trim(),
        expectedAmount: double.parse(_amount.text.replaceAll(',', '')),
        currency: e?.currency ?? ref.read(activeWorkspaceProvider).value?.currency ?? 'INR',
        frequency: _freq,
        nextDueDate: _due,
        categoryId: _category.id,
        counterparty: _counterparty.text.trim().isEmpty ? null : _counterparty.text.trim(),
        status: _paused ? RecurringStatus.paused : RecurringStatus.active,
        confidence: e?.confidence ?? 1,
        reminderEnabled: _reminder,
        reminderDaysBefore: _daysBefore,
        lastPaidDate: e?.lastPaidDate,
        occurrences: e?.occurrences ?? 0,
        merchantKey: e?.merchantKey,
        isManual: e?.isManual ?? true,
        createdBy: e?.createdBy ?? ctx.userId,
      ));
      if (mounted) context.pop();
    } on AppFailure catch (err) {
      if (mounted) showSnack(context, err.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: const Text('Past transactions are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.expense))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(recurringRepositoryProvider).delete(widget.existing!.id);
      if (mounted) context.pop();
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'New recurring payment' : 'Edit schedule'),
          actions: [if (widget.existing != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded))],
        ),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (e.g. House rent)'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              decoration: const InputDecoration(labelText: 'Expected amount', prefixText: '₹ '),
              validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) ?? 0) <= 0 ? 'Enter an amount' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(controller: _counterparty, decoration: const InputDecoration(labelText: 'Payee / counterparty')),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(12),
              onTap: () async {
                final p = await showCategoryPicker(context, income: false, currentId: _category.id, showMerchantOption: false);
                if (p != null) setState(() => _category = p.category);
              },
              child: Row(children: [
                CategoryAvatar(_category),
                const SizedBox(width: 12),
                Expanded(child: Text(_category.name, style: context.text.titleSmall)),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
            const SizedBox(height: 18),
            Text('Frequency', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in RecurrenceFrequency.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _freq == f,
                  onSelected: (_) => setState(() => _freq = f),
                  selectedColor: AppColors.navy,
                  labelStyle: TextStyle(color: _freq == f ? Colors.white : null),
                  showCheckmark: false,
                ),
            ]),
            const SizedBox(height: 18),
            AppCard(
              padding: const EdgeInsets.all(14),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _due, firstDate: DateTime(2020), lastDate: DateTime(AppClock.now().year + 5));
                if (d != null) setState(() => _due = d);
              },
              child: Row(children: [
                const Icon(Icons.event_rounded, color: AppColors.blue),
                const SizedBox(width: 12),
                Expanded(child: Text('Next due: ${Fmt.date(_due)}')),
                const Icon(Icons.edit_calendar_outlined, size: 20),
              ]),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(children: [
                SwitchListTile(
                  value: _reminder,
                  onChanged: (v) => setState(() => _reminder = v),
                  title: const Text('Reminder'),
                  subtitle: Text('Notify $_daysBefore day${_daysBefore == 1 ? '' : 's'} before'),
                ),
                if (_reminder)
                  Slider(
                    value: _daysBefore.toDouble(),
                    min: 0,
                    max: 7,
                    divisions: 7,
                    label: '$_daysBefore days',
                    onChanged: (v) => setState(() => _daysBefore = v.round()),
                  ),
                SwitchListTile(value: _paused, onChanged: (v) => setState(() => _paused = v), title: const Text('Paused')),
              ]),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save schedule')),
          ]),
        ),
      );
}
