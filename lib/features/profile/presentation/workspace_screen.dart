import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../workspace/domain/workspace.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    try {
      final code = await ref.read(workspaceRepositoryProvider).createInvite(ref.read(activeWorkspaceIdProvider)!, ref.read(authStateProvider).value!.uid);
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite code'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Share this code. It expires in 7 days and can be used during sign-up or from this screen.'),
            const SizedBox(height: 16),
            SelectableText(code, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 4)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
                showSnack(context, 'Code copied');
              },
              child: const Text('Copy'),
            ),
          ],
        ),
      );
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a workspace'),
        content: TextField(controller: c, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Invite code')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      final wid = await ref.read(workspaceRepositoryProvider).joinWithCode(code);
      await ref.read(workspaceRepositoryProvider).updateProfile(ref.read(authStateProvider).value!.uid, {'activeWorkspaceId': wid});
      if (context.mounted) showSnack(context, 'Joined workspace');
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider).value;
    final me = ref.watch(myMembershipProvider);
    final members = ref.watch(workspaceMembersProvider);
    final isAdmin = me?.isAdmin ?? false;
    final uid = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        AppCard(
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.home_work_rounded, color: AppColors.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ws?.name ?? '', style: context.text.titleMedium),
                Text('${ws?.currency ?? 'INR'} • ${ws?.timezone ?? ''}', style: TextStyle(color: context.secondaryText)),
              ]),
            ),
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final c = TextEditingController(text: ws?.name);
                  final name = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Rename workspace'),
                      content: TextField(controller: c, autofocus: true),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))],
                    ),
                  );
                  if (name != null && name.isNotEmpty) await ref.read(workspaceRepositoryProvider).renameWorkspace(ws!.id, name);
                },
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          if (isAdmin)
            Expanded(child: FilledButton.icon(onPressed: () => _invite(context, ref), icon: const Icon(Icons.person_add_alt_rounded), label: const Text('Invite'))),
          if (isAdmin) const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => _join(context, ref), icon: const Icon(Icons.login_rounded), label: const Text('Join another'))),
        ]),
        const SectionHeader('Members', subtitle: 'Members see shared transactions — never each other\'s inbox or source messages.'),
        members.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(e),
          data: (list) => AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              for (final m in list)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.navy,
                    child: Text((m.displayName ?? m.email ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text('${m.displayName ?? m.email ?? 'Member'}${m.userId == uid ? ' (you)' : ''}'),
                  subtitle: Text(m.email ?? ''),
                  trailing: isAdmin && m.userId != uid
                      ? PopupMenuButton<String>(
                          onSelected: (a) async {
                            final repo = ref.read(workspaceRepositoryProvider);
                            try {
                              if (a == 'remove') await repo.removeMember(m.workspaceId, m.userId);
                              if (a == 'admin') await repo.setMemberRole(m.workspaceId, m.userId, WorkspaceRole.admin);
                              if (a == 'member') await repo.setMemberRole(m.workspaceId, m.userId, WorkspaceRole.member);
                            } on AppFailure catch (e) {
                              if (context.mounted) showSnack(context, e.message, error: true);
                            }
                          },
                          itemBuilder: (_) => [
                            if (!m.isAdmin) const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                            if (m.isAdmin) const PopupMenuItem(value: 'member', child: Text('Make member')),
                            const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.expense))),
                          ],
                        )
                      : Chip(label: Text(m.isAdmin ? 'Admin' : 'Member'), visualDensity: VisualDensity.compact),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
