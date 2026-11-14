import 'dart:math' as math;

import '../../transactions/domain/engines/categorization_engine.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import 'recurring_expense.dart';

class RecurringSuggestion {
  const RecurringSuggestion({
    required this.merchantKey,
    required this.name,
    required this.frequency,
    required this.expectedAmount,
    required this.nextDueDate,
    required this.lastPaidDate,
    required this.categoryId,
    required this.confidence,
    required this.occurrences,
    this.currency = 'INR',
  });

  final String merchantKey;
  final String name;
  final RecurrenceFrequency frequency;
  final double expectedAmount;
  final DateTime nextDueDate;
  final DateTime lastPaidDate;
  final String categoryId;
  final double confidence;
  final int occurrences;
  final String currency;
}

/// Detects repeated outflows to the same counterparty with a regular cadence
/// and similar amounts. Results are *suggestions* — the user confirms them.
class RecurringDetector {
  const RecurringDetector({this.minOccurrences = 3, this.minConfidence = 0.55});

  final int minOccurrences;
  final double minConfidence;

  static const _tolerance = {
    RecurrenceFrequency.weekly: 2,
    RecurrenceFrequency.monthly: 5,
    RecurrenceFrequency.quarterly: 12,
    RecurrenceFrequency.halfYearly: 20,
    RecurrenceFrequency.yearly: 25,
  };

  /// Categories that are inherently recurring get a confidence boost.
  static const _recurringCategories = {
    'rent', 'loan_emi', 'credit_card_payment', 'electricity', 'mobile_recharge', 'insurance',
    'internet', 'subscription', 'water_bill',
  };

  List<RecurringSuggestion> detect(Iterable<FinancialTransaction> txs) {
    final groups = <String, List<FinancialTransaction>>{};
    for (final t in txs) {
      if (t.direction != TxDirection.outflow || !t.countsTowardTotals) continue;
      final key = CategorizationEngine.merchantKey(t.counterparty ?? t.merchant);
      if (key.length < 3) continue;
      groups.putIfAbsent('$key|${t.currency}', () => []).add(t);
    }

    final out = <RecurringSuggestion>[];
    for (final entry in groups.entries) {
      final list = entry.value..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
      // Collapse same-day duplicates.
      final dates = <DateTime>[];
      final amounts = <double>[];
      for (final t in list) {
        final d = DateTime(t.transactionDate.year, t.transactionDate.month, t.transactionDate.day);
        if (dates.isNotEmpty && dates.last == d) continue;
        dates.add(d);
        amounts.add(t.amount);
      }
      final isKnownRecurringCat = _recurringCategories.contains(list.last.categoryId);
      final required = isKnownRecurringCat ? 2 : minOccurrences;
      if (dates.length < required) continue;

      final intervals = [for (var i = 1; i < dates.length; i++) dates[i].difference(dates[i - 1]).inDays];
      final median = _median(intervals.map((e) => e.toDouble()).toList());
      final freq = _classify(median);
      if (freq == null) continue;

      final tol = _tolerance[freq]!;
      final regular = intervals.where((d) => (d - freq.approxDays).abs() <= tol).length / intervals.length;

      final meanAmt = amounts.reduce((a, b) => a + b) / amounts.length;
      final variance = amounts.map((a) => math.pow(a - meanAmt, 2)).reduce((a, b) => a + b) / amounts.length;
      final cv = meanAmt == 0 ? 1.0 : math.sqrt(variance) / meanAmt;
      final amountScore = cv <= 0.05 ? 1.0 : (cv <= 0.2 ? 0.75 : (cv <= 0.4 ? 0.4 : 0.1));

      final countScore = math.min(1.0, dates.length / 6);
      var confidence = regular * 0.45 + amountScore * 0.3 + countScore * 0.15 + (isKnownRecurringCat ? 0.1 : 0);
      confidence = confidence.clamp(0, 1).toDouble();
      if (confidence < minConfidence) continue;

      final last = list.last;
      out.add(RecurringSuggestion(
        merchantKey: entry.key.split('|').first,
        name: last.counterparty ?? last.merchant ?? last.categoryName,
        frequency: freq,
        expectedAmount: double.parse(_median(amounts.sublist(math.max(0, amounts.length - 3))).toStringAsFixed(2)),
        lastPaidDate: dates.last,
        nextDueDate: freq.advance(dates.last),
        categoryId: last.categoryId,
        confidence: confidence,
        occurrences: dates.length,
        currency: last.currency,
      ));
    }
    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out;
  }

  RecurrenceFrequency? _classify(double medianDays) {
    for (final f in RecurrenceFrequency.values) {
      if ((medianDays - f.approxDays).abs() <= _tolerance[f]!) return f;
    }
    return null;
  }

  double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }
}
