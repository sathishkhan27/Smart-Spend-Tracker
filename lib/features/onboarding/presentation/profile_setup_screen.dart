import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/widgets/common.dart';
import '../../auth/presentation/login_screen.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(profileProvider).value?.displayName ?? '');
  final _phone = TextEditingController();
  final _workspace = TextEditingController();
  final _invite = TextEditingController();
  String _timezone = AppClock.defaultTimezone;
  String _currency = 'INR';
  bool _joinExisting = false;
  bool _busy = false;

  static const timezones = ['Asia/Kolkata', 'Asia/Dubai', 'Asia/Singapore', 'Europe/London', 'America/New_York', 'America/Los_Angeles', 'UTC'];
  static const currencies = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD'];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _workspace.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_form.currentState!.validate()) return;
    final uid = ref.read(authStateProvider).value!.uid;
    final repo = ref.read(workspaceRepositoryProvider);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updateDisplayName(_name.text.trim());
      final fields = <String, Object?>{
        'displayName': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'timezone': _timezone,
        'currency': _currency,
      };
      if (_joinExisting) {
        final wid = await repo.joinWithCode(_invite.text);
        fields['activeWorkspaceId'] = wid;
      } else if (_workspace.text.trim().isNotEmpty) {
        final wid = ref.read(activeWorkspaceIdProvider);
        if (wid != null) await repo.renameWorkspace(wid, _workspace.text.trim());
      }
      await repo.updateProfile(uid, fields);
      AppClock.setTimezone(_timezone);
      if (mounted) context.push(Routes.setupAccess);
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OnboardingScaffold(
        step: 0,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Set up your profile', style: context.text.headlineMedium),
              const SizedBox(height: 6),
              Text('This helps us show dates and amounts correctly.', style: TextStyle(color: context.secondaryText)),
              const SizedBox(height: 28),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number (optional)', prefixIcon: Icon(Icons.phone_iphone_rounded)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _timezone,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Timezone'),
                    items: [for (final t in timezones) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _timezone = v!),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 28),
              Text('Workspace', style: context.text.titleMedium),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Create new'), icon: Icon(Icons.add_home_outlined)),
                  ButtonSegment(value: true, label: Text('Join with code'), icon: Icon(Icons.group_add_outlined)),
                ],
                selected: {_joinExisting},
                onSelectionChanged: (s) => setState(() => _joinExisting = s.first),
              ),
              const SizedBox(height: 14),
              if (_joinExisting)
                TextFormField(
                  controller: _invite,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Invite code', prefixIcon: Icon(Icons.vpn_key_outlined)),
                  validator: (v) => _joinExisting && (v?.trim().length ?? 0) < 6 ? 'Enter the 8-character code' : null,
                )
              else
                TextFormField(
                  controller: _workspace,
                  decoration: const InputDecoration(labelText: 'Workspace name (e.g. Family)', prefixIcon: Icon(Icons.home_work_outlined)),
                ),
              const SizedBox(height: 32),
              FilledButton(onPressed: _busy ? null : _continue, child: _busy ? const ButtonSpinner() : const Text('Continue')),
              TextButton(onPressed: () => signOutAndUnregister(ref), child: const Text('Sign out')),
            ],
          ),
        ),
      );
}
