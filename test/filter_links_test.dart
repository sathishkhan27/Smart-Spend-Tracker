import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/router/app_router.dart';
import 'package:smart_spend_tracker/core/utils/date_range.dart';

void main() {
  test('period survives the URL round trip', () {
    for (final p in [DateRangePeriod.month(2026, 11), DateRangePeriod.year(2025), DateRangePeriod.custom(DateTime(2026, 10, 3), DateTime(2026, 11, 9))]) {
      expect(DateRangePeriod.fromQuery(p.toQuery()), p);
    }
    expect(DateRangePeriod.fromQuery(const {}), isNull);
  });

  test('category / payment-mode links carry their filters', () {
    final uri = Uri.parse(Routes.transactionsFor(categoryId: 'food_dining', paymentMode: 'upi', outflowOnly: true, period: DateRangePeriod.month(2026, 11)));
    expect(uri.path, Routes.transactions);
    expect(uri.queryParameters['category'], 'food_dining');
    expect(uri.queryParameters['mode'], 'upi');
    expect(uri.queryParameters['dir'], 'outflow');
    expect(DateRangePeriod.fromQuery(uri.queryParameters), DateRangePeriod.month(2026, 11));
    expect(uri.queryParameters['nav'], isNotEmpty);
  });

  test('inflow / outflow links set the direction', () {
    expect(Uri.parse(Routes.transactionsFor(inflowOnly: true)).queryParameters['dir'], 'inflow');
    expect(Uri.parse(Routes.transactionsFor(outflowOnly: true)).queryParameters['dir'], 'outflow');
    expect(Uri.parse(Routes.transactionsFor()).queryParameters.containsKey('dir'), isFalse);
  });
}
