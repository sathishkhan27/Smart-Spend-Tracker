import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/cards/domain/card_sms_parser.dart';
import 'package:smart_spend_tracker/features/cards/domain/credit_card.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/raw_message.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

RawMessage sms(String body, {String sender = 'AX-ICICIT-S'}) =>
    RawMessage(id: '${body.hashCode}', source: TxSource.sms, sender: sender, body: body, receivedAt: DateTime(2026, 11, 13, 10));

void main() {
  setUpAll(AppClock.init);
  final p = CardSmsParser();

  test('limit-increase message gives the current credit limit', () {
    final s = p.parse(sms('Manage spends effectively by increasing the limit on ICICI Bank Credit Card XX4007 from Rs1,00,000 to Rs1,50,000. SMS CRLIM 4007 to 5676766 to raise the limit'))!;
    expect(s.last4, '4007');
    expect(s.creditLimit, 100000);
    expect(s.issuer.toLowerCase(), contains('icici'));
  });

  test('spend alert gives the available limit', () {
    final s = p.parse(sms('INR 1,250.00 spent using ICICI Bank Card XX4007 on 12-Nov-26 on AMAZON. Avl Limit: INR 85,432.10. If not you, call 18002662.'))!;
    expect((s.last4, s.availableLimit), ('4007', 85432.10));
  });

  test('HDFC style "Avl Lmt" alert', () {
    final s = p.parse(sms('Rs.499 spent on HDFC Bank Card x9012 at NETFLIX on 2026-11-10:10:15:12. Avl Lmt: Rs.1,23,456.00', sender: 'VM-HDFCBK'))!;
    expect((s.last4, s.availableLimit), ('9012', 123456.0));
  });

  test('statement gives total due, minimum due and due date', () {
    final s = p.parse(sms('Statement for ICICI Bank Credit Card XX4007: Total Amount Due Rs.18,345.50, Minimum Amount Due Rs.920.00, Due Date 02-Dec-26.'))!;
    expect((s.totalDue, s.minDue, s.dueDate), (18345.50, 920.0, DateTime(2026, 12, 2)));
  });

  test('payment confirmation', () {
    final s = p.parse(sms('Dear Customer, Payment of Rs 18,345.50 has been received on your ICICI Bank Credit Card XX4007 on 28-Nov-26. Thank you.'))!;
    expect(s.paymentAmount, 18345.50);
  });

  test('savings account alerts are not cards', () {
    expect(p.parse(sms('Rs.500 debited from A/c XX1234 on 12-11-26. Avl Bal Rs 9,120.00', sender: 'VM-SBIINB')), isNull);
  });

  test('derived figures: used, utilisation, pending due', () {
    final c = CreditCard(
      id: 'w_icici_4007', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007',
      creditLimit: 100000, availableLimit: 85000, totalDue: 18000, minDue: 900,
      statementAt: DateTime(2026, 11, 13), dueDate: DateTime(2026, 12, 2),
    );
    expect((c.used, c.utilization, c.pendingDue), (15000.0, 0.15, 18000.0));
    final paid = CreditCard(
      id: 'x', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007', totalDue: 18000, minDue: 900,
      statementAt: DateTime(2026, 11, 13), lastPaymentAt: DateTime(2026, 11, 28), lastPaymentAmount: 18000,
    );
    expect((paid.statementPaid, paid.pendingDue), (true, 0.0));
  });

  group('not credit cards', () {
    for (final body in const [
      'INR 500.00 debited from A/c XX1234 using Debit Card XX5678 at AMAZON on 12-11-26. Avl Bal INR 12,000.00 -Indian Bank',
      'Your Indian Bank A/c XX1234 is debited for Rs 2,000.00 at ATM using card ending 5678 on 12-11-26. Avl Bal Rs 10,000.00',
      'Rs.350.00 spent on your card XX5678 at SWIGGY on 12-11-26. Avl Bal Rs 9,650.00 -Indian Bank',
      'Dear Customer, RuPay Debit Card XX5678 used for Rs 120.00 at METRO. Avl Bal Rs 9,530.00. Indian Bank',
    ]) {
      test(body.substring(0, 40), () => expect(p.parse(sms(body, sender: 'VM-INDBNK')), isNull));
    }
  });

  test('a real credit card from a bank that also issues debit cards still works', () {
    final s = p.parse(sms('Rs 999.00 spent on your SBI Credit Card ending 3344 at FLIPKART on 12/11/26. Avl Lmt Rs 45,001.00', sender: 'VM-SBICRD'))!;
    expect((s.last4, s.availableLimit), ('3344', 45001.0));
  });
}
