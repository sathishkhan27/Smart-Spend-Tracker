import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/domain/period_aggregate.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/data/notification_service.dart';
import '../../notifications/domain/notification_kind.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../workspace/domain/workspace.dart';
import '../domain/budget.dart';

/// Checks this month's spending against the user's monthly budget after a
/// sync and alerts once at 80% and once when the budget is crossed. What was
/// already sent is kept on the user's profile (`budgetAlerts`: month → %), so
/// the user's other phones don't repeat it.
class BudgetAlerter {
  BudgetAlerter({required this.db, required this.transactions, required this.local, required this.inbox});

  final FirebaseFirestore db;
  final TransactionRepository transactions;
  final NotificationService local;
  final NotificationRepository inbox;

  Future<void> check({
    required String uid,
    required String workspaceId,
    required double? budget,
    required Map<String, int> alerted,
    required Map<String, bool> prefs,
    String currency = 'INR',
    DateTime? now,
  }) async {
    try {
      if (budget == null || budget <= 0) return;
      if (!(prefs[NotificationPrefKeys.budget] ?? true)) return;
      final n = now ?? AppClock.now();
      final start = DateTime(n.year, n.month), end = DateTime(n.year, n.month + 1);
      final month = Fmt.monthKey(start);
      final agg = FinancialCalculator.aggregate(await transactions.getRange(workspaceId, start, end), currency: currency);
      final status = BudgetStatus(budget: budget, spent: agg.outflow);
      final due = status.alertDue(alerted[month] ?? 0);
      if (due == null) return;
      // Record first so a sync running at the same time doesn't alert twice.
      await db.collection('users').doc(uid).set({
        'budgetAlerts': {month: due},
      }, SetOptions(merge: true));
      final msg = status.message(currency: currency, monthLabel: Fmt.month(start));
      await local.show(kind: NotificationKind.budget, title: msg.title, body: msg.body, route: Routes.budget, tag: 'budget', id: 1002);
      await inbox.add(uid, title: msg.title, body: msg.body, type: NotificationKind.budget.type, route: Routes.budget);
    } catch (e, s) {
      ErrorHandler.log(e, s, 'budget.check');
    }
  }
}
