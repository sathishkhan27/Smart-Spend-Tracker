import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _poll;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Automatically detect verification done in the mail app.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => ref.read(authRepositoryProvider).refreshVerification());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).resendVerification();
      if (!mounted) return;
      showSnack(context, 'Verification email sent');
      setState(() => _cooldown = 60);
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _cooldown <= 1) {
          t.cancel();
          if (mounted) setState(() => _cooldown = 0);
        } else {
          setState(() => _cooldown--);
        }
      });
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authStateProvider).value?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.mark_email_unread_rounded, size: 56, color: AppColors.blue),
              ),
              const SizedBox(height: 28),
              Text('Verify your email', style: context.text.headlineMedium),
              const SizedBox(height: 10),
              Text(
                'We sent a verification link to\n$email\nOpen it to activate your account. This page updates automatically.',
                textAlign: TextAlign.center,
                style: context.text.bodyLarge?.copyWith(color: context.secondaryText, height: 1.5),
              ),
              const SizedBox(height: 24),
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final ok = await ref.read(authRepositoryProvider).refreshVerification();
                  if (!ok && context.mounted) showSnack(context, 'Not verified yet. Please check your inbox.');
                },
                child: const Text("I've verified my email"),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _cooldown > 0 ? null : _resend,
                child: Text(_cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend email'),
              ),
              TextButton(onPressed: () => signOutAndUnregister(ref), child: const Text('Use a different account')),
            ],
          ),
        ),
      ),
    );
  }
}
