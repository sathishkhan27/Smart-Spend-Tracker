import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../data/notification_repository.dart';
import '../domain/notification_kind.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationFilter _filter = NotificationFilter.all;

  bool _matches(AppNotification n) => switch (_filter) {
        NotificationFilter.all => true,
        NotificationFilter.unread => !n.read,
        final f => n.kind.filter == f,
      };

  /// Today / Yesterday / This week / Earlier.
  static String _section(DateTime d, DateTime now) {
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  void _open(AppNotification n) {
    final repo = ref.read(notificationRepositoryProvider);
    if (!n.read) repo.markRead(n.id);
    if (n.route != null && n.route!.isNotEmpty) openAppRoute(GoRouter.of(context), n.route!);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final repo = ref.read(notificationRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Notifications'),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(20)),
              child: Text('$unread new', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        actions: [
          if (unread > 0)
            IconButton(
              tooltip: 'Mark all as read',
              icon: const Icon(Icons.done_all_rounded),
              onPressed: () => repo.markAllRead(ref.read(authStateProvider).value!.uid),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(e),
        data: (all) {
          final list = all.where(_matches).toList();
          final now = DateTime.now();
          final rows = <Object>[]; // String = section header, AppNotification = item
          String? current;
          for (final n in list) {
            final s = _section(n.createdAt, now);
            if (s != current) rows.add(current = s);
            rows.add(n);
          }

          return Column(children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                children: [
                  for (final f in NotificationFilter.values)
                    _FilterPill(
                      label: f.label,
                      count: f == NotificationFilter.unread ? unread : null,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: _filter == NotificationFilter.all ? "You're all caught up" : 'Nothing here',
                        message: _filter == NotificationFilter.all
                            ? 'Reminders, new transactions and alerts will show up here.'
                            : 'No ${_filter.label.toLowerCase()} notifications right now.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        if (row is String) {
                          return Padding(
                            padding: EdgeInsets.fromLTRB(4, i == 0 ? 6 : 18, 4, 8),
                            child: Text(row.toUpperCase(),
                                style: context.text.labelSmall?.copyWith(color: context.secondaryText, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                          );
                        }
                        final n = row as AppNotification;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SwipeToAct(
                            key: ValueKey(n.id),
                            read: n.read,
                            onMarkRead: () => repo.markRead(n.id),
                            onDelete: () {
                              repo.delete(n.id);
                              showSnack(context, 'Notification removed');
                            },
                            child: _NotificationTile(n: n, now: now, onTap: () => _open(n)),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.now, required this.onTap});
  final AppNotification n;
  final DateTime now;
  final VoidCallback onTap;

  static String _ago(DateTime d, DateTime now) {
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && now.day == d.day) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${Fmt.relativeDay(d, now)} • ${Fmt.time(d)}';
    return Fmt.date(d);
  }

  @override
  Widget build(BuildContext context) {
    final k = n.kind;
    final unread = !n.read;
    final tint = Color.alphaBlend(k.color.withValues(alpha: context.isDark ? 0.10 : 0.045), context.cardColor);
    return Material(
      color: unread ? tint : context.cardColor,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: unread ? k.color.withValues(alpha: 0.35) : (context.isDark ? Colors.white10 : AppColors.divider)),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Unread accent bar.
              AnimatedContainer(duration: const Duration(milliseconds: 250), width: unread ? 4 : 0, color: k.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _KindIcon(kind: k),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: k.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                            child: Text(k.label, style: TextStyle(color: k.color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                          ),
                          const Spacer(),
                          Text(_ago(n.createdAt, now), style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: k.color, shape: BoxShape.circle)),
                          ],
                        ]),
                        const SizedBox(height: 6),
                        Text(n.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w600, height: 1.3)),
                        if (n.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(color: context.secondaryText, height: 1.4)),
                        ],
                      ]),
                    ),
                    if (n.route != null && n.route!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Icon(Icons.chevron_right_rounded, size: 20, color: context.secondaryText),
                      ),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Circular icon with a soft ring in the kind's colour.
class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});
  final NotificationKind kind;

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kind.color.withValues(alpha: 0.25), width: 1.5)),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kind.color.withValues(alpha: 0.95), kind.color.withValues(alpha: 0.7)],
            ),
          ),
          child: Icon(kind.icon, size: 18, color: Colors.white),
        ),
      );
}

/// Swipe right = mark read, swipe left = delete.
class _SwipeToAct extends StatelessWidget {
  const _SwipeToAct({super.key, required this.child, required this.read, required this.onMarkRead, required this.onDelete});
  final Widget child;
  final bool read;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  Widget _bg(BuildContext context, {required bool left}) => Container(
        decoration: BoxDecoration(
          color: (left ? AppColors.blue : AppColors.expense).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(left ? Icons.mark_email_read_rounded : Icons.delete_outline_rounded, color: left ? AppColors.blue : AppColors.expense, size: 20),
          const SizedBox(width: 6),
          Text(left ? 'Mark read' : 'Delete',
              style: TextStyle(color: left ? AppColors.blue : AppColors.expense, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Dismissible(
        key: key!,
        direction: read ? DismissDirection.endToStart : DismissDirection.horizontal,
        background: _bg(context, left: true),
        secondaryBackground: _bg(context, left: false),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            onMarkRead();
            return false; // keep it in the list, just read
          }
          return true;
        },
        onDismissed: (_) => onDelete(),
        child: child,
      );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : (context.isDark ? Colors.white70 : AppColors.textPrimary);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? AppColors.navy : (context.isDark ? Colors.white10 : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.navy : (context.isDark ? Colors.white12 : AppColors.divider)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: selected ? Colors.white : AppColors.blue, borderRadius: BorderRadius.circular(10)),
                  child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: selected ? AppColors.navy : Colors.white)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
