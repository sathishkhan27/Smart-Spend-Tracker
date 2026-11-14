import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../sync/data/connected_accounts_repository.dart';
import '../../sync/data/gmail_source.dart';
import '../../sync/presentation/gmail_widgets.dart';

class EmailConnectScreen extends ConsumerStatefulWidget {
  const EmailConnectScreen({super.key, this.fromSettings = false});
  final bool fromSettings;

  @override
  ConsumerState<EmailConnectScreen> createState() => _EmailConnectScreenState();
}

class _EmailConnectScreenState extends ConsumerState<EmailConnectScreen> {
  bool _busy = false;
  String? _connected;

  Future<void> _connectGmail() async {
    final uid = ref.read(authStateProvider).value!.uid;
    final wid = ref.read(activeWorkspaceIdProvider)!;
    setState(() => _busy = true);
    try {
      final email = await ref.read(gmailSourceProvider).connect();
      await ref.read(workspaceRepositoryProvider).recordConsent(uid, source: 'gmail', granted: true, scope: GmailSource.scope);
      await ref.read(connectedAccountsRepositoryProvider).upsert(uid, wid, SourceProvider.gmail, ConnectionStatus.connected, identifier: email);
      setState(() => _connected = email);
      if (mounted) showSnack(context, 'Connected $email');
    } on AppFailure catch (e) {
      if (mounted && e.code != 'cancelled') showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, ErrorHandler.map(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (widget.fromSettings) {
      context.pop();
      return;
    }
    final uid = ref.read(authStateProvider).value!.uid;
    // Mark onboarding complete so future launches open the dashboard
    // immediately while any remaining sync continues in the background.
    await ref.read(workspaceRepositoryProvider).updateProfile(uid, {'onboardingComplete': true});
    if (mounted) context.go(Routes.setupSync);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(connectedAccountsProvider).value ?? const [];
    final existing = accounts.where((a) => a.provider == SourceProvider.gmail && a.isConnected).firstOrNull;
    final connected = _connected ?? existing?.identifier;
    return OnboardingScaffold(
      step: widget.fromSettings ? null : 3,
      onBack: () => context.pop(),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Connect your email', style: context.text.headlineMedium),
                const SizedBox(height: 8),
                Text('Bank statements, card alerts, bills and receipts arrive by email. Connect securely with OAuth — no passwords.',
                    style: TextStyle(color: context.secondaryText, height: 1.4)),
                const SizedBox(height: 24),
                _ProviderTile(
                  icon: Icons.mail_rounded,
                  color: const Color(0xFFEA4335),
                  title: 'Gmail',
                  subtitle: connected ?? (GmailSource.isConfigured ? 'Read-only access to financial emails' : 'Setup pending • tap for details'),
                  connected: connected != null,
                  busy: _busy,
                  onTap: connected != null ? null : (GmailSource.isConfigured ? _connectGmail : () => showGmailSetupSheet(context)),
                  trailing: connected == null ? const GmailStatusLabel() : null,
                ),
                const SizedBox(height: 12),
                const _ProviderTile(
                  icon: Icons.window_rounded,
                  color: Color(0xFF0078D4),
                  title: 'Outlook / Microsoft 365',
                  subtitle: 'Coming soon (Microsoft Graph)',
                  connected: false,
                  busy: false,
                  onTap: null,
                  disabled: true,
                ),
                const SizedBox(height: 20),
                AppCard(
                  color: AppColors.blue.withValues(alpha: 0.06),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, color: AppColors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'We request only the gmail.readonly scope and filter for financial senders. '
                          'You can revoke access anytime from Profile → Connected sources or your Google account.',
                          style: context.text.bodySmall?.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(children: [
              FilledButton(
                onPressed: _finish,
                child: Text(widget.fromSettings ? 'Done' : (connected != null ? 'Start sync' : 'Continue')),
              ),
              if (connected == null && !widget.fromSettings) TextButton(onPressed: _finish, child: const Text('Skip for now')),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.busy,
    required this.onTap,
    this.disabled = false,
    this.trailing,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool connected;
  final bool busy;
  final VoidCallback? onTap;
  final bool disabled;

  /// Replaces the default "Connect" label when not connected.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: disabled ? 0.55 : 1,
        child: AppCard(
          onTap: onTap,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
              ]),
            ),
            if (busy)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            else if (connected)
              const Icon(Icons.check_circle_rounded, color: AppColors.income)
            else if (trailing != null)
              trailing!
            else if (!disabled)
              const Text('Connect', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}
