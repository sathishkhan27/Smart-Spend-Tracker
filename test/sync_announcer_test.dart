import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_spend_tracker/core/device/device_id.dart';
import 'package:smart_spend_tracker/features/notifications/data/notification_repository.dart';
import 'package:smart_spend_tracker/features/notifications/data/notification_service.dart';
import 'package:smart_spend_tracker/features/notifications/data/sync_announcer.dart';
import 'package:smart_spend_tracker/features/notifications/domain/notification_kind.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

import 'engines/engines_test.dart' show tx;

class _Local extends Mock implements NotificationService {}

class _Repo extends Mock implements NotificationRepository {}

void main() {
  final now = DateTime.utc(2026, 11, 13, 12);
  late _Local local;
  late _Repo repo;

  setUpAll(() => registerFallbackValue(NotificationKind.sync));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    local = _Local();
    repo = _Repo();
    when(() => local.showTransactions(any(), summary: any(named: 'summary'))).thenAnswer((_) async {});
    when(() => local.show(
          title: any(named: 'title'),
          body: any(named: 'body'),
          kind: any(named: 'kind'),
          route: any(named: 'route'),
          tag: any(named: 'tag'),
          id: any(named: 'id'),
        )).thenAnswer((_) async {});
    when(() => repo.add(any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        type: any(named: 'type'),
        route: any(named: 'route'),
        lines: any(named: 'lines'),
        fanout: any(named: 'fanout'),
        originDevice: any(named: 'originDevice'))).thenAnswer((_) async {});
  });

  test('recent transactions: shown here, saved in-app, fanned out to other phones', () async {
    final txs = [
      tx(id: 'a', amount: 420, cp: 'Swiggy', date: now.subtract(const Duration(hours: 2))),
      tx(id: 'b', amount: 62000, dir: TxDirection.inflow, cp: 'Infosys', date: now.subtract(const Duration(hours: 5))),
    ];
    await SyncAnnouncer(local, repo).announce(uid: 'u', txs: txs, prefs: const {}, now: now);

    verify(() => local.showTransactions(any(that: hasLength(2)), summary: 'Sync complete')).called(1);
    final captured = verify(() => repo.add('u',
        title: captureAny(named: 'title'),
        body: any(named: 'body'),
        type: 'transaction',
        route: any(named: 'route'),
        lines: captureAny(named: 'lines'),
        fanout: true,
        originDevice: captureAny(named: 'originDevice'))).captured;
    expect(captured[0], '2 new transactions');
    expect(captured[1], ['−₹420  Swiggy', '+₹62,000  Infosys']); // newest first
    expect(captured[2], await DeviceId.get()); // this phone is excluded from the push
  });

  test('first sync of old history is not announced as new', () async {
    final old = [for (var i = 0; i < 40; i++) tx(id: 'o$i', amount: 100, date: now.subtract(Duration(days: 10 + i)))];
    await SyncAnnouncer(local, repo).announce(uid: 'u', txs: old, prefs: const {}, initial: true, now: now);

    verifyNever(() => local.showTransactions(any(), summary: any(named: 'summary')));
    // Listed in-app (for the bell badge) but never pushed to other phones.
    verifyNever(() => repo.add(any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        type: any(named: 'type'),
        route: any(named: 'route'),
        lines: any(named: 'lines'),
        fanout: true,
        originDevice: any(named: 'originDevice')));
    verify(() => repo.add('u', title: 'Initial sync complete', body: any(named: 'body'), type: 'sync', route: any(named: 'route'))).called(1);
    verify(() => local.show(
          title: 'Initial sync complete',
          body: '40 earlier transactions imported to your history',
          kind: NotificationKind.sync,
          route: any(named: 'route'),
          tag: any(named: 'tag'),
          id: any(named: 'id'),
        )).called(1);
  });

  test('turning off "New transaction" silences it everywhere', () async {
    await SyncAnnouncer(local, repo).announce(
      uid: 'u',
      txs: [tx(id: 'a', amount: 420, date: now)],
      prefs: const {'newTransaction': false},
      now: now,
    );
    verifyNever(() => local.showTransactions(any(), summary: any(named: 'summary')));
  });

  test('summary text for one and many transactions', () {
    final one = TxSummary.of([tx(id: 'a', amount: 420, cp: 'Swiggy', date: now)]);
    expect(one.title, 'Spent ₹420 at Swiggy');
    final many = TxSummary.of([
      tx(id: 'a', amount: 420, cp: 'Swiggy', date: now),
      tx(id: 'b', amount: 1890, dir: TxDirection.inflow, cp: 'Infosys', date: now.subtract(const Duration(hours: 1))),
    ]);
    expect(many.title, '2 new transactions');
    expect(many.body, 'Spent ₹420 • Received ₹1,890');
    expect(many.lines, hasLength(2));
  });

  test('device id is stable across calls', () async {
    expect(await DeviceId.get(), await DeviceId.get());
  });

  test('every sync with new transactions raises an in-app toast', () async {
    // Older-only import (quiet notification) → toast in the app.
    final old = [tx(id: 'o1', amount: 100, date: now.subtract(const Duration(days: 20))), tx(id: 'o2', amount: 50, date: now.subtract(const Duration(days: 21)))];
    await SyncAnnouncer(local, repo).announce(uid: 'u', txs: old, prefs: const {}, now: now);
    verify(() => local.toast(title: '2 new transactions added', body: any(named: 'body'), kind: NotificationKind.transaction, route: any(named: 'route'))).called(1);

    // Alerts turned off → still a toast in the app.
    clearInteractions(local);
    await SyncAnnouncer(local, repo).announce(uid: 'u', txs: [tx(id: 'a', amount: 420, cp: 'Swiggy', date: now)], prefs: const {'newTransaction': false}, now: now);
    verify(() => local.toast(title: 'Spent ₹420 at Swiggy', body: any(named: 'body'), kind: any(named: 'kind'), route: any(named: 'route'))).called(1);

    // Recent + alerts on → the notification itself raises the banner; no extra toast.
    clearInteractions(local);
    await SyncAnnouncer(local, repo).announce(uid: 'u', txs: [tx(id: 'b', amount: 99, date: now)], prefs: const {}, now: now);
    verifyNever(() => local.toast(title: any(named: 'title'), body: any(named: 'body'), kind: any(named: 'kind'), route: any(named: 'route')));

    // Nothing new → no toast.
    clearInteractions(local);
    await SyncAnnouncer(local, repo).announce(uid: 'u', txs: const [], prefs: const {}, now: now);
    verifyNever(() => local.toast(title: any(named: 'title'), body: any(named: 'body'), kind: any(named: 'kind'), route: any(named: 'route')));
  });
}
