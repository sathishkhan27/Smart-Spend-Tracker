import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// How urgent an upcoming payment is, relative to today (workspace timezone).
enum DueLevel {
  overdue,
  today,
  tomorrow,
  twoDays,
  later;

  bool get isAlert => this != later;
  bool get isCritical => this == overdue || this == today;

  Color get color => switch (this) {
        overdue => AppColors.expense,
        today => const Color(0xFFE5602E),
        tomorrow || twoDays => AppColors.warning,
        later => AppColors.blue,
      };

  IconData get icon => switch (this) {
        overdue => Icons.error_rounded,
        today => Icons.notification_important_rounded,
        tomorrow || twoDays => Icons.schedule_rounded,
        later => Icons.event_rounded,
      };
}

class DueStatus {
  const DueStatus(this.level, this.days);

  /// Days until due (negative = overdue).
  final int days;
  final DueLevel level;

  /// Unpaid dues stay "overdue" for this many days before rolling forward.
  static const overdueGraceDays = 7;

  factory DueStatus.of(DateTime due, DateTime now) {
    final days = DateTime(due.year, due.month, due.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final level = days < 0
        ? DueLevel.overdue
        : days == 0
            ? DueLevel.today
            : days == 1
                ? DueLevel.tomorrow
                : days == 2
                    ? DueLevel.twoDays
                    : DueLevel.later;
    return DueStatus(level, days);
  }

  String get label => switch (level) {
        DueLevel.overdue => 'Overdue ${-days}d',
        DueLevel.today => 'Due today',
        DueLevel.tomorrow => 'Due tomorrow',
        DueLevel.twoDays => 'In 2 days',
        DueLevel.later => 'In $days days',
      };
}
