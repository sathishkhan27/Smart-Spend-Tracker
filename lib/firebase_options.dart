// Firebase configuration for project smart-spend-27d7c.
//
// These are Firebase *client* identifiers (safe to ship in the app — access is
// enforced by Firestore security rules and App Check, not by these values).
// Regenerate with: flutterfire configure --project=smart-spend-27d7c
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyCsVe5Da6WfB2ugi_mDr68NkicRBLTGgGs',
    appId: '1:54599778836:android:ceb71839290135f97e1d01',
    messagingSenderId: '54599778836',
    projectId: 'smart-spend-27d7c',
    storageBucket: 'smart-spend-27d7c.firebasestorage.app',
  );

  /// iOS app is not registered yet. Add it in the Firebase console (bundle ID
  /// com.smartspend.smartSpendTracker), then fill in [_iosAppId] or run
  /// `flutterfire configure`.
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static FirebaseOptions get currentPlatform {
    final o = currentPlatformOrNull;
    if (o == null) throw UnsupportedError('Firebase is not configured for $defaultTargetPlatform');
    return o;
  }

  /// Null when this platform has no Firebase app registered yet.
  static FirebaseOptions? get currentPlatformOrNull {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        if (_iosAppId.isEmpty) return null;
        return FirebaseOptions(
          apiKey: android.apiKey,
          appId: _iosAppId,
          messagingSenderId: android.messagingSenderId,
          projectId: android.projectId,
          storageBucket: android.storageBucket,
          iosBundleId: 'com.smartspend.smartSpendTracker',
        );
      default:
        return null;
    }
  }
}
