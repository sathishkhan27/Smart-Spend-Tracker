import '../../transactions/domain/category.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../../../core/utils/app_clock.dart';
import 'recurring_expense.dart';

/// A recurring due settled by a transaction.
class DuePayment {
  const DuePayment(this.expense, this.dueDate, this.transaction);
  final RecurringExpense expense;
  final DateTime dueDate;
  final FinancialTransaction transaction;
}

/// Matches debits (EMI auto-debit, card bill payment, premium, bill) to the
/// Upcoming entries they settle, so paid dues stop showing as due/overdue.
class DuePaymentMatcher {
  const DuePaymentMatcher();

  /// Payment may land up to this many days before the due date…
  static const earlyDays = 12;

  /// …or this many days after it.
  static const lateDays = 7;

  List<DuePayment> match(List<RecurringExpense> dues, Iterable<FinancialTransaction> txs) {
    final out = <DuePayment>[];
    final used = <String>{};
    final active = dues.where((r) => r.status == RecurringStatus.active).toList();
    final sorted = txs.toList()..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));

    for (final t in sorted) {
      if (t.isInflow || t.status != TxStatus.success || t.isInternalTransfer) continue;
      if (used.contains(t.transactionId)) continue;
      final when = AppClock.toLocal(t.transactionDate);
      final day = DateTime(when.year, when.month, when.day);

      RecurringExpense? best;
      DateTime? bestDue;
      var bestScore = 0.0;
      for (final r in active) {
        if (out.any((p) => p.expense.id == r.id)) continue; // one payment per due per run
        final due = _dueFor(r, day);
        if (due == null) continue;
        final s = _score(r, t);
        if (s > bestScore) {
          bestScore = s;
          best = r;
          bestDue = due;
        }
      }
      if (best != null && bestScore >= 0.6) {
        out.add(DuePayment(best, bestDue!, t));
        used.add(t.transactionId);
      }
    }
    return out;
  }

  /// The unpaid due this payment date falls against, if any.
  DateTime? _dueFor(RecurringExpense r, DateTime payDay) {
    final lastPaid = r.lastPaidDate;
    // Candidate dues: the stored next due and the one after it.
    for (final due in [r.nextDueDate, r.frequency.advance(r.nextDueDate)]) {
      final d = DateTime(due.year, due.month, due.day);
      if (lastPaid != null && !d.isAfter(DateTime(lastPaid.year, lastPaid.month, lastPaid.day))) continue;
      final from = d.subtract(const Duration(days: earlyDays));
      final to = d.add(const Duration(days: lateDays));
      if (!payDay.isBefore(from) && !payDay.isAfter(to)) return due;
    }
    return null;
  }

  double _score(RecurringExpense r, FinancialTransaction t) {
    final cardBill = r.categoryId == Categories.creditCardPayment.id;
    final diff = (t.amount - r.expectedAmount).abs();
    final tolerance = (r.expectedAmount * 0.02).clamp(5, double.infinity);
    final amountOk = diff <= tolerance;
    // Card bills are often paid partly or in full above the "total due" snapshot.
    final cardAmountOk = cardBill && t.amount >= r.expectedAmount * 0.1;
    if (!amountOk && !cardAmountOk) return 0;

    var s = amountOk ? 0.45 : 0.25;
    if (t.categoryId == r.categoryId) s += 0.3;
    if (_emiLike(t) && r.categoryId == Categories.loanEmi.id) s += 0.15;
    if (_sameName(r.counterparty, t.counterparty ?? t.merchant ?? t.bankName)) s += 0.15;
    if (_sameName(r.name, t.bankName)) s += 0.1;
    return s.clamp(0, 1).toDouble();
  }

  static final _emiWords = RegExp(r'\b(emi|loan|nach|ecs|ach[\s\-]*d|instal?ment)\b', caseSensitive: false);
  bool _emiLike(FinancialTransaction t) => _emiWords.hasMatch([t.narration, t.counterparty, t.merchant].whereType<String>().join(' '));

  bool _sameName(String? a, String? b) {
    if (a == null || b == null) return false;
    Set<String> words(String s) => s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3 && w != 'bank' && w != 'emi').toSet();
    return words(a).intersection(words(b)).isNotEmpty;
  }
}
