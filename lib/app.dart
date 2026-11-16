import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/device/device_id.dart';
import 'core/di/providers.dart';
import 'core/errors/failures.dart';
import 'core/network/connectivity_banner.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_clock.dart';
import 'core/widgets/common.dart';
import 'features/notifications/data/sync_announcer.dart';
import 'features/onboarding/presentation/permission_intro.dart';
import 'features/notifications/presentation/foreground_alert_host.dart';
import 'features/sync/data/background_sync.dart';
import 'features/sync/data/connected_accounts_repository.dart';
import 'features/sync/data/sync_service.dart';
import 'features/transactions/domain/engines/raw_message.dart';
import 'features/workspace/domain/workspace.dart';

class SmartSpendApp extends ConsumerWidget {
  const SmartSpendApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Smart Spend Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      // Respect accessibility font sizes, but cap them so layouts stay intact.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.1)),
          child: ConnectivityBanner(child: ForegroundAlertHost(child: SessionEffects(child: child ?? const SizedBox()))),
        );
      },
    );
  }
}

/// Session-level side effects: profile bootstrap, FCM token, live SMS
/// listener, background sync scheduling and a refresh sync on launch.
class SessionEffects extends ConsumerStatefulWidget {
  const SessionEffects({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SessionEffects> createState() => _SessionEffectsState();
}

class _SessionEffectsState extends ConsumerState<SessionEffects> with WidgetsBindingObserver {
  String? _bootstrappedUid;
  String? _syncedFor;
  StreamSubscription<RawMessage>? _smsSub;
  StreamSubscription<String>? _tapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Notification taps open the related screen (transaction, Upcoming…).
    final notifications = ref.read(notificationServiceProvider);
    _tapSub = notifications.taps.listen(_openRoute);
    final router = ref.read(routerProvider);
    router.routerDelegate
      ..addListener(_drainPendingRoute)
      ..addListener(_maybeAskPermissions);
    _router = router;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // First launch after install: ask to allow notifications right away
      // (Android 13+ / iOS show the system prompt once; older Android allows
      // them by default). Short delay so the prompt appears over the first
      // screen, not a blank window.
      Future<void>.delayed(const Duration(milliseconds: 900), _maybeAskPermissions);
      final launch = notifications.takeLaunchRoute();
      if (launch != null) _openRoute(launch);
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid != null) _onUser(uid);
      final p = ref.read(profileProvider).value;
      if (p != null && p.onboardingComplete && ref.read(processingContextProvider) != null) _onReady(p);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _smsSub?.cancel();
    _tapSub?.cancel();
    _router?.routerDelegate
      ?..removeListener(_drainPendingRoute)
      ..removeListener(_maybeAskPermissions);
    super.dispose();
  }

  DateTime? _lastRefresh;

