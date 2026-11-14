// Real ICICI / SBI / Indian Bank message formats (numbers masked).
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/cards/domain/card_cycle.dart';
import 'package:smart_spend_tracker/features/cards/domain/card_sms_parser.dart';
import 'package:smart_spend_tracker/features/cards/domain/credit_card.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/categorization_engine.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/raw_message.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_parser.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_processor.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

FinancialTransaction processorTx(double amount, DateTime day) => TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine())
    .process(
      RawMessage(id: '$amount$day', source: TxSource.sms, sender: 'BP-ICICIT-S', body: 'INR $amount spent using ICICI Bank Card XX4007 on ${day.day.toString().padLeft(2, '0')}-Oct-26 on SHOP. Avl Limit: INR 50,000.00.', receivedAt: DateTime(day.year, day.month, day.day, 12)),
      const ProcessingContext(workspaceId: 'w', userId: 'u'),
    )
    .transaction!;

RawMessage sms(String body, {String sender = 'JD-ICICIT-S', DateTime? at}) =>
    RawMessage(id: '${body.hashCode}', source: TxSource.sms, sender: sender, body: body, receivedAt: at ?? DateTime(2026, 10, 14, 9));

void main() {
  setUpAll(AppClock.init);
  final p = CardSmsParser();

  test('statement: total, minimum ("minimum of Rs"), due date; marks the cycle', () {
    final s = p.parse(sms('ICICI Bank Credit Card XX8003 Statement is sent to sa*********27@gmail.com. Total of Rs 23,000.54 or minimum of Rs 9,570.00 is due by 03-NOV-26.'))!;
    expect((s.last4, s.isStatement, s.totalDue, s.minDue, s.dueDate), ('8003', true, 23000.54, 9570.0, DateTime(2026, 11, 3)));
  });

  test('"Pay Total Amount Due … by" is a reminder, not a new statement', () {
    final s = p.parse(sms('Pay Total Amount Due of Rs 23,000.54 or Minimum Amount Due of Rs 9,570.00 by 03-Nov-26 towards ICICI Bank Credit Card XX8003. Delay/Non-payment is reported to Credit Bureaus. Ignore if paid.',
        at: DateTime(2026, 10, 31, 9)))!;
    expect((s.isStatement, s.totalDue, s.minDue), (false, 23000.54, 9570.0));
  });

  test('payment received', () {
    final s = p.parse(sms('Dear Customer, payment of INR 17,752.26 towards your ICICI Bank Credit Card XX8003 has been received through Click to Pay on 01-SEP-26. Thank you.'))!;
    expect((s.last4, s.paymentAmount), ('8003', 17752.26));
  });

  test('refund is not a payment; revised total due is read', () {
    final s = p.parse(sms('UPI-XXXXXXXX8009-SRI JEEV refund of Rs 2,903.00 credited to ICICI Bank Credit Card XX4007 on 02-OCT-26. Revised total due Rs 0, minimum due Rs .00'))!;
    expect((s.paymentAmount, s.revisedTotalDue, s.revisedMinDue), (null, 0.0, 0.0));
    final r = p.parse(sms('Reversal of Rs 321.46 credited to ICICI Bank Credit Card XX8003 on 31-AUG-26. Revised total due Rs 17,002.20, minimum due Rs 5,579.94'))!;
    expect((r.paymentAmount, r.revisedTotalDue, r.revisedMinDue), (null, 17002.20, 5579.94));
  });

  test('SBI OTP to "ICICI Bank Credit card" is a payment hint', () {
    final h = p.parseHint(sms('XX8993 is OTP to approve transaction of Rs. 23000.54 from your A/c No. ending 3935 to ICICI Bank Credit card. Do not share with anyone. -SBI', sender: 'AD-SBIINB-T'))!;
    expect((h.issuer, h.amount), ('ICICI Bank', 23000.54));
  });

  test('Indian Bank debit card AMC message is not a credit card', () {
    expect(p.parse(sms('AMC charges for your Indian Bank Debit Card XX5663 due on 31-10-2026 for INR 383.5 will be debited from your account shortly.Keep sufficient funds in A/C', sender: 'BV-INDBNK-S')), isNull);
  });

  group('card spends', () {
    final processor = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine());
    test('UPI spend on the credit card is a credit-card spend', () {
      final t = processor
          .process(sms('ICICI Bank Credit Card XX4007 debited for INR 20.00 on 13-Nov-26 for UPI-XXXXXXXX4496-Juice. To dispute call XXXX1080/SMS BLOCK 4007 to XXXXXX6766', sender: 'BP-ICICIT-S'),
              const ProcessingContext(workspaceId: 'w', userId: 'u'))
          .transaction!;
      expect((t.paymentMode, t.maskedAccountNumber, t.amount, t.direction), (PaymentMode.creditCard, 'XX4007', 20.0, TxDirection.outflow));
    });
    test('"spent using ICICI Bank Card … Avl Limit" is a credit card with available limit', () {
      final body = 'INR 265.00 spent using ICICI Bank Card XX8003 on 07-Nov-26 on TATAPLAYLTD. Avl Limit: INR 91,994.08. If not you, call 1800 2662/SMS BLOCK 8003 to XXXXXX6766.';
      final t = processor.process(sms(body, sender: 'BP-ICICIT-S'), const ProcessingContext(workspaceId: 'w', userId: 'u')).transaction!;
      expect(t.paymentMode, PaymentMode.creditCard);
      expect(p.parse(sms(body))!.availableLimit, 91994.08);
    });
  });

  test('November bill paid via SBI (OTP hint of the statement amount) → Paid', () {
    final card = CreditCard(
      id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '8003',
      totalDue: 23000.54, minDue: 9570, statementAt: AppClock.toUtc(DateTime(2026, 10, 14, 9)), dueDate: DateTime(2026, 11, 3),
      statementDay: 14, dueDay: 3,
      paymentHints: [(amount: 23000.54, at: AppClock.toUtc(DateTime(2026, 11, 2, 20)))],
    );
    final now = DateTime(2026, 11, 14, 10);
    final before = CardCycle.compute(card: card, cardTransactions: const [], payments: const [], now: now);
    expect(before.state, StatementState.overdue);
    final hint = CardPayment(23000.54, DateTime(2026, 11, 2));
    final match = CardCycle.matchUnattributed(before, [hint]);
    final after = CardCycle.compute(card: card, cardTransactions: const [], payments: [match!], now: now);
    expect((after.state, after.remaining), (StatementState.paid, 0.0));
    expect(after.nextDueDate, DateTime(2026, 12, 3));
  });

  test('ICICI ••8003 real timeline: 23 Oct statement paid 31 Oct via SBI → Paid, next due 3 Dec', () {
    // State after the card reader replays the messages.
    final card = CreditCard(
      id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '8003',
      totalDue: 23000.54, minDue: 9570, statementAt: AppClock.toUtc(DateTime(2026, 10, 23, 17, 34)), dueDate: DateTime(2026, 11, 3),
      statementDay: 23, dueDay: 3,
      paymentHints: [(amount: 23000.54, at: AppClock.toUtc(DateTime(2026, 10, 31, 11, 21)))],
    );
    final now = DateTime(2026, 11, 14, 18);
    final c0 = CardCycle.compute(card: card, cardTransactions: const [], payments: const [], now: now);
    expect((c0.lastStatementDate, c0.statementTotal, c0.statementEstimated), (DateTime(2026, 10, 23), 23000.54, false));
    final m = CardCycle.matchUnattributed(c0, [CardPayment(23000.54, DateTime(2026, 10, 31))])!;
    final c = CardCycle.compute(card: card, cardTransactions: const [], payments: [m], now: now);
    expect(c.state, StatementState.paid);
    expect(c.cycleStart, DateTime(2026, 10, 24));
    expect(c.nextStatement, DateTime(2026, 11, 23));
    expect(c.nextDueDate, DateTime(2026, 12, 3));
  });

  test('ICICI ••4007 (no statement SMS): estimated bill is not shown as overdue; Mark as paid settles it', () {
    final card = CreditCard(id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007', statementDay: 23, dueDay: 3);
    final spend = [
      for (final (d, a) in [(DateTime(2026, 10, 2), 2699.0), (DateTime(2026, 10, 15), 1200.0)])
        processorTx(a, d),
    ];
    final now = DateTime(2026, 11, 14, 18);
    final c = CardCycle.compute(card: card, cardTransactions: spend, payments: const [], now: now);
    expect((c.statementEstimated, c.state), (true, StatementState.unconfirmed));
    final paid = CardCycle.compute(card: card, cardTransactions: spend, payments: [CardPayment(c.statementTotal!, DateTime(2026, 11, 14))], now: now);
    expect(paid.state, StatementState.paid);
  });
}
