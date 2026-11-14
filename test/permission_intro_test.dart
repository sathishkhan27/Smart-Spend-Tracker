import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/features/onboarding/presentation/permission_intro.dart';

void main() {
  Future<bool?> open(WidgetTester t, {required bool sms, required bool notifications, required String tap}) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showPermissionIntro(ctx, sms: sms, notifications: notifications),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    if (tap == 'check') return null;
    await t.ensureVisible(find.text(tap)); // the sheet scrolls on small screens
    await t.pump();
    await t.tap(find.text(tap));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    return result;
  }

  testWidgets('explains both permissions and returns true on Allow', (t) async {
    expect(await open(t, sms: true, notifications: true, tap: 'Allow access'), isTrue);
  });

  testWidgets('returns false on Not now', (t) async {
    expect(await open(t, sms: true, notifications: true, tap: 'Not now'), isFalse);
  });

  testWidgets('lists only what is still needed', (t) async {
    await open(t, sms: false, notifications: true, tap: 'check');
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('SMS'), findsNothing);
  });
}
