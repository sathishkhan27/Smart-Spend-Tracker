import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import 'login_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _accepted = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_accepted) {
      showSnack(context, 'Please accept the terms and privacy policy.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).register(name: _name.text, email: _email.text, password: _password.text);
    } on AppFailure catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _passwordRule(String? v) {
    final s = v ?? '';
    if (s.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Include letters and numbers';
    return null;
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Create your account',
        subtitle: 'Start tracking spends automatically in minutes.',
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name' : null,
              ),
              const SizedBox(height: 14),
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
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters with letters and numbers',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: _passwordRule,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(value: _accepted, onChanged: (v) => setState(() => _accepted = v ?? false)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(color: context.secondaryText, fontSize: 13),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms & Privacy Policy',
                              style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600),
                              recognizer: TapGestureRecognizer()..onTap = () => _showPolicy(context),
                            ),
                            const TextSpan(text: '. Data is accessed only with explicit permission.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const ButtonSpinner() : const Text('Create account')),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Already registered?', style: TextStyle(color: context.secondaryText)),
                TextButton(onPressed: () => context.pushReplacement(Routes.login), child: const Text('Sign in')),
              ]),
            ],
          ),
        ),
      );

  void _showPolicy(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              SizedBox(height: 12),
              Text('• SMS and email are read only after you grant permission, and only to detect financial transactions.\n'
                  '• Messages are parsed on your device. Only extracted transaction fields are stored.\n'
                  '• Account numbers are masked. Raw message excerpts are visible only to you.\n'
                  '• Workspace members see shared transactions — never your email or SMS inbox.\n'
                  '• You can disconnect sources or request deletion of your data at any time.'),
            ],
          ),
        ),
      );
}