  /// Re-scan on resume only if the last refresh is stale; the live SMS
  /// listener already captures new messages while the app is open.
  static const _resumeRefreshGap = Duration(minutes: 15);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(notificationsEnabledProvider); // may have been changed in Settings
    ref.invalidate(smsPermissionProvider);
    _startSmsIfGranted();
    final last = _lastRefresh;
    if (last == null || DateTime.now().difference(last) > _resumeRefreshGap) _refreshSync();
  }

  /// Page requested by a tapped notification, held until the app can show it.
  String? _pendingRoute;
  GoRouter? _router;

  /// Opens [route] now, or as soon as the user is signed in, set up and past
  /// the splash screen (a tap can arrive before any of that on a cold start).
  void _openRoute(String route) {
    _pendingRoute = route;
    _drainPendingRoute();
  }

  // ---- Permissions (every new install) ----
  static const _introKey = 'permission_intro_shown_v1';
  bool _introRunning = false;

  /// First launch after install: explain, then ask for SMS + notifications.
  /// Later launches only re-check notifications (no repeated SMS prompts).
  Future<void> _maybeAskPermissions() async {
    if (!mounted || _introRunning) return;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (prefs.getBool(_introKey) ?? false) {
      unawaited(ref.read(notificationServiceProvider).ensurePermission());
      return;
    }
    // Wait until the splash is gone: a sheet over the splash would be closed
    // by the startup redirect. Retried from the router listener.
    final here = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || here.isEmpty || here == Routes.splash) return;

    _introRunning = true;
    try {
      final sms = ref.read(smsSourceProvider);
      final notifications = ref.read(notificationServiceProvider);
      final needSms = sms.isSupported && !await sms.hasPermission();
      final needNotif = !await notifications.areEnabled();
      if (needSms || needNotif) {
        if (!ctx.mounted) return;
        final allow = await showPermissionIntro(ctx, sms: needSms, notifications: needNotif);
        if (allow) {
          if (needSms && (await sms.requestPermission()).isGranted) await _onSmsGranted();
          if (needNotif) await notifications.ensurePermission();
        }
      }
      await prefs.setBool(_introKey, true);
      ref
        ..invalidate(smsPermissionProvider)
        ..invalidate(notificationsEnabledProvider);
    } finally {
      _introRunning = false;
    }
  }

  /// SMS access just granted: record consent and start reading right away.
  Future<void> _onSmsGranted() async {
    final uid = ref.read(authStateProvider).value?.uid;
    final wid = ref.read(activeWorkspaceIdProvider);
    if (uid != null) {
      unawaited(ref.read(workspaceRepositoryProvider).recordConsent(uid, source: 'sms', granted: true, scope: 'READ_SMS,RECEIVE_SMS').catchError((Object _) {}));
      if (wid != null) {
        unawaited(ref
            .read(connectedAccountsRepositoryProvider)
            .upsert(uid, wid, SourceProvider.sms, ConnectionStatus.connected, identifier: 'Device SMS')
            .catchError((Object _) {}));
      }
    }
    _startSmsIfGranted(forceSync: true);
  }

  /// Starts the live SMS listener (and a sync) once access exists.
  void _startSmsIfGranted({bool forceSync = false}) {
    final p = ref.read(profileProvider).value;
    if (p == null || !p.onboardingComplete || ref.read(processingContextProvider) == null) return;
    final hadListener = _smsSub != null;
    _listenSms();
    if (forceSync || !hadListener) {
      _lastRefresh = null;
      _refreshSync();
    }
  }

  void _drainPendingRoute() {
    final route = _pendingRoute;
    if (route == null || !mounted) return;
    final user = ref.read(authStateProvider).value;
    final profile = ref.read(profileProvider).value;
    if (user == null || !user.emailVerified || profile == null || !profile.onboardingComplete) return;
    final router = ref.read(routerProvider);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    const notReady = {Routes.splash, Routes.welcome, Routes.login, Routes.register, Routes.verifyEmail};
    if (here.isEmpty || notReady.contains(here) || here.startsWith('/setup')) return; // the redirect will move on; retry then
    _pendingRoute = null;
    if (here == Uri.tryParse(route)?.path) return; // already showing it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openAppRoute(router, route);
    });
  }

  Future<void> _onUser(String uid) async {
    if (_bootstrappedUid == uid) return;
    _bootstrappedUid = uid;
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    try {
      await ref.read(workspaceRepositoryProvider).ensureProfile(user);
    } catch (e, s) {
      ErrorHandler.log(e, s, 'session.ensureProfile');
    }
  }

  Future<void> _onReady(UserProfile profile) async {
    AppClock.setTimezone(profile.timezone);
    if (_syncedFor == profile.uid) return;
    _syncedFor = profile.uid;
    final notifications = ref.read(notificationServiceProvider);
    // Every phone on the account registers for pushes; permissions are asked by
    // the first-launch flow (explanation first, then the system prompts).
    unawaited(notifications.registerToken((t) async => ref
        .read(workspaceRepositoryProvider)
        .registerDevice(profile.uid, deviceId: await DeviceId.get(), token: t, platform: DeviceId.platform)));
    unawaited(_maybeAskPermissions());
    unawaited(BackgroundSync.schedule().catchError((Object e) => ErrorHandler.log(e, null, 'schedule')));
    _listenSms();
    _refreshSync();
  }

  void _listenSms() {
    final sms = ref.read(smsSourceProvider);
    if (!sms.isSupported || _smsSub != null) return;
    sms.hasPermission().then((granted) {
      if (!granted || !mounted) return;
      _smsSub = sms.incoming().listen((m) async {
        final ctx = ref.read(processingContextProvider);
        if (ctx == null) return;
        final fresh = await ref.read(syncServiceProvider).ingestLive(m, ctx);
        final profile = ref.read(profileProvider).value;
        if (fresh.isNotEmpty && profile != null) {
          await SyncAnnouncer(ref.read(notificationServiceProvider), ref.read(notificationRepositoryProvider))
              .announce(uid: profile.uid, txs: fresh, prefs: profile.notificationPrefs);
          await ref.read(budgetCheckProvider)();
        }
      }, onError: (Object e) => ErrorHandler.log(e, null, 'sms.live'));
    });
  }

  /// Existing Firebase data renders immediately; this refresh runs behind it.
  void _refreshSync() {
    final profile = ref.read(profileProvider).value;
    final ctx = ref.read(processingContextProvider);
    if (profile == null || ctx == null || !profile.onboardingComplete) return;
    final service = ref.read(syncServiceProvider);
    if (service.current.isRunning) return;
    // Offline: on-device parsing still works, but uploads would only queue; wait for reconnect.
    if (ref.read(onlineProvider).value == false) return;
    _lastRefresh = DateTime.now();
    unawaited(service.run(SyncRequest(ctx: ctx, initial: !profile.initialSyncComplete)).then((r) {
      if (!profile.initialSyncComplete && r.progress.isComplete) {
        ref.read(workspaceRepositoryProvider).updateProfile(profile.uid, {'initialSyncComplete': true});
      }
    }).catchError((Object e) {
      ErrorHandler.log(e, null, 'sync.refresh');
    }));
  }

  @override
  Widget build(BuildContext context) {
    // Reconnected: upload anything queued offline and fetch new messages.
    ref.listen<AsyncValue<bool>>(onlineProvider, (prev, next) {
      if (prev?.value == false && next.value == true) _refreshSync();
    });
    ref.listen(authStateProvider, (_, next) {
      final uid = next.value?.uid;
      if (uid != null) {
        _onUser(uid);
      } else {
        _bootstrappedUid = null;
        _syncedFor = null;
        _smsSub?.cancel();
        _smsSub = null;
      }
    });
    ref.listen(profileProvider, (_, next) {
      _drainPendingRoute();
      final p = next.value;
      if (p != null && p.onboardingComplete && ref.read(processingContextProvider) != null) _onReady(p);
    });
    ref.listen(processingContextProvider, (_, ctx) {
      final p = ref.read(profileProvider).value;
      if (ctx != null && p != null && p.onboardingComplete) _onReady(p);
    });
    return widget.child;
  }
}

/// Shown when Firebase has not been configured for this build.
class FirebaseSetupRequiredApp extends StatelessWidget {
  const FirebaseSetupRequiredApp({super.key, this.error});
  final String? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                const Center(child: AppLogo(size: 72)),
                const SizedBox(height: 24),
                Text('Connect Firebase to continue',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text(
                  'Smart Spend Tracker stores all transactions in your Firebase project. '
                  'This build has no Firebase configuration yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                const AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. Create a Firebase project and enable Auth (Email/Password), Firestore, Functions and Messaging.'),
                      SizedBox(height: 8),
                      Text('2. Run `flutterfire configure` in the project folder.'),
                      SizedBox(height: 8),
                      Text('3. Deploy rules & functions: `firebase deploy`.'),
                      SizedBox(height: 8),
                      Text('4. Rebuild the app. See docs/SETUP.md for details.'),
                    ],
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      );
}
