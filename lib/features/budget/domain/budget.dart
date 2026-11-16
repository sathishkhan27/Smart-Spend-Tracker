import '../../../core/utils/formatters.dart';

enum BudgetLevel { onTrack, warning, over }

/// How this month's spending compares with the monthly budget.
class BudgetStatus {
  const BudgetStatus({required this.budget, required this.spent});

  /// Alert thresholds, in percent: "almost used up" and "crossed". Stored per
  /// month once sent.
  static const warnThreshold = 80;
  static const overThreshold = 100;

  final double budget;
  final double spent;

  double get fraction => budget <= 0 ? 0 : spent / budget;

  /// Whole percent used; the tiny epsilon keeps 115.0 from showing as 114
  /// after floating-point division.
  int get percent => budget <= 0 ? 0 : (spent * 100 / budget + 1e-9).floor();
  double get remaining => budget - spent;
  double get overBy => spent - budget;

  BudgetLevel get level => budget <= 0 || percent < warnThreshold
      ? BudgetLevel.onTrack
      : percent >= overThreshold
          ? BudgetLevel.over
          : BudgetLevel.warning;

  /// The threshold to alert for now, or null when nothing new has been
  /// reached this month. [alreadyAlerted] is the highest threshold already
  /// sent this month (0 = none), so each alert fires once per month.
  int? alertDue(int alreadyAlerted) {
    final t = switch (level) {
      BudgetLevel.over => overThreshold,
      BudgetLevel.warning => warnThreshold,
      BudgetLevel.onTrack => null,
    };
    return t == null || t <= alreadyAlerted ? null : t;
  }

  /// Notification wording for the current level.
  ({String title, String body}) message({required String currency, required String monthLabel}) {
    String m(double v) => Fmt.money(v, currency: currency);
    return switch (level) {
      BudgetLevel.over => (
          title: 'Monthly budget crossed',
          body: 'You have spent ${m(spent)} of your ${m(budget)} budget for $monthLabel — ${m(overBy)} over.',
        ),
      _ => (
          title: '$percent% of your monthly budget used',
          body: 'You have spent ${m(spent)} of ${m(budget)} for $monthLabel. ${m(remaining)} left.',
        ),
    };
  }
}

