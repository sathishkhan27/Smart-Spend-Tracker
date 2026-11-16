import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Android notification channels. Users can tune each one separately in
/// system settings (e.g. silence sync updates but keep payment reminders).
///
/// Android fixes a channel's sound when it is first created, so a sound change
/// needs new channel ids (v2 = custom "ding"); [legacyIds] are removed.
enum NotificationChannel {
  transactions('ss_transactions_v2', 'Transactions', 'New debits and credits detected from SMS or email', high: true),
  reminders('ss_reminders_v2', 'Payment reminders', 'Bills, EMIs and subscriptions due in 2 days, tomorrow or today', high: true),
  alerts('ss_alerts_v2', 'Important alerts', 'Overdue payments, unusual spending and budget alerts', high: true),
  workspace('ss_workspace_v2', 'Workspace activity', 'Transactions added by members of your shared workspace'),
  sync('ss_sync', 'Sync status', 'Background sync results', silent: true);

  /// Raw resource (android/app/src/main/res/raw/notification_ding.mp3).
  static const sound = 'notification_ding';

  /// Same sound for iOS (ios/Runner/notification_ding.caf; iOS can't use MP3).
  static const iosSound = 'notification_ding.caf';

  /// Channels from earlier builds, deleted on startup.
  static const legacyIds = ['smart_spend_default', 'ss_transactions', 'ss_reminders', 'ss_alerts', 'ss_workspace'];

  const NotificationChannel(this.id, this.label, this.description, {this.high = false, this.silent = false});
  final String id;
  final String label;
  final String description;
  final bool high;
  final bool silent;
}

/// Notification categories shared by the in-app list, local notifications
/// and the server push payload (`type` field).
enum NotificationKind {
  transaction('transaction', 'Transaction', Icons.receipt_long_rounded, AppColors.blue, NotificationChannel.transactions),
  upcoming('upcoming', 'Reminder', Icons.event_rounded, Color(0xFFE09A1F), NotificationChannel.reminders),
  overdue('overdue', 'Overdue', Icons.error_rounded, AppColors.expense, NotificationChannel.alerts),
  unusual('unusual', 'Alert', Icons.trending_up_rounded, Color(0xFFEB6834), NotificationChannel.alerts),
  budget('budget', 'Budget', Icons.account_balance_wallet_rounded, AppColors.expense, NotificationChannel.alerts),
  uncategorized('uncategorized', 'Needs review', Icons.help_outline_rounded, Color(0xFF7B8495), NotificationChannel.transactions),
  workspace('workspace', 'Workspace', Icons.groups_rounded, Color(0xFF6250D6), NotificationChannel.workspace),
  sync('sync', 'Sync', Icons.cloud_done_rounded, AppColors.income, NotificationChannel.sync),
  syncFailed('sync_failed', 'Sync issue', Icons.cloud_off_rounded, AppColors.expense, NotificationChannel.sync);

  const NotificationKind(this.type, this.label, this.icon, this.color, this.channel);
  final String type;
  final String label;
  final IconData icon;
  final Color color;
  final NotificationChannel channel;

  /// Filter bucket on the notifications screen.
  NotificationFilter get filter => switch (this) {
        upcoming || overdue => NotificationFilter.reminders,
        transaction || uncategorized || workspace => NotificationFilter.transactions,
        unusual || budget || syncFailed => NotificationFilter.alerts,
        sync => NotificationFilter.all,
      };

  static NotificationKind fromType(String? type) => switch (type) {
        'upcoming' => upcoming,
        'overdue' => overdue,
        'unusual' => unusual,
        'budget' => budget,
        'uncategorized' => uncategorized,
        'workspace' => workspace,
        'sync' => sync,
        'sync_failed' => syncFailed,
        _ => transaction,
      };
}

enum NotificationFilter {
  all('All'),
  unread('Unread'),
  reminders('Reminders'),
  transactions('Transactions'),
  alerts('Alerts');

  const NotificationFilter(this.label);
  final String label;
}
