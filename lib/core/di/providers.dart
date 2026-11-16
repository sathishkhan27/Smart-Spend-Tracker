import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/budget/data/budget_alerter.dart';
import '../../features/cards/data/credit_card_repository.dart';
import '../../features/cards/domain/credit_card.dart';
import '../../features/dashboard/data/monthly_stats_repository.dart';
import '../../features/insights/data/export_service.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/notifications/data/notification_service.dart';
import '../../features/notifications/data/sync_announcer.dart';
import '../../features/notifications/domain/notification_kind.dart';
import '../../features/sync/data/connected_accounts_repository.dart';
import '../../features/sync/data/gmail_source.dart';
import '../../features/sync/data/local_store.dart';
import '../../features/sync/data/sms_source.dart';
import '../../features/sync/data/sync_service.dart';
import '../../features/sync/domain/sync_progress.dart';
import '../../features/transactions/data/rules_repository.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../../features/transactions/domain/engines/transaction_processor.dart';
import '../../features/upcoming/data/recurring_repository.dart';
import '../../features/workspace/data/workspace_repository.dart';
import '../../features/workspace/domain/workspace.dart';
import '../config/app_config.dart';
import '../device/device_id.dart';
import '../router/app_router.dart';
import '../network/connectivity_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure (overridden in bootstrap / tests)
// ---------------------------------------------------------------------------

final connectivityServiceProvider = Provider((_) => ConnectivityService());

/// true = internet reachable. Starts optimistic so cached screens don't flash "offline".
final onlineProvider = StreamProvider<bool>((ref) => ref.watch(connectivityServiceProvider).watch());

final firestoreProvider = Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);
final firebaseAuthProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final functionsProvider = Provider<FirebaseFunctions>((_) => FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion));
final localStoreProvider = Provider<LocalStore>((_) => throw UnimplementedError('LocalStore is opened in bootstrap'));

// ---------------------------------------------------------------------------
// Repositories & services
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(firebaseAuthProvider)));
final workspaceRepositoryProvider = Provider((ref) => WorkspaceRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider)));
final transactionRepositoryProvider = Provider((ref) => TransactionRepository(ref.watch(firestoreProvider)));
final rulesRepositoryProvider = Provider((ref) => RulesRepository(ref.watch(firestoreProvider)));
final recurringRepositoryProvider = Provider((ref) => RecurringRepository(ref.watch(firestoreProvider)));
final monthlyStatsRepositoryProvider = Provider((ref) => MonthlyStatsRepository(ref.watch(firestoreProvider)));
final notificationRepositoryProvider = Provider((ref) => NotificationRepository(ref.watch(firestoreProvider)));
final connectedAccountsRepositoryProvider = Provider((ref) => ConnectedAccountsRepository(ref.watch(firestoreProvider)));
final smsSourceProvider = Provider((_) => SmsSource());
final gmailSourceProvider = Provider((_) => GmailSource());
final notificationServiceProvider = Provider((_) => NotificationService());
final exportServiceProvider = Provider((_) => ExportService());

final syncServiceProvider = Provider<SyncService>((ref) {
  final notifications = ref.watch(notificationServiceProvider);
  return SyncService(
    transactions: ref.watch(transactionRepositoryProvider),
    rules: ref.watch(rulesRepositoryProvider),
    recurring: ref.watch(recurringRepositoryProvider),
    accounts: ref.watch(connectedAccountsRepositoryProvider),
    local: ref.watch(localStoreProvider),
    cards: ref.watch(creditCardRepositoryProvider),
    sms: ref.watch(smsSourceProvider),
    gmail: ref.watch(gmailSourceProvider),
    // Every completed sync: recent transactions → this phone, the in-app list
    // and the user's other phones; older imports → a quiet summary.
    onNewTransactions: (txs, p, initial) {
      final profile = ref.read(profileProvider).value;
      if (profile == null) return;
      SyncAnnouncer(notifications, ref.read(notificationRepositoryProvider)).announce(
        uid: profile.uid,
        txs: txs,
        prefs: profile.notificationPrefs,
        initial: initial,
        hasFailures: p.hasFailures,
      );
      ref.read(budgetCheckProvider)();
    },
  );
});

final budgetAlerterProvider = Provider((ref) => BudgetAlerter(
      db: ref.watch(firestoreProvider),
      transactions: ref.watch(transactionRepositoryProvider),
      local: ref.watch(notificationServiceProvider),
      inbox: ref.watch(notificationRepositoryProvider),
    ));

