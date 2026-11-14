import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, Color, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/notification_kind.dart';

/// FCM (server push: reminders, workspace activity, unusual spending) plus
/// local notifications (on-device events: new SMS transaction, sync status).
///
/// Notification-bar look: per-kind channel and accent colour, expandable text,
/// app logo as large icon, and a group summary once a kind has 2+ alerts.
/// Taps (local or push) are exposed on [taps] as in-app routes.
class NotificationService {
  NotificationService({FirebaseMessaging? messaging, FlutterLocalNotificationsPlugin? local})
      : _messaging = messaging,
        _local = local ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _local;
  bool _ready = false;
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<RemoteMessage>? _openSub;
  final _taps = StreamController<String>.broadcast();
  final _foreground = StreamController<InAppAlert>.broadcast();

  /// Alerts raised while the app is open, for the in-app banner.
  Stream<InAppAlert> get foregroundAlerts => _foreground.stream;
  String? _pendingRoute;

  static const _summaryBaseId = 900000;

  /// In-app routes from tapped notifications.
  Stream<String> get taps => _taps.stream;

  /// Route of the notification that launched the app (read once).
  String? takeLaunchRoute() {
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// [listenForPush] = false in the background-sync isolate, which only
  /// posts local notifications.
  Future<void> init({bool listenForPush = true}) async {
    if (_ready) return;
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) => _emit(r.payload),
      );
      await _createChannels();

