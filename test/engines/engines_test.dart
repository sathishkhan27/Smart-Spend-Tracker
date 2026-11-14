import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/dashboard/domain/period_aggregate.dart';
import 'package:smart_spend_tracker/features/transactions/domain/category.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/categorization_engine.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/duplicate_detector.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/raw_message.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_processor.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/recurring_detector.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/recurring_expense.dart';

FinancialTransaction tx({
  required String id,
  required double amount,
  TxDirection dir = TxDirection.outflow,
  String cat = 'others',
  TxStatus status = TxStatus.success,
  DateTime? date,
  String? cp,
  String currency = 'INR',
  bool internal = false,
}) =>
    FinancialTransaction(
      transactionId: id,
      workspaceId: 'w',
      ownerUserId: 'u',
      amount: amount,
      currency: currency,
      direction: dir,
      transactionType: dir == TxDirection.inflow ? TxType.credit : TxType.debit,
      categoryId: cat,
      categoryName: Categories.byId(cat).name,
      transactionDate: date ?? DateTime.utc(2026, 11, 2),
      source: TxSource.sms,
      sources: const [TxSource.sms],
      status: status,
      counterparty: cp,
      isInternalTransfer: internal,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  setUpAll(() => AppClock.init());

  group('CategorizationEngine', () {
    final engine = CategorizationEngine();
    CategorizationResult cat(String merchant, {TxDirection dir = TxDirection.outflow, TxType type = TxType.upiPayment}) =>
        engine.categorize(CategorizationInput(direction: dir, type: type, paymentMode: PaymentMode.upi, merchant: merchant, counterparty: merchant));

    test('keyword rules', () {
      expect(cat('Swiggy').category, Categories.food);
      expect(cat('BigBasket').category, Categories.groceries);
      expect(cat('Netflix').category, Categories.subscription);
      expect(cat('Indian Oil Petrol Pump').category, Categories.fuel);
      expect(cat('BESCOM').category, Categories.electricity);
    });

    test('type rules win for salary and ATM', () {
      expect(cat('ACME', dir: TxDirection.inflow, type: TxType.salaryCredit).category, Categories.salary);
      expect(cat('S1AW123', type: TxType.atmWithdrawal).category, Categories.atm);
    });

    test('person-to-person transfer', () {
      expect(cat('Ravi Kumar').category, Categories.personalTransfer);
    });

    test('unknown falls back to Others with review flag', () {
      final r = engine.categorize(const CategorizationInput(direction: TxDirection.outflow, type: TxType.debit, paymentMode: PaymentMode.other, merchant: 'XQZ'));
      expect(r.category, Categories.others);
      expect(r.needsReview, isTrue);
    });

    test('learned merchant mapping overrides rules', () {
      final e = CategorizationEngine()..learn('Swiggy', 'groceries', subcategory: 'Instamart');
      final r = e.categorize(const CategorizationInput(direction: TxDirection.outflow, type: TxType.upiPayment, paymentMode: PaymentMode.upi, merchant: 'SWIGGY'));
      expect(r.category, Categories.groceries);
      expect(r.subcategory, 'Instamart');
      expect(r.confidence, 1);
    });
  });

  group('DuplicateDetector', () {
    const d = DuplicateDetector();
    final base = DateTime.utc(2026, 11, 4, 9);

    test('same reference across SMS and email is a duplicate', () {
      final a = DedupeCandidate(transactionId: 'a', amount: 250, direction: TxDirection.outflow, dateUtc: base, referenceNumber: '430912345678', sources: const [TxSource.sms]);
      final b = DedupeCandidate(transactionId: 'b', amount: 250, direction: TxDirection.outflow, dateUtc: base.add(const Duration(hours: 3)), referenceNumber: '430912345678', sources: const [TxSource.email]);
      expect(d.check(b, [a], sourceKey: 'email:1').kind, DuplicateKind.sameEvent);
    });

    test('same amount, same account, close in time, different source → duplicate', () {
      final a = DedupeCandidate(transactionId: 'a', amount: 999, direction: TxDirection.outflow, dateUtc: base, maskedAccount: 'XX1234', sources: const [TxSource.sms]);
      final b = DedupeCandidate(transactionId: 'b', amount: 999, direction: TxDirection.outflow, dateUtc: base.add(const Duration(minutes: 20)), maskedAccount: 'XX1234', sources: const [TxSource.email]);
      expect(d.check(b, [a], sourceKey: 'email:2').isDuplicate, isTrue);
    });

    test('two genuine same-amount SMS payments are not merged', () {
      final a = DedupeCandidate(transactionId: 'a', amount: 20, direction: TxDirection.outflow, dateUtc: base, maskedAccount: 'XX1234', sources: const [TxSource.sms]);
      final b = DedupeCandidate(transactionId: 'b', amount: 20, direction: TxDirection.outflow, dateUtc: base.add(const Duration(hours: 1)), maskedAccount: 'XX1234', sources: const [TxSource.sms]);
      expect(d.check(b, [a], sourceKey: 'sms:9').isDuplicate, isFalse);
    });

    test('different references are never merged', () {
      final a = DedupeCandidate(transactionId: 'a', amount: 20, direction: TxDirection.outflow, dateUtc: base, referenceNumber: '111111111111');
      final b = DedupeCandidate(transactionId: 'b', amount: 20, direction: TxDirection.outflow, dateUtc: base, referenceNumber: '222222222222');
      expect(d.score(a, b), 0);
    });

    test('transaction ids are deterministic (idempotent writes)', () {
      String id() => DuplicateDetector.transactionIdFor(workspaceId: 'w', amount: 10, direction: TxDirection.outflow, referenceNumber: 'ABC12345', sourceKey: 'sms:1');
      expect(id(), id());
    });
  });

  group('TransactionProcessor', () {
    test('processes an SMS end-to-end', () {
      final p = TransactionProcessor();
      final out = p.process(
        RawMessage(id: '1', source: TxSource.sms, sender: 'VM-HDFCBK', body: 'Rs.250.00 debited from A/c **1234 on 04-11-26 to VPA swiggy@icici (UPI Ref No. 430912345678).', receivedAt: DateTime(2026, 11, 4, 13)),
        const ProcessingContext(workspaceId: 'w', userId: 'u'),
      );
      expect(out.status, TxStatus.success);
      expect(out.transaction!.categoryId, Categories.food.id);
      expect(out.transaction!.searchKeywords, contains('swi'));
      expect(out.sourceDetails!.sourceMessageIds, ['sms:1']);
    });
  });

  group('FinancialCalculator', () {
    test('applies the calculation rules', () {
      final agg = FinancialCalculator.aggregate([
        tx(id: '1', amount: 50000, dir: TxDirection.inflow, cat: 'salary'),
        tx(id: '2', amount: 1000, cat: 'food_dining'),
        tx(id: '2', amount: 1000, cat: 'food_dining'), // duplicate id
        tx(id: '3', amount: 3000, cat: 'shopping'),
        tx(id: '4', amount: 999, status: TxStatus.failed),
        tx(id: '5', amount: 700, status: TxStatus.pending),
        tx(id: '6', amount: 20000, internal: true),
        tx(id: '7', amount: 500, dir: TxDirection.inflow, cat: 'refund'),
        tx(id: '8', amount: 100, currency: 'USD'),
      ]);
      expect(agg.inflow, 50500);
      expect(agg.outflow, 4000);
      expect(agg.net, 46500);
      expect(agg.count, 4);
      expect(agg.refunds, 500);
      expect(agg.failed, 1);
      expect(agg.pending, 1);
      expect(agg.otherCurrencies['USD']!.outflow, 100);
      expect(agg.expenseCategories.first.category, Categories.shopping);
      expect(agg.expenseCategories.first.percent, 75);
    });
  });

  group('RecurringDetector', () {
    test('detects monthly rent', () {
      final txs = [
        for (var m = 6; m <= 10; m++) tx(id: 'r$m', amount: 18000, cat: 'rent', cp: 'Landlord Ramesh', date: DateTime.utc(2026, m, 3)),
      ];
      final s = const RecurringDetector().detect(txs);
      expect(s, hasLength(1));
      expect(s.first.frequency, RecurrenceFrequency.monthly);
      expect(s.first.nextDueDate, DateTime(2026, 11, 3));
      expect(s.first.confidence, greaterThan(0.8));
    });

    test('irregular payments are not recurring', () {
      final txs = [
        tx(id: 'a', amount: 120, cp: 'Cafe Coffee', date: DateTime.utc(2026, 1, 3)),
        tx(id: 'b', amount: 900, cp: 'Cafe Coffee', date: DateTime.utc(2026, 1, 9)),
        tx(id: 'c', amount: 40, cp: 'Cafe Coffee', date: DateTime.utc(2026, 4, 20)),
      ];
      expect(const RecurringDetector().detect(txs), isEmpty);
    });
  });
}
