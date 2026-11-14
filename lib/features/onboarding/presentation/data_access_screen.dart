import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// Explains, before any permission prompt, exactly what is accessed and why.
class DataAccessScreen extends StatelessWidget {
  const DataAccessScreen({super.key});

  static const _items = [
    (Icons.sms_outlined, 'Bank SMS (Android)', 'Read transaction alerts from banks, cards, UPI apps and wallets. OTPs, promotions and personal messages are ignored.', AppColors.blue),
    (Icons.mail_outline_rounded, 'Email alerts (Gmail)', 'Read-only access to find bank and payment notifications. We never see or store your password.', Color(0xFFEA4335)),
    (Icons.phonelink_lock_rounded, 'Processed on your device', 'Messages are parsed locally. Only amount, date, merchant, category and a masked account are uploaded.', AppColors.income),
    (Icons.groups_2_outlined, 'Shared with your workspace', 'Members see consolidated transactions — never your inbox or message content.', Color(0xFF8B5CF6)),
  ];

  @override
  Widget build(BuildContext context) => OnboardingScaffold(
        step: 1,
        onBack: () => context.pop(),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Your data, your control', style: context.text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Smart Spend Tracker needs your permission to collect transactions automatically. Here is exactly what we use and why.',
                    style: TextStyle(color: context.secondaryText, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  for (final (icon, title, body, color) in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                              child: Icon(icon, color: color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(body, style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text('You can disconnect any source or delete your data at any time from Profile.',
                      style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(onPressed: () => context.push(Routes.setupSms), child: const Text('Continue')),
            ),
          ],
        ),
      );
}
