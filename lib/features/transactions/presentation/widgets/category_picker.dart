import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/category_icon.dart';
import '../../domain/category.dart';

class CategoryPick {
  const CategoryPick(this.category, this.subcategory, {this.applyToMerchant = true, this.counterparty});
  final CategoryDef category;
  final String? subcategory;
  final bool applyToMerchant;
  final String? counterparty;
}

/// Category + subcategory + counterparty editor used for manual corrections.
Future<CategoryPick?> showCategoryPicker(
  BuildContext context, {
  required bool income,
  String? currentId,
  String? currentSub,
  String? counterparty,
  bool showMerchantOption = true,
}) =>
    showModalBottomSheet<CategoryPick>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Picker(
        income: income,
        currentId: currentId,
        currentSub: currentSub,
        counterparty: counterparty,
        showMerchantOption: showMerchantOption,
      ),
    );

class _Picker extends StatefulWidget {
  const _Picker({required this.income, this.currentId, this.currentSub, this.counterparty, required this.showMerchantOption});
  final bool income;
  final String? currentId;
  final String? currentSub;
  final String? counterparty;
  final bool showMerchantOption;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late String? _selected = widget.currentId;
  late final _sub = TextEditingController(text: widget.currentSub ?? '');
  late final _cp = TextEditingController(text: widget.counterparty ?? '');
  bool _apply = true;
  late bool _showIncome = widget.income;

  @override
  void dispose() {
    _sub.dispose();
    _cp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _showIncome ? Categories.income : Categories.expense;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, controller) => Column(children: [
        Expanded(
          child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
            Text('Categorize', style: context.text.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Expense')), ButtonSegment(value: true, label: Text('Income'))],
              selected: {_showIncome},
              onSelectionChanged: (s) => setState(() => _showIncome = s.first),
            ),
            const SizedBox(height: 16),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.82,
              children: [
                for (final c in cats)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _selected = c.id),
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _selected == c.id ? AppColors.blue : Colors.transparent, width: 2),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CategoryAvatar(c, size: 40),
                        const SizedBox(height: 6),
                        Text(c.name, textAlign: TextAlign.center, maxLines: 2, style: context.text.labelSmall),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _sub, decoration: const InputDecoration(labelText: 'Subcategory (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _cp, decoration: const InputDecoration(labelText: 'Counterparty / merchant')),
            if (widget.showMerchantOption)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _apply,
                onChanged: (v) => setState(() => _apply = v),
                title: const Text('Remember for this merchant'),
                subtitle: const Text('Future transactions from this merchant use this category'),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: FilledButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(
                        context,
                        CategoryPick(
                          Categories.byId(_selected),
                          _sub.text.trim().isEmpty ? null : _sub.text.trim(),
                          applyToMerchant: _apply,
                          counterparty: _cp.text.trim().isEmpty ? null : _cp.text.trim(),
                        ),
                      ),
              child: const Text('Save'),
            ),
          ),
        ),
      ]),
    );
  }
}
