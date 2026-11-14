import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Explains why the app asks for SMS and notification access, shown once per
/// install before the system prompts (Android/Play require a clear disclosure
/// before requesting SMS). Returns true when the user taps "Allow access".
Future<bool> showPermissionIntro(BuildContext context, {required bool sms, required bool notifications}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _PermissionSheet(sms: sms, notifications: notifications),
  );
  return ok ?? false;
}

class _PermissionSheet extends StatefulWidget {
  const _PermissionSheet({required this.sms, required this.notifications});
  final bool sms;
  final bool notifications;

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 10));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _orbit.dispose();
    super.dispose();
  }

  Animation<double> _step(int i) => CurvedAnimation(parent: _intro, curve: Interval(0.15 + i * 0.15, (0.55 + i * 0.15).clamp(0, 1), curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    final items = [
      if (widget.sms)
        const _PermissionInfo(
          icon: Icons.sms_rounded,
          color: AppColors.blue,
          title: 'SMS',
          tag: 'Required',
          body: 'Reads bank and card transaction SMS to track spending automatically.',
          points: ['Only bank, card and payment alerts', 'Personal messages are ignored'],
        ),
      if (widget.notifications)
        const _PermissionInfo(
          icon: Icons.notifications_active_rounded,
          color: Color(0xFFE09A1F),
          title: 'Notifications',
          tag: 'Recommended',
          body: 'Reminders and alerts, with sound.',
          points: ['EMI and card bill due reminders', 'New transaction and overdue alerts'],
        ),
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      decoration: BoxDecoration(color: context.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Header(orbit: _orbit, sms: widget.sms, notifications: widget.notifications),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < items.length; i++)
                  FadeTransition(
                    opacity: _step(i),
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(_step(i)),
                      child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _PermissionCard(info: items[i])),
                    ),
                  ),
                FadeTransition(opacity: _step(items.length), child: const _PrivacyStrip()),
                const SizedBox(height: 18),
                _GradientButton(label: 'Allow access', onTap: () => Navigator.pop(context, true)),
                const SizedBox(height: 4),
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
                Text('You can change this anytime in Settings.',
                    textAlign: TextAlign.center, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
                const SizedBox(height: 6),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PermissionInfo {
  const _PermissionInfo({required this.icon, required this.color, required this.title, required this.tag, required this.body, required this.points});
  final IconData icon;
  final Color color;
  final String title;
  final String tag;
  final String body;
  final List<String> points;
}

/// Gradient header: shield in the middle with SMS / bell badges orbiting it.
class _Header extends StatelessWidget {
  const _Header({required this.orbit, required this.sms, required this.notifications});
  final Animation<double> orbit;
  final bool sms;
  final bool notifications;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          SizedBox(
            height: 132,
            child: AnimatedBuilder(
              animation: orbit,
              builder: (_, __) {
                final a = orbit.value * 2 * math.pi;
                Offset at(double phase) => Offset(70 * math.cos(a + phase), 34 * math.sin(a + phase));
                return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                  // Orbit ring.
                  Container(
                    width: 150,
                    height: 76,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(80), border: Border.all(color: Colors.white24)),
                  ),
                  if (sms) Transform.translate(offset: at(0), child: const _Badge(icon: Icons.sms_rounded, color: AppColors.blue)),
                  if (notifications) Transform.translate(offset: at(math.pi), child: const _Badge(icon: Icons.notifications_active_rounded, color: Color(0xFFE09A1F))),
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppColors.navy, size: 36),
                  ),
                ]);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sms && notifications ? 'Two quick permissions' : 'One quick permission',
            style: context.text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('So Smart Spend can track your money automatically',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: color, size: 20),
      );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.info});
  final _PermissionInfo info;

  @override
  Widget build(BuildContext context) {
    final c = info.color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: context.isDark ? 0.10 : 0.05), context.cardColor),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Icon(info.icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(info.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                child: Text(info.tag, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(info.body, style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4)),
            const SizedBox(height: 8),
            for (final p in info.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: c),
                  const SizedBox(width: 6),
                  Expanded(child: Text(p, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.income.withValues(alpha: context.isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.income),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Messages are read on your phone. Message text is never uploaded or shared.',
                style: context.text.labelMedium?.copyWith(height: 1.35, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.navy, AppColors.blue]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 54,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}