      if (!listenForPush) {
        _ready = true;
        return;
      }
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) _pendingRoute = _clean(launch?.notificationResponse?.payload);

      // ---- Foreground (app open) ----
      // iOS shows the push itself (banner + ding) when asked to; Android never
      // displays FCM notifications for a foreground app, so we post it.
      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      await (_messaging ?? FirebaseMessaging.instance).setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      _fgSub = FirebaseMessaging.onMessage.listen((m) {
        if (kDebugMode) debugPrint('[push] foreground: ${m.notification?.title ?? m.data['title']} (${m.data['type']})');
        if (isIos && m.notification != null) {
          _emitForeground(m.notification!.title ?? '', m.notification!.body ?? '', NotificationKind.fromType(m.data['type'] as String?), m.data['route'] as String?);
          return; // the system banner is shown by iOS itself
        }
        showRemote(m);
      });
      // Push tapped from the notification bar (app in background / killed).
      _openSub = FirebaseMessaging.onMessageOpenedApp.listen((m) => _emit(m.data['route'] as String?));
      final initial = await (_messaging ?? FirebaseMessaging.instance).getInitialMessage();
      if (initial != null) _pendingRoute ??= _clean(initial.data['route'] as String?);
      _ready = true;
    } catch (e, s) {
      ErrorHandler.log(e, s, 'notifications.init');
    }
  }

  Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;
    for (final c in NotificationChannel.values) {
      await android.createNotificationChannel(AndroidNotificationChannel(
        c.id,
        c.label,
        description: c.description,
        importance: c.silent ? Importance.low : (c.high ? Importance.high : Importance.defaultImportance),
        playSound: !c.silent,
        sound: c.silent ? null : const RawResourceAndroidNotificationSound(NotificationChannel.sound),
        enableVibration: !c.silent,
        showBadge: !c.silent,
        ledColor: const Color(0xFF3478F6),
      ));
    }
    // Replaced by the channels above (older ids had the default sound).
    for (final id in NotificationChannel.legacyIds) {
      await android.deleteNotificationChannel(channelId: id);
    }
  }

  static String? _clean(String? route) => route == null || route.isEmpty ? null : route;

  void _emit(String? route) {
    final r = _clean(route);
    if (r != null) _taps.add(r);
  }

  Future<bool> requestPermission() async {
    try {
      final settings = await (_messaging ?? FirebaseMessaging.instance).requestPermission();
      await _android?.requestNotificationsPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Whether this phone currently allows Smart Spend notifications.
  Future<bool> areEnabled() async {
    try {
      final android = _android;
      if (android != null) return await android.areNotificationsEnabled() ?? true;
      final s = await (_messaging ?? FirebaseMessaging.instance).getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return true; // unknown: don't nag
    }
  }

  /// Makes sure this phone may show notifications. Android 13+ and iOS block
  /// them until the user allows it, and a phone that signs in to an existing
  /// account skips onboarding, so ask here (once the system lets us).
  Future<bool> ensurePermission() => _permissionRequest ??= _ensurePermission().whenComplete(() => _permissionRequest = null);

  /// In-flight request, shared so two callers never stack system dialogs.
  Future<bool>? _permissionRequest;

  Future<bool> _ensurePermission() async {
    try {
      final m = _messaging ?? FirebaseMessaging.instance;
      final current = await m.getNotificationSettings();
      var allowed = current.authorizationStatus == AuthorizationStatus.authorized ||
          current.authorizationStatus == AuthorizationStatus.provisional;
      if (current.authorizationStatus == AuthorizationStatus.notDetermined) {
        final asked = await m.requestPermission(alert: true, badge: true, sound: true);
        allowed = asked.authorizationStatus == AuthorizationStatus.authorized ||
            asked.authorizationStatus == AuthorizationStatus.provisional;
      }
      final android = _android;
      if (android != null && !(await android.areNotificationsEnabled() ?? true)) {
        allowed = await android.requestNotificationsPermission() ?? false;
      }
      return allowed;
    } catch (e, s) {
      ErrorHandler.log(e, s, 'notifications.permission');
      return false;
    }
  }

  /// Registers the device token so Cloud Functions can push reminders.
  Future<void> registerToken(Future<void> Function(String token) save) async {
    try {
      final m = _messaging ?? FirebaseMessaging.instance;
      final token = await m.getToken();
      if (token != null) await save(token);
      m.onTokenRefresh.listen(save);
    } catch (e, s) {
      ErrorHandler.log(e, s, 'notifications.token');
    }
  }

  /// Stops this install receiving pushes (sign-out) and clears its alerts.
  Future<void> unregister() async {
    try {
      await (_messaging ?? FirebaseMessaging.instance).deleteToken();
    } catch (e, s) {
      ErrorHandler.log(e, s, 'notifications.deleteToken');
    }
    try {
      await _local.cancelAll();
    } catch (_) {}
  }

  /// Shows a styled notification.
  Future<void> show({
    required String title,
    required String body,
    NotificationKind kind = NotificationKind.transaction,
    String? route,
    String? tag,
    List<String>? lines,
    String? summary,
    int? id,
  }) async {
    try {
      final channel = kind.channel;
      final android = AndroidNotificationDetails(
        channel.id,
        channel.label,
        channelDescription: channel.description,
        importance: channel.silent ? Importance.low : (channel.high ? Importance.high : Importance.defaultImportance),
        priority: channel.silent ? Priority.low : Priority.high,
        color: kind.color,
        largeIcon: const DrawableResourceAndroidBitmap('splash_logo'),
        subText: kind.label,
        ticker: title,
        tag: tag,
        groupKey: 'ss_group_${kind.type}',
        onlyAlertOnce: channel.silent,
        playSound: !channel.silent,
        // Used on Android 7 and older; 8+ takes the sound from the channel.
        sound: channel.silent ? null : const RawResourceAndroidNotificationSound(NotificationChannel.sound),
        category: switch (kind) {
          NotificationKind.upcoming || NotificationKind.overdue => AndroidNotificationCategory.reminder,
          NotificationKind.sync || NotificationKind.syncFailed => AndroidNotificationCategory.status,
          _ => AndroidNotificationCategory.message,
        },
        styleInformation: lines != null && lines.isNotEmpty
            ? InboxStyleInformation(lines, contentTitle: title, summaryText: summary)
            : BigTextStyleInformation(body, contentTitle: title, summaryText: summary),
      );
      await _local.show(
        id: id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: android,
          iOS: DarwinNotificationDetails(
            threadIdentifier: kind.type,
            subtitle: kind.label,
            presentSound: !channel.silent,
            // ios/Runner/notification_ding.caf (bundled resource).
            sound: channel.silent ? null : NotificationChannel.iosSound,
          ),
        ),
        payload: route,
      );
      await _updateGroupSummary(kind);
      _emitForeground(title, body, kind, route);
    } catch (e, s) {
      ErrorHandler.log(e, s, 'notifications.show');
    }
  }

  /// In-app banner only (no system notification), shown if the app is open.
  void toast({required String title, required String body, NotificationKind kind = NotificationKind.sync, String? route}) {
    if (title.isEmpty || _foreground.isClosed) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _foreground.add(InAppAlert(title: title, body: body, kind: kind, route: route));
  }

  /// Also show it inside the app when the app is open (system alerts are easy
  /// to miss while you're using the app).
  void _emitForeground(String title, String body, NotificationKind kind, String? route) {
    if (title.isEmpty || kind.channel.silent || _foreground.isClosed) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _foreground.add(InAppAlert(title: title, body: body, kind: kind, route: route));
  }

  /// Displays a push (foreground on Android, or a data-only push in the
  /// background) with the app's styling, sound and tap route.
  Future<void> showRemote(RemoteMessage m) {
    final title = m.notification?.title ?? m.data['title'] as String?;
    if (title == null || title.isEmpty) return Future.value();
    final tag = m.data['tag'] as String?;
    return show(
      title: title,
      body: m.notification?.body ?? m.data['body'] as String? ?? '',
      kind: NotificationKind.fromType(m.data['type'] as String?),
      route: m.data['route'] as String?,
      tag: tag == null || tag.isEmpty ? null : tag,
    );
  }

  /// "Spent ₹420 at Swiggy" for one; an inbox-style list for several.
  Future<void> showTransactions(List<FinancialTransaction> txs, {String? summary}) {
    if (txs.isEmpty) return Future.value();
    final t = TxSummary.of(txs);
    return show(
      kind: NotificationKind.transaction,
      title: t.title,
      body: t.body,
      lines: t.lines.length > 1 ? t.lines : null,
      summary: summary ?? (txs.length > 1 ? 'Tap to review' : null),
      route: t.route,
      tag: 'tx_summary',
      id: 1002,
    );
  }

  /// Bundles 2+ notifications of a kind under one expandable summary.
  Future<void> _updateGroupSummary(NotificationKind kind) async {
    final android = _android;
    if (android == null || defaultTargetPlatform != TargetPlatform.android) return;
    final group = 'ss_group_${kind.type}';
    final summaryId = _summaryBaseId + kind.index;
    final active = (await android.getActiveNotifications()).where((n) => n.groupKey == group && n.id != summaryId).toList();
    if (active.length < 2) return;
    await _local.show(
      id: summaryId,
      title: '${active.length} ${kind.label.toLowerCase()} updates',
      body: active.first.title ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kind.channel.id,
          kind.channel.label,
          channelDescription: kind.channel.description,
          color: kind.color,
          subText: kind.label,
          groupKey: group,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
          groupAlertBehavior: GroupAlertBehavior.children,
          styleInformation: InboxStyleInformation(
            [for (final n in active.take(6)) n.title ?? ''],
            contentTitle: '${active.length} ${kind.label.toLowerCase()} updates',
            summaryText: kind.label,
          ),
        ),
      ),
      payload: kind.filter == NotificationFilter.reminders ? Routes.upcoming : Routes.notifications,
    );
  }

  void dispose() {
    _fgSub?.cancel();
    _openSub?.cancel();
    _taps.close();
    _foreground.close();
  }
}

