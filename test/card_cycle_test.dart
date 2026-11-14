import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/cards/data/credit_card_repository.dart';
import 'package:smart_spend_tracker/features/cards/domain/card_cycle.dart';
import 'package:smart_spend_tracker/features/cards/domain/credit_card.dart';
import 'package:smart_spend_tracker/features/transactions/domain/category.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

FinancialTransaction tx(String id, double amount, DateTime day,
        {TxDirection dir = TxDirection.outflow, String? acct, String cat = 'shopping', String? cp, TxType type = TxType.debit, PaymentMode mode = PaymentMode.creditCard}) =>
    FinancialTransaction(
      transactionId: id,
      workspaceId: 'w',
      ownerUserId: 'u',
      amount: amount,
      currency: 'INR',
      direction: dir,
      transactionType: type,
      categoryId: cat,
      categoryName: Categories.byId(cat).name,
      counterparty: cp,
      transactionDate: AppClock.toUtc(DateTime(day.year, day.month, day.day, 12)),
      source: TxSource.sms,
      sources: const [TxSource.sms],
      status: TxStatus.success,
      maskedAccountNumber: acct,
      paymentMode: mode,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  setUpAll(AppClock.init);
  final now = DateTime(2026, 11, 14, 10);
  const card = CreditCard(id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007', creditLimit: 100000, statementDay: 15, dueDay: 5);

  final spends = [
    tx('o1', 10000, DateTime(2026, 10, 2), acct: 'XX4007'), // previous cycle (Sep 16 – Oct 15)
    tx('o2', 8345, DateTime(2026, 10, 10), acct: 'XX4007'),
    tx('n1', 1200, DateTime(2026, 10, 20), acct: 'XX4007'), // current cycle (Oct 16 – Nov 15)
    tx('n2', 800, DateTime(2026, 11, 8), acct: 'XX4007'),
    tx('r1', 200, DateTime(2026, 11, 9), acct: 'XX4007', dir: TxDirection.inflow), // refund
  ];
  bool onCard(FinancialTransaction t) => CreditCardRepository.belongsToCard(t, card);

  test('cycle dates follow the statement day', () {
    final c = CardCycle.compute(card: card, cardTransactions: spends, payments: const [], now: now);
    expect(c.lastStatementDate, DateTime(2026, 10, 15));
    expect(c.cycleStart, DateTime(2026, 10, 16));
    expect(c.nextStatement, DateTime(2026, 11, 15));
    expect(c.cycleSpent, 1800); // 1200 + 800 − 200 refund
  });

  test('estimated statement with no payment seen is "not confirmed", not overdue', () {
    final c = CardCycle.compute(card: card, cardTransactions: spends, payments: const [], now: now);
    expect((c.statementTotal, c.statementEstimated), (18345.0, true));
    expect(c.statementDueDate, DateTime(2026, 11, 5));
    expect(c.state, StatementState.unconfirmed);
    expect(c.state.owing, isFalse);
    expect(c.nextDueDate, DateTime(2026, 11, 5));
  });

  test('bill paid from the bank account → Paid, next due after the next statement', () {
    final all = [
      ...spends,
      tx('p1', 18345, DateTime(2026, 11, 3), acct: 'XX1234', cat: 'credit_card_payment', cp: 'ICICI Credit Card', mode: PaymentMode.upi),
    ];
    final payments = CardCycle.paymentsFrom(card, all, onCard: onCard);
    expect(payments.single.amount, 18345);
    final c = CardCycle.compute(card: card, cardTransactions: spends, payments: payments, now: now);
    expect(c.state, StatementState.paid);
    expect(c.remaining, 0);
    expect(c.nextDueDate, DateTime(2026, 12, 5));
  });

  test('statement SMS amount wins; minimum paid → partially paid', () {
    final withSms = CreditCard(
      id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007', statementDay: 15, dueDay: 5,
      totalDue: 20000, minDue: 1000, statementAt: AppClock.toUtc(DateTime(2026, 10, 15, 9)), dueDate: DateTime(2026, 11, 5),
    );
    final c = CardCycle.compute(card: withSms, cardTransactions: spends, payments: [CardPayment(5000, DateTime(2026, 11, 2))], now: now);
    expect((c.statementTotal, c.statementEstimated, c.state, c.remaining), (20000.0, false, StatementState.partial, 15000.0));
  });

  test('same payment from issuer SMS and bank debit is counted once', () {
    final merged = CardCycle.dedupe([CardPayment(18345, DateTime(2026, 11, 3)), CardPayment(18345, DateTime(2026, 11, 4)), CardPayment(500, DateTime(2026, 11, 10))]);
    expect(merged.map((p) => p.amount), [18345, 500]);
  });

  test('billing cycle learned when unknown: uses statement SMS day', () {
    final noCycle = CreditCard(id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007', totalDue: 5000, statementAt: AppClock.toUtc(DateTime(2026, 10, 15, 9)), dueDate: DateTime(2026, 11, 5));
    final c = CardCycle.compute(card: noCycle, cardTransactions: spends, payments: const [], now: now);
    expect(c.statementDay, 15);
    expect(c.dueDay, 5);
  });

  test('"Paid to CRED" for the statement amount settles it', () {
    final all = [...spends, tx('cred', 18345, DateTime(2026, 11, 4), acct: 'XX1234', cp: 'CRED', cat: 'credit_card_payment', mode: PaymentMode.upi)];
    expect(CardCycle.paymentsFrom(card, all, onCard: onCard), isEmpty); // doesn't name the card
    final unattributed = CardCycle.unattributedBillPayments(all, onAnyCard: onCard);
    final before = CardCycle.compute(card: card, cardTransactions: spends, payments: const [], now: now);
    final match = CardCycle.matchUnattributed(before, unattributed);
    expect(match?.amount, 18345);
    final after = CardCycle.compute(card: card, cardTransactions: spends, payments: [match!], now: now);
    expect(after.state, StatementState.paid);
  });

  test('manual cycle that disagrees with the statement SMS is flagged (8003: saved 27th, SMS on 23rd)', () {
    final wrong = CreditCard(
      id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '8003', statementDay: 27, dueDay: 3,
      cycleSetManually: true, statementFromSms: true, statementAt: DateTime.utc(2026, 10, 23, 12, 4),
    );
    expect(wrong.cycleMismatchDay, 23);
    // Set by the user and matching the SMS → no prompt.
    final ok = CreditCard(id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '8003', statementDay: 23, dueDay: 3, cycleSetManually: true, statementFromSms: true, statementAt: DateTime.utc(2026, 10, 23, 12));
    expect(ok.cycleMismatchDay, isNull);
    // Learned from SMS (not manual) → never prompts.
    final auto = CreditCard(id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '8003', statementDay: 27, statementFromSms: true, statementAt: DateTime.utc(2026, 10, 23, 12));
    expect(auto.cycleMismatchDay, isNull);
  });
}
