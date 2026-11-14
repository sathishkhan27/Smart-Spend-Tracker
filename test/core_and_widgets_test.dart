import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/theme/app_theme.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/core/utils/date_range.dart';
import 'package:smart_spend_tracker/features/dashboard/presentation/widgets/period_selector.dart';
import 'package:smart_spend_tracker/features/sync/domain/sync_progress.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_filter.dart';

import 'engines/engines_test.dart' show tx;

void main() {
  setUpAll(() => AppClock.init());

  group('DateRangePeriod', () {
    test('month boundaries and stepping', () {
      final p = DateRangePeriod.month(2026, 12);
      expect(p.end, DateTime(2027, 1));
      expect(p.next().start, DateTime(2027, 1));
      expect(p.previous().start, DateTime(2026, 11));
      expect(DateRangePeriod.year(2026).monthKeys, hasLength(12));
    });

    test('custom range is inclusive of last day', () {
      final p = DateRangePeriod.custom(DateTime(2026, 1, 5), DateTime(2026, 1, 10));
      expect(p.contains(DateTime(2026, 1, 10, 23, 59)), isTrue);
      expect(p.contains(DateTime(2026, 1, 11)), isFalse);
    });
  });

  test('Asia/Kolkata wall-clock round trip', () {
    final wall = DateTime(2026, 11, 5, 23, 30);
    final utc = AppClock.toUtc(wall);
    expect(utc, DateTime.utc(2026, 11, 5, 18, 0));
    expect(AppClock.toLocal(utc), wall);
  });

  group('TransactionFilter', () {
    final f = TransactionFilter(period: DateRangePeriod.month(2026, 11));
    test('search picks the longest token for the server and matches client-side', () {
      final s = f.copyWith(search: 'to swiggy');
      expect(s.searchToken, 'swiggy');
      expect(s.serverSideField, FilterField.search);
      expect(s.matches(tx(id: '1', amount: 10, cp: 'Swiggy Bangalore')), isTrue);
      expect(s.matches(tx(id: '2', amount: 10, cp: 'Zomato')), isFalse);
    });
    test('direction filter', () {
      final d = f.copyWith(direction: TxDirection.inflow);
      expect(d.matches(tx(id: '1', amount: 1)), isFalse);
      expect(d.activeCount, 1);
      expect(d.cleared().activeCount, 0);
    });
  });

  group('SyncProgress', () {
    test('never reports a fake percentage when work is unknown', () {
      const p = SyncProgress(stage: SyncStage.scanningSms, sources: {'sms': SourceState(SourceSyncStatus.running)});
      expect(p.fraction, isNull);
    });
    test('real fraction from scanned counts', () {
      const p = SyncProgress(stage: SyncStage.extracting, smsTotal: 100, smsScanned: 50, emailsTotal: 0);
      expect(p.fraction, closeTo(0.425, 0.001));
    });
  });

  testWidgets('PeriodSelector steps to previous month', (tester) async {
    var period = DateRangePeriod.month(2026, 6);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => PeriodSelector(period: period, onChanged: (p) => set(() => period = p)),
        ),
      ),
    ));
    expect(find.text('June 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous'));
    await tester.pump();
    expect(find.text('May 2026'), findsOneWidget);
  });
}
