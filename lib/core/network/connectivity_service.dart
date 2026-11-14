import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Reports real internet reachability, not just "Wi-Fi/mobile is on".
///
/// * No network interface → offline immediately.
/// * Otherwise reachability is probed (IPv4 DNS, then an HTTPS request), and
///   "offline" is only reported after two failed probes in a row, so a slow
///   DNS server or a momentary blip never shows a false offline state.
/// * While offline it re-checks periodically (dead Wi-Fi, login portals).
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity, Future<bool> Function()? probe})
      : _connectivity = connectivity ?? Connectivity(),
        _probeOverride = probe;

  final Connectivity _connectivity;
  final Future<bool> Function()? _probeOverride;

  static const _probeHost = 'firestore.googleapis.com';
  static final _probeUrl = Uri.parse('https://www.gstatic.com/generate_204');
  static const _offlineRecheck = Duration(seconds: 10);
  static const _confirmDelay = Duration(seconds: 3);

  Stream<bool> watch() {
    late final StreamController<bool> controller;
    StreamSubscription<List<ConnectivityResult>>? sub;
    Timer? timer;
    bool? last;
    var generation = 0;

    Future<void> evaluate([List<ConnectivityResult>? results]) async {
      final gen = ++generation;
      var online = await isOnline(results);
      // Confirm a failed probe before telling the user they're offline.
      if (!online && last != false && !_noInterface(results ?? await _safeCheck())) {
        await Future<void>.delayed(_confirmDelay);
        if (gen != generation || controller.isClosed) return;
        online = await isOnline();
      }
      if (gen != generation || controller.isClosed) return;
      if (online != last) {
        last = online;
        _log('state → ${online ? 'online' : 'offline'}');
        controller.add(online);
      }
      timer?.cancel();
      if (!online) timer = Timer(_offlineRecheck, evaluate);
    }

    controller = StreamController<bool>(
      onListen: () {
        evaluate();
        sub = _connectivity.onConnectivityChanged.listen(evaluate);
      },
      onCancel: () async {
        timer?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<bool> isOnline([List<ConnectivityResult>? results]) async {
    results ??= await _safeCheck();
    if (_noInterface(results)) {
      _log('no network interface ($results)');
      return false;
    }
    if (kIsWeb) return true;
    return (_probeOverride ?? _probe)();
  }

  static bool _noInterface(List<ConnectivityResult> r) => r.isNotEmpty && r.every((e) => e == ConnectivityResult.none);

  Future<List<ConnectivityResult>> _safeCheck() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      _log('checkConnectivity failed: $e');
      // Unknown interface state: let the probe decide.
      return const [ConnectivityResult.other];
    }
  }

  Future<bool> _probe() async {
    // 1. IPv4 lookup only: some networks never answer IPv6 (AAAA) queries,
    //    which made a combined lookup time out and report a false "offline".
    try {
      final found = await InternetAddress.lookup(_probeHost, type: InternetAddressType.IPv4).timeout(const Duration(seconds: 6));
      if (found.isNotEmpty) return true;
    } catch (e) {
      _log('DNS probe failed: $e');
    }
    // 2. Real HTTPS round-trip (works even if the DNS probe path is odd).
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.headUrl(_probeUrl).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      return res.statusCode < 500;
    } catch (e) {
      _log('HTTPS probe failed: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static void _log(String m) {
    if (kDebugMode) debugPrint('[connectivity] $m');
  }
}
