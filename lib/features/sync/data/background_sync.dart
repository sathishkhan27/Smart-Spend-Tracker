import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/utils/app_clock.dart';
import '../../../firebase_options.dart';
import '../../budget/data/budget_alerter.dart';
import '../../cards/data/credit_card_repository.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/data/notification_service.dart';
import '../../notifications/data/sync_announcer.dart';
import '../../transactions/data/rules_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/engines/transaction_processor.dart';
import '../../upcoming/data/recurring_repository.dart';
import '../../workspace/domain/workspace.dart';
import 'connected_accounts_repository.dart';
import 'gmail_source.dart';
import 'local_store.dart';
import 'sms_source.dart';
import 'sync_service.dart';

/// Periodic background synchronization (Android WorkManager / iOS BGTask).
abstract final class BackgroundSync {
  static const periodicTask = 'smart_spend.periodic_sync';
  static const oneOffTask = 'smart_spend.one_off_sync';

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> schedule() => Workmanager().registerPeriodicTask(
        periodicTask,
        periodicTask,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  /// Continues an interrupted initial sync in the background.
  static Future<void> runSoon() => Workmanager().registerOneOffTask(
        oneOffTask,
        oneOffTask,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

  static Future<void> cancel() => Workmanager().cancelAll();
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final options = DefaultFirebaseOptions.currentPlatformOrNull;
      if (Firebase.apps.isEmpty) {
        options == null ? await Firebase.initializeApp() : await Firebase.initializeApp(options: options);
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;
      final db = FirebaseFirestore.instance;
      final profile = await db.collection('users').doc(user.uid).get();
      final data = profile.data();
      final wid = data?['activeWorkspaceId'] as String?;
      if (wid == null) return true;
      AppClock.init(data?['timezone'] as String? ?? AppClock.defaultTimezone);

      final notifications = NotificationService();
      await notifications.init(listenForPush: false);
      final prefs = Map<String, bool>.from((data?['notificationPrefs'] as Map?) ?? const {});

      final service = SyncService(
        transactions: TransactionRepository(db),
        rules: RulesRepository(db),
        recurring: RecurringRepository(db),
        accounts: ConnectedAccountsRepository(db),
        local: await LocalStore.open(),
        cards: CreditCardRepository(db),
        sms: SmsSource(),
        gmail: GmailSource(),
      );
      final result = await service.run(SyncRequest(
        ctx: ProcessingContext(workspaceId: wid, userId: user.uid, userName: data?['displayName'] as String?),
      ));
      // Failures are surfaced when the app is opened, not from background runs.
      await SyncAnnouncer(notifications, NotificationRepository(db)).announce(
        uid: user.uid,
        txs: result.newTransactions,
        prefs: prefs,
      );
      final workspace = (await db.collection('workspaces').doc(wid).get()).data();
      await BudgetAlerter(db: db, transactions: TransactionRepository(db), local: notifications, inbox: NotificationRepository(db)).check(
        uid: user.uid,
        workspaceId: wid,
        budget: (data?['monthlyBudget'] as num?)?.toDouble(),
        alerted: {
          for (final e in ((data?['budgetAlerts'] as Map?) ?? const {}).entries)
            if (e.value is num) e.key as String: (e.value as num).toInt(),
        },
        prefs: prefs,
        currency: workspace?['currency'] as String? ?? data?['currency'] as String? ?? 'INR',
      );
      return true;
    } catch (_) {
      return false; // WorkManager will retry with backoff
    }
  });
}
