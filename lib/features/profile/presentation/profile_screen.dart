import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../sync/data/background_sync.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _deleteData(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete my data?'),
        content: const Text(
            'This permanently deletes every transaction you contributed, your connected sources, sync history and your account. '
            'Workspaces you own with other members are transferred to another admin. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete everything', style: TextStyle(color: AppColors.expense))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final uid = ref.read(authStateProvider).value!.uid;
      await ref.read(workspaceRepositoryProvider).requestDataDeletion();
      await ref.read(localStoreProvider).clearUser(uid);
      await ref.read(gmailSourceProvider).disconnect().catchError((_) {});
      await BackgroundSync.cancel().catchError((_) {});
      await signOutAndUnregister(ref);
    } on AppFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final workspace = ref.watch(activeWorkspaceProvider).value;
    final membership = ref.watch(myMembershipProvider);
    final theme = ref.watch(themeModeProvider);
    final uid = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 120), children: [
        AppCard(
          child: Row(children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [AppColors.navy, AppColors.blue], begin: Alignment.bottomLeft, end: Alignment.topRight),
              ),
              child: Text(profile?.initials ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile?.displayName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(profile?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('${workspace?.name ?? ''} • ${membership?.isAdmin == true ? 'Admin' : 'Member'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.blue, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            IconButton(
              onPressed: () => _editName(context, ref, profile?.displayName ?? ''),
              icon: Icon(Icons.edit_outlined, color: context.secondaryText),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        _Group(children: [
          _Item(Icons.groups_2_outlined, 'Workspace & members', () => context.push(Routes.workspace)),
          _Item(Icons.link_rounded, 'Connected sources', () => context.push(Routes.sources)),
          _Item(Icons.account_balance_wallet_outlined, 'Monthly budget', () => context.push(Routes.budget)),
          _Item(Icons.notifications_none_rounded, 'Notification preferences', () => context.push(Routes.notificationSettings)),
          _Item(Icons.add_card_rounded, 'Add transaction manually', () => context.push(Routes.addTransaction)),
        ]),
        const SizedBox(height: 14),
        _Group(children: [
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Theme'),
            trailing: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 18)),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined, size: 18)),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_outlined, size: 18)),
              ],
              selected: {theme},
              onSelectionChanged: (s) => ref.read(workspaceRepositoryProvider).updateProfile(uid!, {'themeMode': s.first.name}),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('Timezone'),
            subtitle: Text(profile?.timezone ?? 'Asia/Kolkata'),
          ),
        ]),
        const SizedBox(height: 14),
        _Group(children: [
          _Item(Icons.logout_rounded, 'Sign out', () async {
            await BackgroundSync.cancel().catchError((_) {});
            await signOutAndUnregister(ref);
          }),
          _Item(Icons.delete_forever_outlined, 'Delete my data', () => _deleteData(context, ref), color: AppColors.expense),
        ]),
        const SizedBox(height: 20),
        Center(child: Text('Smart Spend Tracker • v1.0.0', style: context.text.bodySmall?.copyWith(color: context.secondaryText))),
      ]),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(authRepositoryProvider).updateDisplayName(name);
    await ref.read(workspaceRepositoryProvider).updateProfile(ref.read(authStateProvider).value!.uid, {'displayName': name});
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children));
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label, this.onTap, {this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
