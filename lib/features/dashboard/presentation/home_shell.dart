import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../upcoming/domain/due_status.dart';
import 'dashboard_providers.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Insights'),
    (Icons.event_note_outlined, Icons.event_note_rounded, 'Upcoming'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBody: true,
        body: shell,
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _FloatingNavBar(
            index: shell.currentIndex,
            onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          ),
        ),
      );
}

class _FloatingNavBar extends ConsumerWidget {
  const _FloatingNavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _upcomingTab = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(dueAlertsProvider);
    final critical = alerts.any((a) => a.status.level.isCritical);
    return Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: context.isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: AppColors.navy.withValues(alpha: context.isDark ? 0.4 : 0.12), blurRadius: 30, offset: const Offset(0, 10)),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < HomeShell._items.length; i++)
              Expanded(
                flex: i == index ? 2 : 1,
                child: _NavItem(
                  icon: HomeShell._items[i].$1,
                  activeIcon: HomeShell._items[i].$2,
                  label: HomeShell._items[i].$3,
                  selected: i == index,
                  badge: i == _upcomingTab && alerts.isNotEmpty ? (critical ? DueLevel.overdue : DueLevel.twoDays).color : null,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.onTap, this.badge});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Dot colour when this tab has pending alerts.
  final Color? badge;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 0),
              decoration: BoxDecoration(
                gradient: selected ? const LinearGradient(colors: [AppColors.navy, AppColors.blue]) : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    isLabelVisible: badge != null,
                    smallSize: 9,
                    backgroundColor: badge,
                    child: Icon(selected ? activeIcon : icon, size: 22, color: selected ? Colors.white : context.secondaryText),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
