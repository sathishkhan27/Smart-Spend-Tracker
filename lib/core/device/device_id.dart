import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable per-install identifier. Each phone signed in to the same account
/// registers its push token under its own id (users/{uid}/devices/{id}), so a
/// refreshed token replaces the old one instead of piling up duplicates.
abstract final class DeviceId {
  static const _key = 'ss_device_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_key);
      if (existing != null) return _cached = existing;
      final id = _generate();
      await prefs.setString(_key, id);
      return _cached = id;
    } catch (_) {
      return _cached ??= _generate(); // prefs unavailable: stable for this run
    }
  }

  static String get platform => defaultTargetPlatform.name;

  static String _generate() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
