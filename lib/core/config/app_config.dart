/// Build-time configuration supplied with `--dart-define` (never hardcoded).
///
/// ```
/// flutter run \
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
/// ```
abstract final class AppConfig {
  static const appName = 'Smart Spend Tracker';

  /// OAuth "Web application" client ID (required by google_sign_in on Android).
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// OAuth iOS client ID (iOS only).
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Enables Firebase App Check debug provider (development builds only).
  static const appCheckDebug = bool.fromEnvironment('APP_CHECK_DEBUG', defaultValue: true);

  /// Days of history scanned during the initial sync.
  static const initialSyncDays = int.fromEnvironment('INITIAL_SYNC_DAYS', defaultValue: 180);

  /// Cloud Functions region.
  static const functionsRegion = String.fromEnvironment('FUNCTIONS_REGION', defaultValue: 'asia-south1');
}
