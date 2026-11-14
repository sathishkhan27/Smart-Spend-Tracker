import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _page = PageController();
  int _index = 0;

  static const _slides = [
    (Icons.auto_awesome_rounded, 'No more manual entry', 'Transactions are picked up automatically from your authorized bank SMS and email alerts.'),
    (Icons.pie_chart_rounded, 'Know where money goes', 'Smart categorization, monthly & yearly insights, and beautiful charts.'),
    (Icons.groups_rounded, 'Shared with your family', 'Invite members to a workspace and see consolidated spending together — securely.'),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.heroGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Align(alignment: Alignment.centerLeft, child: AppWordmark(logoSize: 42, light: true)),
                  Expanded(
                    child: PageView.builder(
                      controller: _page,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) {
                        final (icon, title, body) = _slides[i];
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _Illustration(icon: icon),
                            const SizedBox(height: 40),
                            Text(title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 12),
                            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.45)),
                          ],
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(color: i == _index ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                    onPressed: () => context.push(Routes.register),
                    child: const Text('Create account'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                    onPressed: () => context.push(Routes.login),
                    child: const Text('I already have an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06))),
            Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1))),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
              child: Icon(icon, size: 48, color: AppColors.blue),
            ),
            const Positioned(top: 22, right: 30, child: _Chip(icon: Icons.south_west_rounded, color: AppColors.income)),
            const Positioned(bottom: 26, left: 22, child: _Chip(icon: Icons.north_east_rounded, color: AppColors.expense)),
            const Positioned(bottom: 40, right: 12, child: _Chip(icon: Icons.restaurant_rounded, color: Color(0xFFF97316))),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
        ]),
        child: Icon(icon, color: color, size: 20),
      );
}
