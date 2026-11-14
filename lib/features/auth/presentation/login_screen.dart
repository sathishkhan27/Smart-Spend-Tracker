import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).login(email: _email.text, password: _password.text);
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) {
      showSnack(context, 'Enter your email above first.', error: true);
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) showSnack(context, 'Password reset link sent to ${_email.text.trim()}');
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Welcome back',
        subtitle: 'Sign in to see your consolidated finances.',
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
                  validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _reset, child: const Text('Forgot password?'))),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const _ButtonSpinner() : const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("Don't have an account?", style: TextStyle(color: context.secondaryText)),
                  TextButton(onPressed: () => context.pushReplacement(Routes.register), child: const Text('Create one')),
                ]),
              ],
            ),
          ),
        ),
      );
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              const Align(alignment: Alignment.centerLeft, child: AppWordmark(logoSize: 48)),
              const SizedBox(height: 24),
              Text(title, style: context.text.headlineMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: context.text.bodyLarge?.copyWith(color: context.secondaryText)),
              const SizedBox(height: 32),
              child,
            ],
          ),
        ),
      );
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({super.key});
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white));
}

class ButtonSpinner extends _ButtonSpinner {
  const ButtonSpinner({super.key});
}
