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
import '../domain/category.dart';
import '../domain/engines/duplicate_detector.dart';
import '../domain/engines/transaction_processor.dart';
import '../domain/transaction.dart';
import '../domain/transaction_enums.dart';
import 'widgets/category_picker.dart';

/// Manual entry for cash spends or anything not covered by SMS/email.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _counterparty = TextEditingController();
  final _note = TextEditingController();
  TxDirection _direction = TxDirection.outflow;
  CategoryDef _category = Categories.food;
  String? _sub;
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = AppClock.now();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _counterparty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ctx = ref.read(processingContextProvider);
    if (ctx == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final amount = double.parse(_amount.text.replaceAll(',', ''));
      final cp = _counterparty.text.trim().isEmpty ? null : _counterparty.text.trim();
      final narration = _note.text.trim().isEmpty ? '${_direction == TxDirection.inflow ? 'Received' : 'Paid'}${cp == null ? '' : ' ${_direction == TxDirection.inflow ? 'from' : 'to'} $cp'}' : _note.text.trim();
      final dateUtc = AppClock.toUtc(_date);
      final now = DateTime.now().toUtc();
      await repo.createManual(FinancialTransaction(
        transactionId: repo.newId(),
        workspaceId: ctx.workspaceId,
        ownerUserId: ctx.userId,
        ownerName: ctx.userName,
        amount: amount,
        currency: ref.read(activeWorkspaceProvider).value?.currency ?? 'INR',
        direction: _direction,
        transactionType: _direction == TxDirection.inflow ? TxType.credit : TxType.debit,
        categoryId: _category.id,
        categoryName: _category.name,
        subcategory: _sub,
        counterparty: cp,
        merchant: cp,
        narration: narration,
        transactionDate: dateUtc,
        paymentMode: _mode,
        source: TxSource.manual,
        sources: const [TxSource.manual],
        status: TxStatus.success,
        categoryConfidence: 1,
        extractionConfidence: 1,
        fingerprint: DuplicateDetector.fingerprint(amount: amount, direction: _direction, dateUtc: dateUtc),
        searchKeywords: TransactionProcessor.buildSearchKeywords([cp, narration, _category.name]),
        createdAt: now,
        updatedAt: now,
      ));
      if (mounted) {
        showSnack(context, 'Transaction added');
        context.pop();
      }
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Add transaction')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            SegmentedButton<TxDirection>(
              segments: const [
                ButtonSegment(value: TxDirection.outflow, label: Text('Expense'), icon: Icon(Icons.north_east_rounded)),
                ButtonSegment(value: TxDirection.inflow, label: Text('Income'), icon: Icon(Icons.south_west_rounded)),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() {
                _direction = s.first;
                _category = _direction == TxDirection.inflow ? Categories.otherIncome : Categories.food;
              }),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'),
              validator: (v) {
                final d = double.tryParse((v ?? '').replaceAll(',', ''));
                return d == null || d <= 0 ? 'Enter a valid amount' : null;
              },
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(12),
              onTap: () async {
                final pick = await showCategoryPicker(context,
                    income: _direction == TxDirection.inflow, currentId: _category.id, currentSub: _sub, showMerchantOption: false);
                if (pick != null) {
                  setState(() {
                    _category = pick.category;
                    _sub = pick.subcategory;
                    if (pick.counterparty != null) _counterparty.text = pick.counterparty!;
                  });
                }
              },
              child: Row(children: [
                CategoryAvatar(_category),
                const SizedBox(width: 12),
                Expanded(child: Text(_sub == null ? _category.name : '${_category.name} • $_sub', style: context.text.titleSmall)),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
            const SizedBox(height: 14),
            TextFormField(controller: _counterparty, decoration: const InputDecoration(labelText: 'Paid to / received from', prefixIcon: Icon(Icons.storefront_outlined))),
            const SizedBox(height: 14),
            DropdownButtonFormField<PaymentMode>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Payment mode'),
              items: [for (final m in PaymentMode.values) DropdownMenuItem(value: m, child: Row(children: [Icon(CategoryIcons.paymentMode(m), size: 18), const SizedBox(width: 10), Text(m.label)]))],
              onChanged: (v) => setState(() => _mode = v!),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(14),
              onTap: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime(2015), lastDate: AppClock.now(), initialDate: _date);
                if (d == null || !context.mounted) return;
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
                setState(() => _date = DateTime(d.year, d.month, d.day, t?.hour ?? 12, t?.minute ?? 0));
              },
              child: Row(children: [
                const Icon(Icons.event_rounded, color: AppColors.blue),
                const SizedBox(width: 12),
                Expanded(child: Text('${Fmt.date(_date)} • ${Fmt.time(_date)}')),
                const Icon(Icons.edit_calendar_outlined, size: 20),
              ]),
            ),
            const SizedBox(height: 14),
            TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save transaction')),
          ]),
        ),
      );
}
