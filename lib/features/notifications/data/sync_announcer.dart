import '../../../core/device/device_id.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../../workspace/domain/workspace.dart';
import '../domain/notification_kind.dart';
import 'notification_repository.dart';
import 'notification_service.dart';

/// Announces the result of every sync (foreground, background or a live SMS):
///
/// * recent transactions (dated within [recentWindow]) → one notification on
///   this phone listing them, an entry in the in-app Notifications list, and
///   a push to the user's other phones (server fan-out, skipping this one);
/// * older ones (first sync / backfill) → a quiet "import complete" summary,
///   never announced as new;
/// * failures → a "couldn't sync" alert.
///
/// Respects the user's notification preferences.
class SyncAnnouncer {
  SyncAnnouncer(this._local, this._repo);

  final NotificationService _local;
  final NotificationRepository _repo;

  static const recentWindow = Duration(days: 3);

  Future<void> announce({
    required String uid,
    required List<FinancialTransaction> txs,
    required Map<String, bool> prefs,
    bool initial = false,
    bool hasFailures = false,
    DateTime? now,
  }) async {
    try {
      bool pref(String k) => prefs[k] ?? true;
      final cutoff = (now ?? DateTime.now()).toUtc().subtract(recentWindow);
      final recent = txs.where((t) => t.transactionDate.isAfter(cutoff) && t.status != TxStatus.failed).toList();
      final older = txs.length - recent.length;

      var announced = false;
      if (recent.isNotEmpty && pref(NotificationPrefKeys.newTransaction)) {
        final s = TxSummary.of(recent);
        await _local.showTransactions(recent, summary: older > 0 ? '+$older earlier imported' : 'Sync complete');
        await _repo.add(
          uid,
          title: s.title,
          body: s.body,
          type: NotificationKind.transaction.type,
          route: s.route,
          lines: s.lines,
          fanout: true,
          originDevice: await DeviceId.get(),
        );
        announced = true; // the notification also raises the in-app banner
      } else if (older > 0 && pref(NotificationPrefKeys.syncCompleted)) {
        final title = initial ? 'Initial sync complete' : 'Sync complete';
        final body = '$older earlier transaction${older == 1 ? '' : 's'} imported to your history';
        await _local.show(kind: NotificationKind.sync, title: title, body: body, route: Routes.transactions, tag: 'sync_status', id: 1001);
        await _repo.add(uid, title: title, body: body, type: NotificationKind.sync.type, route: Routes.transactions);
      }

      // Every sync that found something tells you in the app (banner), even
      // when it was a quiet/silent notification or alerts are turned off.
      if (!announced && txs.isNotEmpty) {
        final s = TxSummary.of(txs);
        _local.toast(
          title: txs.length == 1 ? s.title : '${txs.length} new transactions added',
          body: txs.length == 1 ? s.body : s.body.isEmpty ? 'Tap to review' : s.body,
          kind: NotificationKind.transaction,
          route: s.route,
        );
      }

      if (hasFailures && pref(NotificationPrefKeys.syncFailed)) {
        const title = "Some sources couldn't sync";
        const body = 'Tap to review connected sources and retry.';
        await _local.show(kind: NotificationKind.syncFailed, title: title, body: body, route: Routes.sources, tag: 'sync_status', id: 1001);
        await _repo.add(uid, title: title, body: body, type: NotificationKind.syncFailed.type, route: Routes.sources);
      }
    } catch (e, s) {
      ErrorHandler.log(e, s, 'notifications.announce');
    }
  }
}
