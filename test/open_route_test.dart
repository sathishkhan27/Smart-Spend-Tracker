import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_spend_tracker/core/router/app_router.dart';

void main() {
  test('tab routes are recognised, including filtered Activity links', () {
    expect(isTabRoute(Routes.upcoming), isTrue);
    expect(isTabRoute('/transactions?category=food_dining&nav=1'), isTrue);
    expect(isTabRoute(Routes.transaction('abc')), isFalse);
    expect(isTabRoute(Routes.notifications), isFalse);
  });

  testWidgets('opening a tab from a notification twice does not duplicate page keys', (t) async {
    Widget page(String name) => Scaffold(body: Text(name));
    final router = GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(path: Routes.notifications, builder: (_, __) => page('notifications')),
        GoRoute(path: '/transactions/view/:id', builder: (_, s) => page('tx ${s.pathParameters['id']}')),
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, __) => page('home'))]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.transactions, builder: (_, __) => page('activity'))]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.upcoming, builder: (_, __) => page('upcoming'))]),
          ],
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));

    openAppRoute(router, Routes.notifications); // pushed on top
    await t.pumpAndSettle();
    openAppRoute(router, Routes.upcoming); // tab → switched to, not pushed
    await t.pumpAndSettle();
    openAppRoute(router, Routes.upcoming); // again (second reminder tapped)
    await t.pumpAndSettle();
    expect(find.text('upcoming'), findsOneWidget);

    openAppRoute(router, Routes.transaction('42'));
    await t.pumpAndSettle();
    expect(find.text('tx 42'), findsOneWidget);
    openAppRoute(router, '/transactions?category=food_dining');
    await t.pumpAndSettle();
    expect(find.text('activity'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
