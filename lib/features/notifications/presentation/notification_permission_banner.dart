import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// Home banner shown while SMS access and/or notifications are turned off.
/// "Turn on" asks again if the system still allows it, otherwise opens the
/// app's settings page. "Not now" hides it for 7 days.
class NotificationPermissionBanner extends ConsumerStatefulWidget {
  const NotificationPermissionBanner({super.key});

  @override
  ConsumerState<NotificationPermissionBanner> createState() => _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState extends ConsumerState<NotificationPermissionBanner> {
  static const _snoozeKey = 'notif_banner_snoozed_until';
  static const _snooze = Duration(days: 7);

  bool _snoozed = true; // until prefs load, to avoid a flash
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final until = DateTime.fromMillisecondsSinceEpoch(p.getInt(_snoozeKey) ?? 0);
      if (mounted) setState(() => _snoozed = DateTime.now().isBefore(until));
    }).catchError((Object _) {
      if (mounted) setState(() => _snoozed = false);
    });
  }

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    final service = ref.read(notificationServiceProvider);
    final sms = ref.read(smsSourceProvider);
    var needSettings = false;

    if (sms.isSupported && !await sms.hasPermission()) {
      final status = await sms.requestPermission();
      if (status.isPermanentlyDenied) needSettings = true;
    }
    if (!await service.areEnabled() && !await service.ensurePermission()) needSettings = true;
    // Denied for good (the system no longer shows its prompt): open Settings.
    if (needSettings) await openAppSettings();

    ref
      ..invalidate(notificationsEnabledProvider)
      ..invalidate(smsPermissionProvider);
    final allOn = (!sms.isSupported || await sms.hasPermission()) && await service.areEnabled();
    if (!mounted) return;
    setState(() => _busy = false);
    if (allOn) showSnack(context, 'All set. Smart Spend can track and remind you automatically.');
  }

  Future<void> _notNow() async {
    setState(() => _snoozed = true);
    try {
      (await SharedPreferences.getInstance()).setInt(_snoozeKey, DateTime.now().add(_snooze).millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final notifOn = ref.watch(notificationsEnabledProvider).value ?? true;
    final smsOn = ref.watch(smsPermissionProvider).value ?? true;
    if ((notifOn && smsOn) || _snoozed) return const SizedBox.shrink();
    final (title, message) = switch ((smsOn, notifOn)) {
      (false, false) => ('SMS access and notifications are off', "Bank SMS won't be added automatically, and you won't get reminders or alerts."),
      (false, true) => ('SMS access is off', "New bank and card SMS won't be added to your transactions automatically."),
      _ => ('Notifications are off', "You won't get EMI and bill reminders, overdue alerts or new transaction alerts."),
    };
    const c = AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.4)),
          boxShadow: context.isDark ? null : [BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // Accent strip with the icon and message.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.withValues(alpha: context.isDark ? 0.22 : 0.14), c.withValues(alpha: 0.02)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Icon(smsOn ? Icons.notifications_off_rounded : Icons.sms_failed_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(message, style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4)),
                ]),
              ),
            ]),
          ),
          // Status of each permission at a glance.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Expanded(child: _StatusPill(icon: Icons.sms_rounded, label: 'SMS', on: smsOn)),
              const SizedBox(width: 8),
              Expanded(child: _StatusPill(icon: Icons.notifications_rounded, label: 'Notifications', on: notifOn)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 14, 10),
            child: Row(children: [
              TextButton(onPressed: _busy ? null : _notNow, child: const Text('Not now')),
              const Spacer(),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.navy, AppColors.blue]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy ? null : _turnOn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                        const SizedBox(width: 6),
                        const Text('Turn on', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "SMS ✓ On" / "Notifications ✗ Off" chip.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, required this.on});
  final IconData icon;
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = on ? AppColors.income : AppColors.expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: c.withValues(alpha: context.isDark ? 0.16 : 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 16, color: context.secondaryText),
        const SizedBox(width: 6),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
        Icon(on ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 15, color: c),
        const SizedBox(width: 3),
        Text(on ? 'On' : 'Off', style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
