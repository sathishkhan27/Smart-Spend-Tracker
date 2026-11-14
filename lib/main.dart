import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'core/di/providers.dart';

Future<void> main() async {
  final boot = await Bootstrap.init();
  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(boot.localStore),
      notificationServiceProvider.overrideWithValue(boot.notifications),
    ],
    child: boot.firebaseReady ? const SmartSpendApp() : FirebaseSetupRequiredApp(error: boot.error),
  ));
}
