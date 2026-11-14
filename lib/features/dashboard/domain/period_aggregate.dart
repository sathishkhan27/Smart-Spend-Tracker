import '../../transactions/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';

class CashFlow {
  CashFlow([this.inflow = 0, this.outflow = 0, this.count = 0]);
  double inflow;
  double outflow;
  int count;
  double get net => inflow - outflow;
}

class Bucket {
  Bucket([this.amount = 0, this.count = 0]);
  double amount;
  int count;
}

class CategorySpend {
  const CategorySpend(this.category, this.amount, this.count, this.percent);
  final CategoryDef category;
  final double amount;
  final int count;
  final double percent;
}

/// Aggregated figures for a period. Built either client-side from date-scoped
/// transactions ([FinancialCalculator.aggregate]) or from server-maintained
/// monthly stats documents (see `MonthlyStatsRepository`).
class PeriodAggregate {
  PeriodAggregate({this.currency = 'INR'});

  final String currency;
  double inflow = 0;
  double outflow = 0;
  int count = 0;
  double refunds = 0;
  int pending = 0;
  int failed = 0;
  int needsReview = 0;
  int internalTransfers = 0;

  /// categoryId → amount/count (both income and expense).
  final Map<String, Bucket> byCategory = {};
  final Map<String, double> byPaymentMode = {};
  final Map<String, double> byUser = {};
  final Map<String, double> byBank = {};
  final Map<String, Bucket> byCounterparty = {};

  /// yyyy-MM → flows
  final Map<String, CashFlow> byMonth = {};

  /// yyyy-MM-dd → flows
  final Map<String, CashFlow> byDay = {};

  /// Totals in currencies other than [currency]; never summed with the primary.
  final Map<String, CashFlow> otherCurrencies = {};

  double get net => inflow - outflow;
  bool get isEmpty => count == 0;

  List<CategorySpend> get expenseCategories => _categories(false, outflow);
  List<CategorySpend> get incomeCategories => _categories(true, inflow);

  List<CategorySpend> _categories(bool income, double total) {
    final list = <CategorySpend>[];
    byCategory.forEach((id, b) {
      final c = Categories.byId(id);
      if (c.isIncome != income || b.amount <= 0) return;
      list.add(CategorySpend(c, b.amount, b.count, total == 0 ? 0 : b.amount / total * 100));
    });
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  /// Dashboard roll-ups ("Bills", "Food", ...).
  Map<String, double> groupTotals({required bool income}) {
    final groups = {for (final g in income ? Categories.incomeGroups : Categories.expenseGroups) g: 0.0};
    byCategory.forEach((id, b) {
      final c = Categories.byId(id);
      if (c.isIncome != income) return;
      final g = c.group ?? (income ? 'Other Credits' : 'Other Expenses');
      groups[g] = (groups[g] ?? 0) + b.amount;
    });
    return groups;
  }

  List<MapEntry<String, Bucket>> topCounterparties([int n = 8]) {
    final l = byCounterparty.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    return l.take(n).toList();
  }

  MapEntry<String, CashFlow>? get highestSpendingMonth {
    final l = byMonth.entries.where((e) => e.value.outflow > 0).toList()..sort((a, b) => b.value.outflow.compareTo(a.value.outflow));
    return l.isEmpty ? null : l.first;
  }

  MapEntry<String, CashFlow>? get lowestSpendingMonth {
    final l = byMonth.entries.where((e) => e.value.outflow > 0).toList()..sort((a, b) => a.value.outflow.compareTo(b.value.outflow));
    return l.isEmpty ? null : l.first;
  }
}

/// Implements the financial calculation rules:
/// * only `success` transactions count; failed & pending are excluded
/// * identified internal transfers are excluded from income and expense
/// * refunds are tracked separately (and also count as inflow)
/// * amounts in different currencies are never added together
abstract final class FinancialCalculator {
  static PeriodAggregate aggregate(Iterable<FinancialTransaction> txs, {String currency = 'INR'}) {
    final agg = PeriodAggregate(currency: currency);
    final seen = <String>{};
    for (final t in txs) {
      if (!seen.add(t.transactionId)) continue; // never double count
      switch (t.status) {
        case TxStatus.pending || TxStatus.processing:
          agg.pending++;
          continue;
        case TxStatus.failed:
          agg.failed++;
          continue;
        case TxStatus.needsReview:
          agg.needsReview++;
          continue;
        case TxStatus.duplicate || TxStatus.ignored:
          continue;
        case TxStatus.success:
          break;
      }
      if (t.isInternalTransfer) {
        agg.internalTransfers++;
        continue;
      }
      if (t.currency != currency) {
        final f = agg.otherCurrencies.putIfAbsent(t.currency, CashFlow.new);
        t.isInflow ? f.inflow += t.amount : f.outflow += t.amount;
        f.count++;
        continue;
      }

      final local = AppClock.toLocal(t.transactionDate);
      final month = agg.byMonth.putIfAbsent(Fmt.monthKey(local), CashFlow.new);
      final day = agg.byDay.putIfAbsent(Fmt.dayKey(local), CashFlow.new);
      agg.count++;
      month.count++;
      day.count++;
      final cat = agg.byCategory.putIfAbsent(t.categoryId, Bucket.new);
      cat.amount += t.amount;
      cat.count++;

      if (t.isInflow) {
        agg.inflow += t.amount;
        month.inflow += t.amount;
        day.inflow += t.amount;
        if (t.categoryId == Categories.refund.id) agg.refunds += t.amount;
      } else {
        agg.outflow += t.amount;
        month.outflow += t.amount;
        day.outflow += t.amount;
        agg.byPaymentMode.update(t.paymentMode.label, (v) => v + t.amount, ifAbsent: () => t.amount);
        agg.byUser.update(t.ownerName ?? 'Member', (v) => v + t.amount, ifAbsent: () => t.amount);
        agg.byBank.update(t.bankName ?? 'Unknown', (v) => v + t.amount, ifAbsent: () => t.amount);
        final cp = agg.byCounterparty.putIfAbsent(t.displayName, Bucket.new);
        cp.amount += t.amount;
        cp.count++;
      }
    }
    return agg;
  }
}
