import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../sync/data/connected_accounts_repository.dart';
import '../../sync/data/sync_service.dart';
import '../../sync/domain/sync_progress.dart';
import '../../sync/data/gmail_source.dart';
import '../../sync/presentation/gmail_widgets.dart';

class ConnectedSourcesScreen extends ConsumerWidget {
  const ConnectedSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(connectedAccountsProvider).value ?? const [];
    final progress = ref.watch(syncProgressProvider).value;
    ConnectedAccount? find(SourceProvider p) => accounts.where((a) => a.provider == p).firstOrNull;
    final uid = ref.watch(authStateProvider).value?.uid;
    final wid = ref.watch(activeWorkspaceIdProvider);

    Widget tile(SourceProvider p, IconData icon, Color color, String title,
        {required VoidCallback onConnect, required Future<void> Function() onDisconnect, bool setupPending = false}) {
      final a = find(p);
      final connected = a?.isConnected ?? false;
      final state = progress?.sources[p == SourceProvider.sms ? 'sms' : 'gmail'];
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  switch (a?.status) {
                    ConnectionStatus.connected => a?.identifier ?? 'Connected',
                    ConnectionStatus.needsReauth => 'Re-authorization required',
                    ConnectionStatus.error => a?.lastError ?? 'Error',
                    _ => setupPending ? 'Setup pending' : 'Not connected',
                  },
                  style: TextStyle(color: a?.status == ConnectionStatus.connected ? context.secondaryText : AppColors.warning, fontSize: 12),
                ),
              ]),
            ),
            if (connected)
              TextButton(onPressed: onDisconnect, child: const Text('Disconnect', style: TextStyle(color: AppColors.expense)))
            else
              FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 40)), onPressed: onConnect, child: const Text('Connect')),
          ]),
          if (a != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last sync: ${a.lastSyncAt == null ? 'never' : '${Fmt.date(a.lastSyncAt!)} ${Fmt.time(a.lastSyncAt!)}'} • '
              '${a.messagesScanned} scanned • ${a.transactionsFound} transactions',
              style: context.text.bodySmall?.copyWith(color: context.secondaryText),
            ),
          ],
          if (state?.status == SourceSyncStatus.failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Last attempt failed: ${state!.error}', style: const TextStyle(color: AppColors.expense, fontSize: 12)),
            ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Connected sources')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        tile(
          SourceProvider.sms,
          Icons.sms_rounded,
          AppColors.blue,
          'Device SMS',
          onConnect: () => context.push('${Routes.setupSms}?settings=1'),
          onDisconnect: () async {
            await ref.read(workspaceRepositoryProvider).recordConsent(uid!, source: 'sms', granted: false);
            await ref.read(connectedAccountsRepositoryProvider).upsert(uid, wid!, SourceProvider.sms, ConnectionStatus.disconnected);
            if (context.mounted) showSnack(context, 'SMS sync stopped. You can also revoke the permission in Android settings.');
          },
        ),
        const SizedBox(height: 12),
        tile(
          SourceProvider.gmail,
          Icons.mail_rounded,
          const Color(0xFFEA4335),
          'Gmail',
          setupPending: !GmailSource.isConfigured,
          onConnect: () => GmailSource.isConfigured ? context.push('${Routes.setupEmail}?settings=1') : showGmailSetupSheet(context),
          onDisconnect: () async {
            await ref.read(gmailSourceProvider).disconnect();
            await ref.read(workspaceRepositoryProvider).recordConsent(uid!, source: 'gmail', granted: false);
            await ref.read(connectedAccountsRepositoryProvider).upsert(uid, wid!, SourceProvider.gmail, ConnectionStatus.disconnected);
            if (context.mounted) showSnack(context, 'Gmail disconnected and access revoked');
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: progress?.isRunning == true
              ? null
              : () {
                  final ctx = ref.read(processingContextProvider);
                  if (ctx != null) ref.read(syncServiceProvider).run(SyncRequest(ctx: ctx));
                },
          icon: progress?.isRunning == true
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync_rounded),
          label: Text(progress?.isRunning == true ? progress!.stage.message : 'Sync now'),
        ),
        if (progress != null && progress.queued > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${progress.queued} records queued offline — they upload automatically when you are back online.',
                textAlign: TextAlign.center, style: context.text.bodySmall),
          ),
      ]),
    );
  }
}
