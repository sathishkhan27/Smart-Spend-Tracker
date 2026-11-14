import 'formatters.dart';

enum PeriodType { monthly, yearly, custom }

/// An inclusive [start] → exclusive [end] wall-clock range.
class DateRangePeriod {
  const DateRangePeriod._(this.type, this.start, this.end);

  factory DateRangePeriod.month(int year, int month) =>
      DateRangePeriod._(PeriodType.monthly, DateTime(year, month), DateTime(year, month + 1));

  factory DateRangePeriod.year(int year) =>
      DateRangePeriod._(PeriodType.yearly, DateTime(year), DateTime(year + 1));

  factory DateRangePeriod.custom(DateTime from, DateTime to) => DateRangePeriod._(
        PeriodType.custom,
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day + 1),
      );

  final PeriodType type;
  final DateTime start;
  final DateTime end;

  DateTime get lastDay => end.subtract(const Duration(days: 1));

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  DateRangePeriod previous() => switch (type) {
        PeriodType.monthly => DateRangePeriod.month(start.year, start.month - 1),
        PeriodType.yearly => DateRangePeriod.year(start.year - 1),
        PeriodType.custom => DateRangePeriod.custom(
            start.subtract(end.difference(start)), start.subtract(const Duration(days: 1))),
      };

  DateRangePeriod next() => switch (type) {
        PeriodType.monthly => DateRangePeriod.month(start.year, start.month + 1),
        PeriodType.yearly => DateRangePeriod.year(start.year + 1),
        PeriodType.custom => DateRangePeriod.custom(end, end.add(end.difference(start)).subtract(const Duration(days: 1))),
      };

  /// Month keys (yyyy-MM) covered by this range — used for aggregate lookups.
  List<String> get monthKeys {
    final keys = <String>[];
    var cursor = DateTime(start.year, start.month);
    while (cursor.isBefore(end)) {
      keys.add(Fmt.monthKey(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return keys;
  }

  /// URL query form, e.g. {period: monthly, from: 2026-11-01, to: 2026-11-30}.
  Map<String, String> toQuery() => {'period': type.name, 'from': Fmt.dayKey(start), 'to': Fmt.dayKey(lastDay)};

  /// Inverse of [toQuery]; null when the query has no valid period.
  static DateRangePeriod? fromQuery(Map<String, String> q) {
    final from = DateTime.tryParse(q['from'] ?? '');
    final to = DateTime.tryParse(q['to'] ?? '');
    if (from == null) return null;
    return switch (q['period']) {
      'monthly' => DateRangePeriod.month(from.year, from.month),
      'yearly' => DateRangePeriod.year(from.year),
      'custom' when to != null && !to.isBefore(from) => DateRangePeriod.custom(from, to),
      _ => null,
    };
  }

  String get label => switch (type) {
        PeriodType.monthly => Fmt.month(start),
        PeriodType.yearly => '${start.year}',
        PeriodType.custom => '${Fmt.shortDate(start)} – ${Fmt.date(lastDay)}',
      };

  @override
  bool operator ==(Object other) =>
      other is DateRangePeriod && other.type == type && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(type, start, end);
}
