import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Bell icon with the unread count. Updates live as notifications arrive
/// (in-app list stream) and pops briefly when the count goes up.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    final color = context.isDark ? Colors.white : AppColors.navy;
    return Semantics(
      label: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      child: Stack(clipBehavior: Clip.none, children: [
        Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: size, color: color),
        if (unread > 0)
          Positioned(
            right: -7,
            top: -6,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(unread), // replays the pop on every change
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.expense,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: context.cardColor, width: 2),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, height: 1),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
