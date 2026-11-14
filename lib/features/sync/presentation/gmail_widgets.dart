import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../data/connected_accounts_repository.dart';
import '../data/gmail_source.dart';

const gmailRed = Color(0xFFEA4335);

/// Explains why Gmail can't be connected in this build yet.
Future<void> showGmailSetupSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: gmailRed.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.mail_lock_rounded, color: gmailRed),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Gmail setup pending', style: ctx.text.titleLarge)),
            ]),
            const SizedBox(height: 12),
            Text(
              'Email sync needs Google sign-in to be enabled for this app. Once it is set up, '
              'you can connect Gmail here in one tap. SMS tracking keeps working in the meantime.',
              style: ctx.text.bodyMedium?.copyWith(color: ctx.secondaryText, height: 1.5),
            ),
            const SizedBox(height: 14),
            for (final step in const [
              'Enable Google sign-in in Firebase Authentication',
              'Add the app signing SHA-1 and download the new google-services.json',
              'Enable the Gmail API and add test users to the OAuth consent screen',
              'Run the app with the Google web client ID',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.blue),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step, style: ctx.text.bodySmall?.copyWith(height: 1.4))),
                ]),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
          ]),
        ),
      ),
    );

/// "Setup needed" / "Connect" trailing label for Gmail tiles.
class GmailStatusLabel extends StatelessWidget {
  const GmailStatusLabel({super.key});

  @override
  Widget build(BuildContext context) => GmailSource.isConfigured
      ? const Text('Connect', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700))
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
          child: const Text('Setup needed', style: TextStyle(color: Color(0xFFB7791F), fontSize: 11, fontWeight: FontWeight.w700)),
        );
}

/// Home card nudging the user to connect email until Gmail is connected.
/// "Not now" hides it on this device.
class ConnectEmailPrompt extends ConsumerStatefulWidget {
  const ConnectEmailPrompt({super.key});

  @override
  ConsumerState<ConnectEmailPrompt> createState() => _ConnectEmailPromptState();
}

class _ConnectEmailPromptState extends ConsumerState<ConnectEmailPrompt> {
  static const _prefKey = 'hide_connect_email_prompt';
  bool _hidden = true; // until prefs load, to avoid a flash

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _hidden = p.getBool(_prefKey) ?? false);
    }).catchError((Object _) {
      if (mounted) setState(() => _hidden = false);
    });
  }

  Future<void> _dismiss() async {
    setState(() => _hidden = true);
    try {
      (await SharedPreferences.getInstance()).setBool(_prefKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(connectedAccountsProvider);
    final connected = (accounts.value ?? const []).any((a) => a.provider == SourceProvider.gmail && a.isConnected);
    if (_hidden || connected || !accounts.hasValue) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
        onTap: () => context.push('${Routes.setupEmail}?settings=1'),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: gmailRed.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.mail_rounded, color: gmailRed, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Connect your email', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Capture card statements, bills and receipts that arrive by email.',
                    style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _dismiss, child: const Text('Not now')),
            const SizedBox(width: 4),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () => context.push('${Routes.setupEmail}?settings=1'),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Connect Gmail'),
            ),
          ]),
        ]),
      ),
    );
  }
}
