import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/common.dart';
import '../../dashboard/presentation/widgets/period_selector.dart';
import '../domain/category.dart';
import '../domain/engines/duplicate_detector.dart';
import '../domain/transaction.dart';
import '../domain/transaction_enums.dart';
import '../domain/transaction_filter.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/transaction_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({
    super.key,
    this.categoryId,
    this.paymentMode,
    this.bankName,
    this.counterparty,
    this.search,
    this.outflowOnly = false,
    this.inflowOnly = false,
    this.period,
    this.navToken,
  });

  /// Pre-applied filters when opened from a category, payment mode, bank or
  /// payee breakdown (Home / Insights).
  final String? categoryId;
  final String? paymentMode; // PaymentMode.name
  final String? bankName;
  final String? counterparty;
  final String? search;
  final bool outflowOnly;
  final bool inflowOnly;
  final DateRangePeriod? period;

  /// Changes on every category tap so the filter is re-applied.
  final String? navToken;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late TransactionFilter _filter;
  final _items = <FinancialTransaction>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _workspaceId;

  @override
  void initState() {
    super.initState();
    _filter = _initialFilter();
    _search.text = widget.search ?? '';
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
  }

  TransactionFilter _initialFilter() {
    final now = AppClock.now();
    PaymentMode? mode;
    for (final m in PaymentMode.values) {
      if (m.name == widget.paymentMode) mode = m;
    }
    return TransactionFilter(
      period: widget.period ?? DateRangePeriod.month(now.year, now.month),
      categoryId: widget.categoryId,
      paymentMode: mode,
      bankName: widget.bankName,
      counterparty: widget.counterparty,
      direction: widget.outflowOnly
          ? TxDirection.outflow
          : widget.inflowOnly
              ? TxDirection.inflow
              : null,
      search: widget.search ?? '',
    );
  }

  @override
  void didUpdateWidget(TransactionsScreen old) {
    super.didUpdateWidget(old);
    // The tab stays alive between visits; apply a new category tap.
    if (widget.navToken != null && widget.navToken != old.navToken) {
      _search.text = widget.search ?? '';
      if (_scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setFilter(_initialFilter());
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Bumped on every reload. A page that arrives for an older generation
  /// (e.g. the first load still in flight when a filter changes) is dropped,
  /// otherwise both result sets are appended and every row — and the
  /// in/out totals — appear twice.
  int _generation = 0;

  Future<void> _reload() async {
    _generation++;
    _items.clear();
    _cursor = null;
    _hasMore = true;
    _error = null;
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    final wid = ref.read(activeWorkspaceIdProvider);
    if (wid == null || (_loading && !force) || !_hasMore) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref.read(transactionRepositoryProvider).page(wid, _filter, after: _cursor);
      if (!mounted || gen != _generation) return;
      setState(() {
        // Copies of one payment can land on different pages.
        final merged = DuplicateDetector.collapse([..._items, ...page.items]);
        _items
          ..clear()
          ..addAll(merged);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } on AppFailure catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  void _setFilter(TransactionFilter f) {
    setState(() => _filter = f);
    _reload();
  }

  /// What the list is narrowed to (shown as a header), most specific first.
  _Selection? _selection() {
    final f = _filter;
    if (f.categoryId != null) {
      final c = Categories.byId(f.categoryId);
      return _Selection(
        title: f.subcategory == null ? c.name : '${c.name} • ${f.subcategory}',
        kindLabel: 'Category',
        avatar: CategoryAvatar(c, size: 44),
        color: Color(c.colorValue),
        income: c.isIncome,
      );
    }
    if (f.paymentMode != null) {
      return _Selection(
        title: f.paymentMode!.label,
        kindLabel: 'Payment mode',
        icon: CategoryIcons.paymentMode(f.paymentMode!),
        color: AppColors.blue,
        income: f.direction == TxDirection.inflow,
      );
    }
    if (f.bankName != null) {
      return _Selection(
          title: f.bankName!, kindLabel: 'Bank', icon: Icons.account_balance_rounded, color: AppColors.navy, income: f.direction == TxDirection.inflow);
    }
    if (f.counterparty != null) {
      return _Selection(
          title: f.counterparty!, kindLabel: 'Payee', icon: Icons.storefront_rounded, color: const Color(0xFF6250D6), income: f.direction == TxDirection.inflow);
    }
    if (f.search.trim().isNotEmpty) {
      return _Selection(
          title: '“${f.search.trim()}”', kindLabel: 'Search', icon: Icons.search_rounded, color: AppColors.blue, income: f.direction == TxDirection.inflow);
    }
    // Only a direction: "Money in" / "Money out" for the period.
    if (f.direction == TxDirection.inflow) {
      return const _Selection(title: 'Money in', kindLabel: 'All inflow', icon: Icons.south_west_rounded, color: AppColors.income, income: true);
    }
    if (f.direction == TxDirection.outflow) {
      return const _Selection(title: 'Money out', kindLabel: 'All outflow', icon: Icons.north_east_rounded, color: AppColors.expense, income: false);
    }
    return null;
  }

  /// One scrollable row: direction, source, review, then removable chips for
  /// every advanced filter applied from the sheet.
  Widget _quickFilters() {
    final f = _filter;
    final members = ref.watch(workspaceMembersProvider).value ?? const [];
    String memberName(String id) {
      for (final m in members) {
        if (m.userId == id) return m.displayName ?? m.email ?? 'Member';
      }
      return 'Member';
    }

    // Filters applied from the sheet or a category tap come first so they're visible.
    final hasApplied = f.categoryId != null ||
        f.subcategory != null ||
        f.counterparty != null ||
        f.paymentMode != null ||
        f.bankName != null ||
        f.ownerUserId != null ||
        f.source == TxSource.manual ||
        (f.status != null && f.status != TxStatus.needsReview);
    return ListView(scrollDirection: Axis.horizontal, children: [
      if (f.categoryId != null) _RemovableChip(Categories.byId(f.categoryId).name, () => _setFilter(f.copyWith(categoryId: null, subcategory: null))),
      if (f.subcategory != null) _RemovableChip(f.subcategory!, () => _setFilter(f.copyWith(subcategory: null))),
      if (f.counterparty != null) _RemovableChip(f.counterparty!, () => _setFilter(f.copyWith(counterparty: null))),
      if (f.paymentMode != null) _RemovableChip(f.paymentMode!.label, () => _setFilter(f.copyWith(paymentMode: null))),
      if (f.bankName != null) _RemovableChip(f.bankName!, () => _setFilter(f.copyWith(bankName: null))),
      if (f.ownerUserId != null) _RemovableChip(memberName(f.ownerUserId!), () => _setFilter(f.copyWith(ownerUserId: null))),
      if (f.source == TxSource.manual) _RemovableChip('Manual', () => _setFilter(f.copyWith(source: null))),
      if (f.status != null && f.status != TxStatus.needsReview) _RemovableChip(f.status!.label, () => _setFilter(f.copyWith(status: null))),
      if (hasApplied) const _ChipDivider(),
      _QuickChip('All', f.direction == null, () => _setFilter(f.copyWith(direction: null))),
      _QuickChip('Money in', f.direction == TxDirection.inflow, () => _setFilter(f.copyWith(direction: f.direction == TxDirection.inflow ? null : TxDirection.inflow))),
      _QuickChip('Money out', f.direction == TxDirection.outflow, () => _setFilter(f.copyWith(direction: f.direction == TxDirection.outflow ? null : TxDirection.outflow))),
      const _ChipDivider(),
      _QuickChip('SMS', f.source == TxSource.sms, () => _setFilter(f.copyWith(source: f.source == TxSource.sms ? null : TxSource.sms)), icon: Icons.sms_outlined),
      _QuickChip('Email', f.source == TxSource.email, () => _setFilter(f.copyWith(source: f.source == TxSource.email ? null : TxSource.email)), icon: Icons.mail_outline_rounded),
      _QuickChip('Review', f.status == TxStatus.needsReview,
          () => _setFilter(f.copyWith(status: f.status == TxStatus.needsReview ? null : TxStatus.needsReview)), icon: Icons.flag_outlined),
      if (f.activeCount > 1)
        TextButton(
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onPressed: () => _setFilter(f.cleared()),
          child: const Text('Clear all'),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final wid = ref.watch(activeWorkspaceIdProvider);
    if (wid != null && wid != _workspaceId) {
      _workspaceId = wid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
    final inflow = _items.where((t) => t.isInflow && t.countsTowardTotals).fold<double>(0, (s, t) => s + t.amount);
    final outflow = _items.where((t) => !t.isInflow && t.countsTowardTotals).fold<double>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(onPressed: () => context.push(Routes.addTransaction), icon: const Icon(Icons.add_circle_outline_rounded), tooltip: 'Add manually'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Compact filter bar: floats back in as soon as you scroll up.
            SliverPersistentHeader(
              floating: true,
              delegate: _FilterBarDelegate(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(children: [
                    SizedBox(
                      height: 44,
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            textInputAction: TextInputAction.search,
                            style: context.text.bodyMedium,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search merchant, note, ref no.',
                              prefixIcon: const Icon(Icons.search_rounded, size: 20),
                              prefixIconConstraints: const BoxConstraints(minWidth: 40),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      onPressed: () {
                                        _search.clear();
                                        _setFilter(_filter.copyWith(search: ''));
                                      }),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (v) {
                              setState(() {});
                              _debounce?.cancel();
                              _debounce = Timer(const Duration(milliseconds: 450), () => _setFilter(_filter.copyWith(search: v)));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterButton(
                          count: _filter.activeCount,
                          onTap: () async {
                            final f = await showFilterSheet(context, ref, _filter);
                            if (f != null) _setFilter(f);
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    PeriodSelector(compact: true, period: _filter.period, onChanged: (p) => _setFilter(_filter.copyWith(period: p))),
                    const SizedBox(height: 8),
                    SizedBox(height: 32, child: _quickFilters()),
                  ]),
                ),
              ),
            ),
            if (_selection() case final sel?)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _SelectionHeader(
                    selection: sel,
                    period: _filter.period.label,
                    count: _items.length,
                    hasMore: _hasMore,
                    loading: _loading && _items.isEmpty,
                    total: sel.income ? inflow : outflow,
                    onClear: () {
                      _search.clear();
                      _setFilter(_filter.cleared().copyWith(search: ''));
                    },
                  ),
                ),
              )
            else if (_items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    Text('${_items.length}${_hasMore ? '+' : ''} transactions',
                        style: context.text.labelSmall?.copyWith(color: context.secondaryText, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    _Total(icon: Icons.south_west_rounded, color: AppColors.chartIncome, value: Fmt.compact(inflow)),
                    const SizedBox(width: 10),
                    _Total(icon: Icons.north_east_rounded, color: AppColors.chartExpense, value: Fmt.compact(outflow)),
                  ]),
                ),
              ),
            if (_error != null && _items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(_error!, onRetry: _reload))
            else if (_items.isEmpty && !_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                // Bottom inset keeps it centred in the area above the floating menu.
                child: Padding(
                  padding: EdgeInsets.only(bottom: 110),
                  child: EmptyState(icon: Icons.search_off_rounded, title: 'No transactions found', message: 'Try another period, or clear some filters.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: _items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : Text(_hasMore ? '' : 'End of list', style: TextStyle(color: context.secondaryText)),
                        ),
                      );
                    }
                    final t = _items[i];
                    final day = Fmt.date(AppClock.toLocal(t.transactionDate));
                    final showHeader = i == 0 || Fmt.date(AppClock.toLocal(_items[i - 1].transactionDate)) != day;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (showHeader)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                          child: Text(Fmt.relativeDay(AppClock.toLocal(t.transactionDate), AppClock.now()),
                              style: context.text.labelLarge?.copyWith(color: context.secondaryText, fontWeight: FontWeight.w700)),
                        ),
                      TransactionTile(t, showDetails: true),
                    ]);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Selection {
  const _Selection({required this.title, required this.kindLabel, required this.color, required this.income, this.avatar, this.icon});
  final String title;
  final String kindLabel;
  final Color color;
  final bool income;
  final Widget? avatar;
  final IconData? icon;
}

/// "Food & Dining · November 2026 · 12 transactions · ₹4,320  ✕"
class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.selection,
    required this.period,
    required this.count,
    required this.hasMore,
    required this.loading,
    required this.total,
    required this.onClear,
  });
  final _Selection selection;
  final String period;
  final int count;
  final bool hasMore;
  final bool loading;
  final double total;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = selection.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: context.isDark ? 0.14 : 0.06), context.cardColor),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        selection.avatar ??
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(selection.icon, color: c, size: 22),
            ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selection.kindLabel.toUpperCase(),
                style: context.text.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            Text(selection.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              loading ? period : '$period • $count${hasMore ? '+' : ''} transaction${count == 1 && !hasMore ? '' : 's'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: context.secondaryText),
            ),
          ]),
        ),
        if (!loading)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(selection.income ? 'Received' : 'Spent', style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
            Text(Fmt.money(total), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        IconButton(
          tooltip: 'Clear filter',
          visualDensity: VisualDensity.compact,
          onPressed: onClear,
          icon: Icon(Icons.close_rounded, size: 18, color: context.secondaryText),
        ),
      ]),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarDelegate({required this.child});
  final Widget child;

  // 4 + 44 + 8 + 34 + 8 + 32 + 8
  static const _height = 138.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      FrostedBar(child: Material(type: MaterialType.transparency, child: child));

  @override
  bool shouldRebuild(covariant _FilterBarDelegate old) => true;
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: AppColors.blue,
        child: Material(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: const SizedBox(width: 44, height: 44, child: Icon(Icons.tune_rounded, color: Colors.white, size: 20)),
          ),
        ),
      );
}

class _Total extends StatelessWidget {
  const _Total({required this.icon, required this.color, required this.value});
  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 2),
        Text(value, style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}

class _ChipDivider extends StatelessWidget {
  const _ChipDivider();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 1,
          height: 18,
          margin: const EdgeInsets.only(right: 6),
          color: context.isDark ? Colors.white24 : AppColors.divider,
        ),
      );
}

class _QuickChip extends StatelessWidget {
  const _QuickChip(this.label, this.selected, this.onTap, {this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : (context.isDark ? Colors.white70 : AppColors.textPrimary);
    final bg = selected ? AppColors.navy : (context.isDark ? Colors.white10 : Colors.white);
    final border = selected ? AppColors.navy : (context.isDark ? Colors.white12 : AppColors.divider);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// An applied advanced filter; tap to remove it.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip(this.label, this.onRemove);
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: AppColors.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(left: 11, right: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.blue)),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.close_rounded, size: 14, color: AppColors.blue),
              ]),
            ),
          ),
        ),
      );
}
