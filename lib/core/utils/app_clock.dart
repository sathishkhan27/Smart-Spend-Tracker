import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Timezone-aware clock. Bank transaction dates are interpreted in the
/// workspace timezone (default Asia/Kolkata), not the device timezone.
class AppClock {
  AppClock._();
  static bool _initialized = false;
  static tz.Location _location = tz.UTC;

  static const defaultTimezone = 'Asia/Kolkata';

  static void init([String timezone = defaultTimezone]) {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    setTimezone(timezone);
  }

  static void setTimezone(String name) {
    try {
      _location = tz.getLocation(name);
    } catch (_) {
      _location = tz.getLocation(defaultTimezone);
    }
  }

  static String get timezoneName => _location.name;
  static tz.Location get location => _location;

  /// Current wall-clock time in the configured timezone.
  static DateTime now() {
    if (!_initialized) return DateTime.now();
    final n = tz.TZDateTime.now(_location);
    return DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second);
  }

  /// Converts a wall-clock date/time (as printed by the bank) into a UTC instant.
  static DateTime toUtc(DateTime wallClock) {
    if (!_initialized) return wallClock.toUtc();
    return tz.TZDateTime(_location, wallClock.year, wallClock.month, wallClock.day, wallClock.hour,
            wallClock.minute, wallClock.second)
        .toUtc();
  }

  /// Converts a stored UTC instant back to wall-clock time in the configured timezone.
  static DateTime toLocal(DateTime utc) {
    if (!_initialized) return utc.toLocal();
    final t = tz.TZDateTime.from(utc.toUtc(), _location);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }
}