/// Compares this month's spending with the user's monthly budget and alerts
/// at 80% / when crossed (once each per month). Called after every sync and
/// when the budget is changed.
final budgetCheckProvider = Provider<Future<void> Function()>((ref) => () async {
      final profile = ref.read(profileProvider).value;
      final wid = ref.read(activeWorkspaceIdProvider);
      if (profile == null || wid == null || profile.monthlyBudget == null) return;
      await ref.read(budgetAlerterProvider).check(
            uid: profile.uid,
            workspaceId: wid,
            budget: profile.monthlyBudget,
            alerted: profile.budgetAlerts,
            prefs: profile.notificationPrefs,
            currency: ref.read(activeWorkspaceProvider).value?.currency ?? profile.currency,
          );
    });

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<User?>((ref) => ref.watch(authRepositoryProvider).authStateChanges());

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(workspaceRepositoryProvider).watchProfile(uid);
});

final membershipsProvider = StreamProvider<List<WorkspaceMember>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(workspaceRepositoryProvider).watchMemberships(uid);
});

/// The workspace the user is currently viewing; must be one they belong to.
final activeWorkspaceIdProvider = Provider<String?>((ref) {
  final profile = ref.watch(profileProvider).value;
  final memberships = ref.watch(membershipsProvider).value ?? const [];
  final wanted = profile?.activeWorkspaceId;
  if (wanted != null && memberships.any((m) => m.workspaceId == wanted)) return wanted;
  return memberships.isEmpty ? null : memberships.first.workspaceId;
});

final activeWorkspaceProvider = StreamProvider<Workspace?>((ref) {
  final id = ref.watch(activeWorkspaceIdProvider);
  if (id == null) return Stream.value(null);
  return ref.watch(workspaceRepositoryProvider).watchWorkspace(id);
});

final myWorkspacesProvider = FutureProvider<List<Workspace>>((ref) async {
  final memberships = ref.watch(membershipsProvider).value ?? const [];
  return ref.watch(workspaceRepositoryProvider).getWorkspaces(memberships.map((m) => m.workspaceId).toList());
});

final myMembershipProvider = Provider<WorkspaceMember?>((ref) {
  final id = ref.watch(activeWorkspaceIdProvider);
  final memberships = ref.watch(membershipsProvider).value ?? const [];
  for (final m in memberships) {
    if (m.workspaceId == id) return m;
  }
  return null;
});

final workspaceMembersProvider = StreamProvider<List<WorkspaceMember>>((ref) {
  final id = ref.watch(activeWorkspaceIdProvider);
  if (id == null) return Stream.value(const []);
  return ref.watch(workspaceRepositoryProvider).watchMembers(id);
});

final processingContextProvider = Provider<ProcessingContext?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final wid = ref.watch(activeWorkspaceIdProvider);
  if (user == null || wid == null) return null;
  final profile = ref.watch(profileProvider).value;
  return ProcessingContext(workspaceId: wid, userId: user.uid, userName: profile?.displayName ?? user.displayName);
});

final syncProgressProvider = StreamProvider<SyncProgress>((ref) => ref.watch(syncServiceProvider).progress);

final connectedAccountsProvider = StreamProvider<List<ConnectedAccount>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(connectedAccountsRepositoryProvider).watch(uid);
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(profileProvider).value?.themeMode) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
});

/// Whether notifications are allowed on this phone. Re-checked when the app
/// returns to the foreground (the user may have changed it in Settings).
final notificationsEnabledProvider = FutureProvider<bool>((ref) => ref.watch(notificationServiceProvider).areEnabled());

/// Whether SMS access is granted (Android). Re-checked on app resume.
final smsPermissionProvider = FutureProvider<bool>((ref) async {
  final sms = ref.watch(smsSourceProvider);
  return !sms.isSupported || await sms.hasPermission();
});

final creditCardRepositoryProvider = Provider((ref) => CreditCardRepository(ref.watch(firestoreProvider)));

/// Credit cards detected for the active workspace (largest pending due first).
final creditCardsProvider = StreamProvider<List<CreditCard>>((ref) {
  final wid = ref.watch(activeWorkspaceIdProvider);
  if (wid == null) return Stream.value(const []);
  return ref.watch(creditCardRepositoryProvider).watch(wid);
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(uid);
});

final unreadNotificationsProvider = Provider<int>((ref) => (ref.watch(notificationsProvider).value ?? const []).where((n) => !n.read).length);

/// Signs out after detaching this phone from the account's push targets, so
/// the next person to sign in here never receives this user's notifications.
Future<void> signOutAndUnregister(WidgetRef ref) async {
  final uid = ref.read(authStateProvider).value?.uid;
  if (uid != null) {
    try {
      await ref.read(workspaceRepositoryProvider).unregisterDevice(uid, await DeviceId.get()).timeout(const Duration(seconds: 6));
    } catch (_) {} // offline: the server drops the token once it stops working
  }
  await ref.read(notificationServiceProvider).unregister();
  await ref.read(authRepositoryProvider).signOut();
}