/// Text for a "new transactions" alert, shared by the local notification, the
/// in-app notification list and the push sent to the user's other phones.
class TxSummary {
  const TxSummary({required this.title, required this.body, required this.lines, required this.route});

  final String title;
  final String body;
  final List<String> lines;
  final String route;

  factory TxSummary.of(List<FinancialTransaction> txs) {
    final sorted = [...txs]..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    if (sorted.length == 1) {
      final t = sorted.first;
      final money = Fmt.money(t.amount, currency: t.currency);
      return TxSummary(
        title: t.isInflow ? 'Received $money from ${t.displayName}' : 'Spent $money at ${t.displayName}',
        body: [t.categoryName, t.paymentMode.label, ?t.bankName].join(' • '),
        lines: const [],
        route: Routes.transaction(t.transactionId),
      );
    }
    final currency = sorted.first.currency;
    final spent = sorted.where((t) => !t.isInflow).fold<double>(0, (s, t) => s + t.amount);
    final received = sorted.where((t) => t.isInflow).fold<double>(0, (s, t) => s + t.amount);
    return TxSummary(
      title: '${sorted.length} new transactions',
      body: [
        if (spent > 0) 'Spent ${Fmt.money(spent, currency: currency)}',
        if (received > 0) 'Received ${Fmt.money(received, currency: currency)}',
      ].join(' • '),
      lines: [
        for (final t in sorted.take(5)) '${t.isInflow ? '+' : '−'}${Fmt.money(t.amount, currency: t.currency)}  ${t.displayName}',
        if (sorted.length > 5) '+${sorted.length - 5} more',
      ],
      route: Routes.transactions,
    );
  }
}

/// A notification to show as an in-app banner while the app is open.
class InAppAlert {
  const InAppAlert({required this.title, required this.body, required this.kind, this.route});
  final String title;
  final String body;
  final NotificationKind kind;
  final String? route;
}
