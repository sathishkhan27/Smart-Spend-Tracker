import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:smart_spend_tracker/core/di/providers.dart';
import 'package:smart_spend_tracker/features/notifications/data/notification_service.dart';
import 'package:smart_spend_tracker/features/notifications/domain/notification_kind.dart';
import 'package:smart_spend_tracker/features/notifications/presentation/foreground_alert_host.dart';

class _Svc extends Mock implements NotificationService {}

void main() {
  testWidgets('in-app banner shows alerts one by one and auto-hides', (t) async {
    final ctrl = StreamController<InAppAlert>.broadcast();
    final svc = _Svc();
    when(() => svc.foregroundAlerts).thenAnswer((_) => ctrl.stream);
    await t.pumpWidget(ProviderScope(
      overrides: [notificationServiceProvider.overrideWithValue(svc)],
      // Mounted exactly like the app: in MaterialApp.builder, above the Navigator
      // (no Overlay there; regression for "No Overlay widget found").
      child: MaterialApp(
        builder: (context, child) => ForegroundAlertHost(child: child ?? const SizedBox()),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));

    ctrl
      ..add(const InAppAlert(title: 'Rent due tomorrow', body: '₹15,000', kind: NotificationKind.upcoming))
      ..add(const InAppAlert(title: 'Spent ₹420 at Swiggy', body: 'UPI', kind: NotificationKind.transaction));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Rent due tomorrow'), findsOneWidget);
    expect(find.text('Spent ₹420 at Swiggy'), findsNothing);

    await t.pump(const Duration(seconds: 4)); // first hides…
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400)); // …second slides in
    expect(find.text('Rent due tomorrow'), findsNothing);
    expect(find.text('Spent ₹420 at Swiggy'), findsOneWidget);

    await t.tap(find.bySemanticsLabel('Dismiss'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Spent ₹420 at Swiggy'), findsNothing);
    expect(t.takeException(), isNull);
    await ctrl.close();
  });
}
