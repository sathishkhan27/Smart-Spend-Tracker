import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/period_aggregate.dart';

/// Reads server-maintained aggregates (`workspaces/{id}/monthly_stats/{yyyy-MM}_{CUR}`)
/// written by the `onTransactionWrite` Cloud Function. Used for yearly views so
/// the client never has to download a full year of transactions.
class MonthlyStatsRepository {
  MonthlyStatsRepository(this._db);
  final FirebaseFirestore _db;

  Stream<PeriodAggregate?> watchMonths(String workspaceId, List<String> monthKeys, {String currency = 'INR'}) {
    final col = _db.collection('workspaces').doc(workspaceId).collection('monthly_stats');
    return col
        .where('currency', isEqualTo: currency)
        .where('monthKey', whereIn: monthKeys.take(30).toList())
        .snapshots()
        .map((q) {
      if (q.docs.isEmpty) return null;
      final agg = PeriodAggregate(currency: currency);
      for (final doc in q.docs) {
        _merge(agg, doc.data());
      }
      return agg;
    });
  }

  void _merge(PeriodAggregate agg, Map<String, dynamic> d) {
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    final month = d['monthKey'] as String;
    final inflow = n(d['inflow']), outflow = n(d['outflow']);
    final count = (d['count'] as num?)?.toInt() ?? 0;
    agg.inflow += inflow;
    agg.outflow += outflow;
    agg.count += count;
    agg.refunds += n(d['refunds']);
    agg.byMonth[month] = CashFlow(inflow, outflow, count);
    (d['categories'] as Map? ?? const {}).forEach((k, v) {
      final b = agg.byCategory.putIfAbsent(k as String, Bucket.new);
      b.amount += n((v as Map)['amount']);
      b.count += ((v['count'] as num?) ?? 0).toInt();
    });
    (d['paymentModes'] as Map? ?? const {}).forEach((k, v) => agg.byPaymentMode.update(k as String, (x) => x + n(v), ifAbsent: () => n(v)));
    (d['users'] as Map? ?? const {}).forEach((k, v) {
      final name = (v as Map)['name'] as String? ?? 'Member';
      agg.byUser.update(name, (x) => x + n(v['amount']), ifAbsent: () => n(v['amount']));
    });
    (d['banks'] as Map? ?? const {}).forEach((k, v) => agg.byBank.update(k as String, (x) => x + n(v), ifAbsent: () => n(v)));
    (d['counterparties'] as Map? ?? const {}).forEach((k, v) {
      final b = agg.byCounterparty.putIfAbsent((v as Map)['name'] as String? ?? k as String, Bucket.new);
      b.amount += n(v['amount']);
      b.count += ((v['count'] as num?) ?? 0).toInt();
    });
  }
}
