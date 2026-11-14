import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/config/app_config.dart';
import 'core/errors/failures.dart';
import 'core/utils/app_clock.dart';
import 'features/notifications/data/notification_service.dart';
import 'features/sync/data/background_sync.dart';
import 'features/sync/data/local_store.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ---- Background / terminated ----
  // Pushes with a notification payload are displayed by the OS (channel sound,
  // icon, tap → onMessageOpenedApp / getInitialMessage). Data-only pushes are
  // not, so display them here with the app's styling.
  if (message.notification != null) return;
  final local = NotificationService();
  await local.init(listenForPush: false);
  await local.showRemote(message);
}

class BootstrapResult {
  const BootstrapResult({required this.firebaseReady, required this.localStore, required this.notifications, this.error});
  final bool firebaseReady;
  final LocalStore localStore;
  final NotificationService notifications;
  final String? error;
}

abstract final class Bootstrap {
  static Future<BootstrapResult> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppClock.init();
    FlutterError.onError = (d) => ErrorHandler.log(d.exception, d.stack, 'flutter');
    PlatformDispatcher.instance.onError = (e, s) {
      ErrorHandler.log(e, s, 'platform');
      return true;
    };

    final notifications = NotificationService();

    // Local DB and Firebase start in parallel (independent; both are I/O).
    final storeFuture = LocalStore.open();
    Object? firebaseError;
    try {
      final options = DefaultFirebaseOptions.currentPlatformOrNull;
      if (Firebase.apps.isEmpty) {
        options == null ? await Firebase.initializeApp() : await Firebase.initializeApp(options: options);
      }
    } catch (e) {
      firebaseError = e;
    }
    final localStore = await storeFuture;
    if (firebaseError != null) {
      return BootstrapResult(firebaseReady: false, localStore: localStore, notifications: notifications, error: firebaseError.toString());
    }

    // App Check: Play Integrity / DeviceCheck in release, debug provider in dev.
    // Not awaited: token fetch must not delay the first frame.
    final debug = kDebugMode && AppConfig.appCheckDebug;
    unawaited(FirebaseAppCheck.instance
        .activate(
          providerAndroid: debug ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
          providerApple: debug ? const AppleDebugProvider() : const AppleDeviceCheckProvider(),
        )
        .catchError((Object e, StackTrace s) => ErrorHandler.log(e, s, 'appcheck')));

    // Offline-first: dashboard renders instantly from cache on launch.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 100 * 1024 * 1024);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    unawaited(FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode).catchError((_) {}));

    await Future.wait([
      notifications.init(),
      BackgroundSync.initialize().catchError((Object e, StackTrace s) => ErrorHandler.log(e, s, 'workmanager')),
    ]);
    return BootstrapResult(firebaseReady: true, localStore: localStore, notifications: notifications);
  }
}
