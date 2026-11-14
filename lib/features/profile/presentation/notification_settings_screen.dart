import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/widgets/common.dart';
import '../../workspace/domain/workspace.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (final e in NotificationPrefKeys.labels.entries)
              SwitchListTile(
                title: Text(e.value),
                value: profile?.pref(e.key) ?? true,
                onChanged: profile == null
                    ? null
                    : (v) => ref.read(workspaceRepositoryProvider).updateProfile(profile.uid, {
                          'notificationPrefs': {...profile.notificationPrefs, e.key: v},
                        }),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await ref.read(notificationServiceProvider).requestPermission();
            if (context.mounted) showSnack(context, ok ? 'Notifications enabled' : 'Notifications are blocked in system settings', error: !ok);
          },
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Allow notifications on this device'),
        ),
        const SizedBox(height: 10),
        const _TestNotificationButton(),
      ]),
    );
  }
}

/// Sends a real push from the server to every phone on this account, to check
/// delivery with the app open (in-app banner + ding) or closed.
class _TestNotificationButton extends ConsumerStatefulWidget {
  const _TestNotificationButton();

  @override
  ConsumerState<_TestNotificationButton> createState() => _TestNotificationButtonState();
}

class _TestNotificationButtonState extends ConsumerState<_TestNotificationButton> {
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(functionsProvider).httpsCallable('sendTestNotification').call();
      final n = (res.data as Map?)?['devices'] as int? ?? 0;
      if (!mounted) return;
      showSnack(
        context,
        n == 0 ? 'No phone is registered for notifications yet. Reopen the app and allow notifications.' : 'Test sent to $n phone${n == 1 ? '' : 's'}',
        error: n == 0,
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Could not send the test. Check your internet connection.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: _busy ? null : _send,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_rounded),
        label: const Text('Send test notification'),
      );
}
