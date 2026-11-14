import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:smart_spend_tracker/core/network/connectivity_service.dart';

class _MockConnectivity extends Mock implements Connectivity {}

void main() {
  test('no network interface means offline without probing DNS', () async {
    final c = _MockConnectivity();
    when(c.checkConnectivity).thenAnswer((_) async => [ConnectivityResult.none]);
    expect(await ConnectivityService(connectivity: c).isOnline(), isFalse);
  });

  test('watch emits offline once and de-duplicates repeats', () async {
    final c = _MockConnectivity();
    when(c.checkConnectivity).thenAnswer((_) async => [ConnectivityResult.none]);
    when(() => c.onConnectivityChanged).thenAnswer((_) => Stream.fromIterable([
          [ConnectivityResult.none],
          [ConnectivityResult.none],
        ]));
    final values = await ConnectivityService(connectivity: c).watch().take(1).toList();
    expect(values, [false]);
  });

  test('a single failed probe on Wi-Fi does not report offline', () async {
    final c = _MockConnectivity();
    when(c.checkConnectivity).thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => c.onConnectivityChanged).thenAnswer((_) => const Stream.empty());
    var calls = 0;
    final svc = ConnectivityService(connectivity: c, probe: () async => ++calls > 1); // fails once, then succeeds
    expect(await svc.watch().first, isTrue);
    expect(calls, 2);
  });

  test('two failed probes report offline', () async {
    final c = _MockConnectivity();
    when(c.checkConnectivity).thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => c.onConnectivityChanged).thenAnswer((_) => const Stream.empty());
    final svc = ConnectivityService(connectivity: c, probe: () async => false);
    expect(await svc.watch().first, isFalse);
  });
}
