import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/category_icon.dart';
import '../../../transactions/domain/engines/bank_templates.dart';
import '../../domain/category.dart';
import '../../domain/transaction_enums.dart';
import '../../domain/transaction_filter.dart';

Future<TransactionFilter?> showFilterSheet(BuildContext context, WidgetRef ref, TransactionFilter initial) =>
    showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: initial),
    );

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});
  final TransactionFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TransactionFilter f = widget.initial;
  late final _counterparty = TextEditingController(text: widget.initial.counterparty ?? '');

  @override
  void dispose() {
    _counterparty.dispose();
    super.dispose();
  }

  /// [scroll] = one horizontally scrolling line instead of a wrapping block.
  Widget _section(String title, List<Widget> chips, {bool scroll = false, String? value}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 14),
        Row(children: [
          Text(title, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (value != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text('• $value',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        if (scroll)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => chips[i],
            ),
          )
        else
          Wrap(spacing: 6, runSpacing: 6, children: chips),
      ]);

  Widget _chip(String label, bool selected, VoidCallback onTap, {Widget? avatar}) => FilterChip(
        label: Text(label),
        avatar: avatar,
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.blue : null),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: selected ? AppColors.blue : (context.isDark ? Colors.white12 : AppColors.divider)),
        selectedColor: AppColors.blue.withValues(alpha: 0.12),
        showCheckmark: false,
      );

  /// Selected item first so the current choice is always visible in a scrolling row.
  List<T> _selectedFirst<T>(List<T> items, bool Function(T) isSelected) =>
      [...items.where(isSelected), ...items.where((e) => !isSelected(e))];

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(workspaceMembersProvider).value ?? const [];
    final category = f.categoryId == null ? null : Categories.byId(f.categoryId);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(children: [
        Expanded(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(children: [
                Text('Filters', style: context.text.titleLarge),
                if (f.activeCount > 0) ...[
                  const SizedBox(width: 8),
                  CircleAvatar(radius: 11, backgroundColor: AppColors.blue, child: Text('${f.activeCount}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700))),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    f = f.cleared();
                    _counterparty.clear();
                  }),
                  child: const Text('Reset'),
                ),
              ]),
              _section('Type & source', [
                _chip('Money in', f.direction == TxDirection.inflow,
                    () => setState(() => f = f.copyWith(direction: f.direction == TxDirection.inflow ? null : TxDirection.inflow))),
                _chip('Money out', f.direction == TxDirection.outflow,
                    () => setState(() => f = f.copyWith(direction: f.direction == TxDirection.outflow ? null : TxDirection.outflow))),
                for (final (src, label) in const [(TxSource.sms, 'SMS'), (TxSource.email, 'Email'), (TxSource.manual, 'Manual')])
                  _chip(label, f.source == src, () => setState(() => f = f.copyWith(source: f.source == src ? null : src))),
              ]),
              _section(
                'Category',
                value: category?.name,
                scroll: true,
                [
                  for (final c in _selectedFirst(Categories.all, (c) => c.id == f.categoryId))
                    _chip(c.name, f.categoryId == c.id,
                        () => setState(() => f = f.copyWith(categoryId: f.categoryId == c.id ? null : c.id, subcategory: null)),
                        avatar: Icon(CategoryIcons.of(c.iconKey), size: 15, color: Color(c.colorValue))),
                ],
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _counterparty,
                    style: context.text.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Merchant / person',
                      prefixIcon: Icon(Icons.storefront_outlined, size: 18),
                    ),
                  ),
                ),
                if (category != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: f.subcategory,
                      style: context.text.bodyMedium,
                      decoration: const InputDecoration(isDense: true, hintText: 'Subcategory'),
                      onChanged: (v) => f = f.copyWith(subcategory: v.trim().isEmpty ? null : v.trim()),
                    ),
                  ),
                ],
              ]),
              _section(
                'Payment mode',
                value: f.paymentMode?.label,
                scroll: true,
                [
                  for (final m in _selectedFirst(PaymentMode.values, (m) => m == f.paymentMode))
                    _chip(m.label, f.paymentMode == m, () => setState(() => f = f.copyWith(paymentMode: f.paymentMode == m ? null : m)),
                        avatar: Icon(CategoryIcons.paymentMode(m), size: 15)),
                ],
              ),
              _section(
                'Bank / card',
                value: f.bankName,
                scroll: true,
                [
                  for (final b in _selectedFirst(
                      defaultTemplates.where((t) => t.kind == InstitutionKind.bank || t.kind == InstitutionKind.creditCard).toList(),
                      (b) => b.name == f.bankName))
                    _chip(b.name, f.bankName == b.name, () => setState(() => f = f.copyWith(bankName: f.bankName == b.name ? null : b.name))),
                ],
              ),
              if (members.length > 1)
                _section('Added by', scroll: true, [
                  for (final m in members)
                    _chip(m.displayName ?? m.email ?? 'Member', f.ownerUserId == m.userId,
                        () => setState(() => f = f.copyWith(ownerUserId: f.ownerUserId == m.userId ? null : m.userId))),
                ]),
              _section('Status', [
                for (final st in [TxStatus.success, TxStatus.needsReview, TxStatus.failed])
                  _chip(st.label, f.status == st, () => setState(() => f = f.copyWith(status: f.status == st ? null : st))),
              ]),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
              onPressed: () {
                final cp = _counterparty.text.trim();
                Navigator.pop(context, f.copyWith(counterparty: cp.isEmpty ? null : cp));
              },
              child: const Text('Show results'),
            ),
          ),
        ),
      ]),
    );
  }
}
