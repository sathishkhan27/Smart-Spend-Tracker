import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../sync/data/connected_accounts_repository.dart';

class SmsConnectScreen extends ConsumerStatefulWidget {
  const SmsConnectScreen({super.key, this.fromSettings = false});
  final bool fromSettings;

  @override
  ConsumerState<SmsConnectScreen> createState() => _SmsConnectScreenState();
}

class _SmsConnectScreenState extends ConsumerState<SmsConnectScreen> {
  bool _consent = false;
  bool _busy = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    ref.read(smsSourceProvider).hasPermission().then((g) {
      if (mounted) setState(() => _granted = g);
    });
  }

  void _next() => widget.fromSettings ? context.pop() : context.push(Routes.setupEmail);

  Future<void> _allow() async {
    final uid = ref.read(authStateProvider).value!.uid;
    final wid = ref.read(activeWorkspaceIdProvider)!;
    setState(() => _busy = true);
    try {
      final status = await ref.read(smsSourceProvider).requestPermission();
      final granted = status.isGranted;
      await ref.read(workspaceRepositoryProvider).recordConsent(uid, source: 'sms', granted: granted, scope: 'READ_SMS,RECEIVE_SMS');
      await ref.read(connectedAccountsRepositoryProvider).upsert(
          uid, wid, SourceProvider.sms, granted ? ConnectionStatus.connected : ConnectionStatus.disconnected,
          identifier: 'Device SMS');
      setState(() => _granted = granted);
      if (!mounted) return;
      if (granted) {
        showSnack(context, 'SMS access granted');
        _next();
      } else if (status.isPermanentlyDenied) {
        showSnack(context, 'Permission blocked. Enable SMS for Smart Spend in system settings.', error: true);
        await openAppSettings();
      } else {
        showSnack(context, 'SMS permission was not granted', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(smsSourceProvider).isSupported;
    return OnboardingScaffold(
      step: widget.fromSettings ? null : 2,
      onBack: () => context.pop(),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.sms_rounded, size: 52, color: AppColors.blue),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Connect bank SMS', style: context.text.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  supported
                      ? 'Allow Smart Spend to read transaction alerts from your SMS inbox and detect new ones as they arrive.'
                      : 'iOS does not allow apps to read the SMS inbox. Connect your email instead — most banks send the same alerts by email.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.secondaryText, height: 1.4),
                ),
                const SizedBox(height: 24),
                if (supported) ...[
                  const AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bullet(Icons.check_circle_rounded, AppColors.income, 'Bank, card, UPI, wallet & loan alerts'),
                        _Bullet(Icons.block_rounded, AppColors.expense, 'OTPs, promotions & personal chats are skipped'),
                        _Bullet(Icons.lock_rounded, AppColors.blue, 'Parsed on-device; message text is never shared'),
                        _Bullet(Icons.history_rounded, AppColors.warning, 'Scans the last 6 months, then only new messages'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_granted)
                    const AppCard(
                      color: Color(0x1416A36A),
                      child: Row(children: [
                        Icon(Icons.verified_rounded, color: AppColors.income),
                        SizedBox(width: 10),
                        Text('SMS access is enabled', style: TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    )
                  else
                    CheckboxListTile(
                      value: _consent,
                      onChanged: (v) => setState(() => _consent = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('I consent to Smart Spend reading financial SMS for automatic transaction tracking.'),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                if (supported && !_granted)
                  FilledButton(
                    onPressed: (_consent && !_busy) ? _allow : null,
                    child: _busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Allow SMS access'),
                  )
                else
                  FilledButton(onPressed: _next, child: Text(widget.fromSettings ? 'Done' : 'Continue')),
                if (supported && !_granted)
                  TextButton(onPressed: _next, child: Text(widget.fromSettings ? 'Not now' : 'Skip for now')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}
