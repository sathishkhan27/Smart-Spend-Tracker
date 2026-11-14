import 'package:intl/intl.dart';

abstract final class Fmt {
  static final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _inrPrecise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

  static String currencySymbol(String code) => switch (code) {
        'INR' => '₹',
        'USD' => r'$',
        'EUR' => '€',
        'GBP' => '£',
        'AED' => 'AED ',
        _ => '$code ',
      };

  static String money(double v, {String currency = 'INR', bool precise = false}) {
    if (currency == 'INR') return precise ? _inrPrecise.format(v) : _inr.format(v);
    return NumberFormat.currency(symbol: currencySymbol(currency), decimalDigits: precise ? 2 : 0).format(v);
  }

  static String compact(double v, {String currency = 'INR'}) {
    // Below 1,000 show whole rupees ("₹450", not "₹450.0").
    if (v.abs() < 1000) return money(v, currency: currency);
    if (currency == 'INR') return _compact.format(v);
    return NumberFormat.compactCurrency(symbol: currencySymbol(currency)).format(v);
  }

  static String signed(double v, {required bool inflow, String currency = 'INR'}) =>
      '${inflow ? '+' : '−'}${money(v.abs(), currency: currency, precise: true)}';

  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);
  static String shortDate(DateTime d) => DateFormat('d MMM').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);
  static String month(DateTime d) => DateFormat('MMMM yyyy').format(d);
  static String monthShort(DateTime d) => DateFormat('MMM').format(d);
  static String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);
  static String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String percent(double v) => '${v.toStringAsFixed(v >= 10 ? 0 : 1)}%';

  static String relativeDay(DateTime d, DateTime now) {
    final a = DateTime(d.year, d.month, d.day);
    final b = DateTime(now.year, now.month, now.day);
    final diff = a.difference(b).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff < 7) return 'In $diff days';
    return date(d);
  }
}
