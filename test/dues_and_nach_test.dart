import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/categorization_engine.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/raw_message.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_parser.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_processor.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/due_payment_matcher.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/due_reminder_parser.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/recurring_expense.dart';

import 'engines/engines_test.dart' show tx;

RawMessage sms(String body, {String sender = 'VM-HDFCBK', DateTime? at}) => RawMessage(
      id: body.hashCode.toString(),
      source: TxSource.sms,
      sender: sender,
      body: body,
      receivedAt: at ?? DateTime(2026, 11, 28, 10),
    );

void main() {
  setUpAll(AppClock.init);
  final dues = DueReminderParser();

  group('due reminders → Upcoming', () {
    test('EMI due with dd-mm-yyyy date', () {
      final d = dues.parse(sms('Dear Customer, EMI of Rs.5,250.00 for your Loan A/c XX4821 is due on 05-12-2026. Please maintain sufficient balance.'))!;
      expect(d.kind, DueKind.emi);
      expect(d.amount, 5250);
      expect(d.dueDate, DateTime(2026, 12, 5));
      expect(d.maskedAccount, 'XX4821');
      expect(d.categoryId, 'loan_emi');
    });

    test('NACH auto-debit notice ("will be debited on 5th Dec")', () {
      final d = dues.parse(sms('Your loan EMI of INR 12,400 will be debited on 5th Dec from A/c XX1234 via NACH. Keep sufficient balance.'))!;
      expect(d.kind, DueKind.emi);
      expect(d.amount, 12400);
      expect(d.dueDate, DateTime(2026, 12, 5));
    });

    test('credit card bill uses total due, not minimum due', () {
      final d = dues.parse(sms('Statement for HDFC Bank Credit Card ending 9012: Total Amount Due Rs.18,345.50, Minimum Amount Due Rs.920.00, Due Date 12-Dec-26.'))!;
      expect(d.kind, DueKind.creditCard);
      expect(d.amount, 18345.50);
      expect(d.dueDate, DateTime(2026, 12, 12));
    });

    test('a completed EMI debit is a transaction, not a reminder', () {
      expect(dues.parse(sms('Rs.5,250.00 has been debited from A/c XX1234 towards EMI for Loan XX4821 on 05-12-2026.')), isNull);
    });

    test('loan offers are ignored', () {
      expect(dues.parse(sms('Pre-approved personal loan up to Rs 5,00,000! EMI starting Rs 999. Apply now, offer due by 30-11-2026.')), isNull);
    });

    test('same loan every month maps to one Upcoming entry', () {
      final a = dues.parse(sms('EMI of Rs.5,250 for Loan A/c XX4821 is due on 05-12-2026.'))!;
      final b = dues.parse(sms('EMI of Rs.5,250 for Loan A/c XX4821 is due on 05-01-2027.'))!;
      expect(a.key, b.key);
    });
  });

  group('EMI paid → marked paid', () {
    final emi = RecurringExpense(
      id: 'r1',
      workspaceId: 'w',
      name: 'HDFC Bank EMI ••4821',
      expectedAmount: 5250,
      frequency: RecurrenceFrequency.monthly,
      nextDueDate: DateTime(2026, 12, 5),
      categoryId: 'loan_emi',
      status: RecurringStatus.active,
      createdBy: 'u',
    );

    test('matching EMI debit near the due date settles it', () {
      final paid = tx(id: 't1', amount: 5250, cat: 'loan_emi', date: AppClock.toUtc(DateTime(2026, 12, 4, 9)));
      final m = const DuePaymentMatcher().match([emi], [paid]);
      expect(m.single.expense.id, 'r1');
      expect(m.single.dueDate, DateTime(2026, 12, 5));
    });

    test('a different amount or a far-away date does not', () {
      final other = tx(id: 't2', amount: 1999, cat: 'shopping', date: AppClock.toUtc(DateTime(2026, 12, 4)));
      final early = tx(id: 't3', amount: 5250, cat: 'loan_emi', date: AppClock.toUtc(DateTime(2026, 11, 2)));
      expect(const DuePaymentMatcher().match([emi], [other, early]), isEmpty);
    });

    test('an already-paid cycle is not paid twice', () {
      final paidEmi = RecurringExpense(
        id: 'r1', workspaceId: 'w', name: 'EMI', expectedAmount: 5250, frequency: RecurrenceFrequency.monthly,
        nextDueDate: DateTime(2026, 12, 5), lastPaidDate: DateTime(2026, 12, 5), categoryId: 'loan_emi',
        status: RecurringStatus.active, createdBy: 'u',
      );
      final again = tx(id: 't4', amount: 5250, cat: 'loan_emi', date: AppClock.toUtc(DateTime(2026, 12, 6)));
      expect(const DuePaymentMatcher().match([paidEmi], [again]), isEmpty);
    });
  });

  group('NACH / ACH dividend credits', () {
    final processor = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine());
    const ctx = ProcessingContext(workspaceId: 'w', userId: 'u');

    for (final body in [
      'Rs.1,890.00 credited to A/c XX1234 on 12-11-26 by NACH-CR INFOSYS LIMITED-DIV. Avl Bal Rs.45,210.00',
      'Update! INR 1,890.00 deposited in HDFC Bank A/c XX1234 on 12-NOV-26 for ACH C- INFOSYS LTD FIN DIV 2025-26.',
      'Your A/c XX1234 is Cr with Rs.1,890.00 on 12/11/2026 Info: NACH-CR-INFOSYS LTD INT DIV.',
      'Dear Customer, your A/C XXXXX1234 has a credit by Transfer of Rs 1,890.00 on 12/11/26 by INFOSYS LIMITED DIVIDEND.',
    ]) {
      test('parsed as dividend income: ${body.substring(0, 40)}…', () {
        final out = processor.process(sms(body, sender: 'AD-HDFCBK', at: DateTime(2026, 11, 12, 11)), ctx);
        final t = out.transaction;
        expect(t, isNotNull, reason: 'should not be ignored');
        expect(t!.direction, TxDirection.inflow);
        expect(t.amount, 1890);
        expect(t.categoryId, 'investment_returns');
        expect((t.counterparty ?? t.narration).toLowerCase(), contains('infosys'));
      });
    }

    test('NACH-DR EMI auto-debit stays an expense', () {
      final out = processor.process(sms('Rs.5,250.00 debited from A/c XX1234 on 05-12-26 by NACH-DR HDFC BANK LOAN EMI.', at: DateTime(2026, 12, 5, 9)), ctx);
      expect(out.transaction!.direction, TxDirection.outflow);
      expect(out.transaction!.categoryId, 'loan_emi');
    });
  });

  group('more bank wordings for NACH / ACH', () {
    final processor = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine());
    const ctx = ProcessingContext(workspaceId: 'w', userId: 'u');
    ProcessingOutcome run(String body, {String sender = 'AD-ICICIB'}) => processor.process(sms(body, sender: sender, at: DateTime(2026, 11, 12, 11)), ctx);

    for (final (body, sender) in const [
      ('ICICI Bank Account XX123 is credited with INR 1,890.00 on 12-Nov-26 by ACH/INFOSYS LIMITED/FIN DIV 25-26.', 'AD-ICICIB'),
      ('Your A/C XXXXX1234 has been credited with INR 1,890.00 on 12-11-2026 towards ACH Credit INFOSYS LTD DIVIDEND.', 'VM-IDFCFB'),
      ('Rs.1890.00 is credited in your Kotak Bank a/c XX1234 by ACH C INFOSYS LIMITED on 12-Nov-26.', 'VK-KOTAKB'),
      ('INR 1890.00 credited to A/c no. XX1234 on 12-11-2026 at 10:10:10 IST. Info- NACH-CR-INFOSYS LTD-DIV. Avl Bal INR 45,210.00', 'AX-AXISBK'),
    ]) {
      test('credit: ${body.substring(0, 36)}…', () {
        final t = run(body, sender: sender).transaction;
        expect(t, isNotNull);
        expect(t!.direction, TxDirection.inflow);
        expect(t.amount, 1890);
        expect(t.categoryId, 'investment_returns');
        expect((t.counterparty ?? '').toLowerCase(), contains('infosys'));
      });
    }

    for (final (body, sender) in const [
      ('Dear Customer, your A/C XXXXX1234 has been debited by Rs 5,250.00 on 05/12/26 for NACH-DR- BAJAJ FINANCE LTD. -SBI', 'VM-SBIINB'),
      ('NACH Debit of Rs 5,250.00 from A/c XX1234 towards HDFC BANK LOAN on 05-12-2026 is successful.', 'VM-HDFCBK'),
      ('Rs.5250.00 debited from A/c XX1234 on 05-12-26 To ACH D- BAJAJFINANCE LTD.', 'VM-HDFCBK'),
    ]) {
      test('debit: ${body.substring(0, 36)}…', () {
        final t = run(body, sender: sender).transaction;
        expect(t, isNotNull);
        expect(t!.direction, TxDirection.outflow);
        expect(t.amount, 5250);
        expect(t.categoryId, 'loan_emi');
      });
    }
  });

  test('SBI NACH credit from a "… LIMITED" company is read (real message)', () {
    final processor = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine());
    final out = processor.process(
      sms('Dear Customer,Your A/C XXXXX08390 has a credit by NACH- INFOSYS LIMITED of Rs 26.00 on 11/11/26. Avl Bal Rs 4,818.26. Download YONO-SBI',
          sender: 'AD-SBIINB-S', at: DateTime(2026, 11, 11, 10)),
      const ProcessingContext(workspaceId: 'w', userId: 'u'),
    );
    final t = out.transaction;
    expect(t, isNotNull, reason: 'was dropped as "no-amount": LIMITED looked like "limit"');
    expect(t!.amount, 26); // not the 4,818.26 balance
    expect(t.direction, TxDirection.inflow);
    expect(t.counterparty, 'Infosys Limited'); // names are tidied to title case
    expect(t.categoryId, 'investment_returns');
    expect(t.maskedAccountNumber, 'XX8390');
    expect(AppClock.toLocal(t.transactionDate).day, 11);
  });

  test('a payee name containing "bal" is not taken for a balance', () {
    final processor = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine());
    final t = processor.process(sms('Rs.300.00 debited from A/c XX1234 at BALAJI STORES on 10-11-26. Avl Bal Rs 9,120.00', at: DateTime(2026, 11, 10)),
        const ProcessingContext(workspaceId: 'w', userId: 'u')).transaction;
    expect(t!.amount, 300);
  });

  group('SBI NACH debits', () {
    final processor = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine());
    FinancialTransaction? run(String body) =>
        processor.process(sms(body, sender: 'AD-SBIINB-S', at: DateTime(2026, 11, 10, 10)), const ProcessingContext(workspaceId: 'w', userId: 'u')).transaction;

    test('loan EMI from a "… LIMITED" lender', () {
      final t = run('Dear Customer,Your A/C XXXXX08390 has a debit by NACH- BAJAJ FINANCE LIMITED of Rs 5,250.00 on 05/11/26. Avl Bal Rs 4,818.26. Download YONO-SBI')!;
      expect((t.amount, t.direction, t.categoryId, t.counterparty), (5250.0, TxDirection.outflow, 'loan_emi', 'Bajaj Finance Limited'));
    });

    test('insurance premium by NACH', () {
      final t = run('Dear Customer, Your A/C XXXXX08390 has been debited by NACH- ICICI PRUDENTIAL LIFE INSURANCE CO LTD of Rs 2,000.00 on 05/11/26. Avl Bal Rs 2,818.26 -SBI')!;
      expect((t.amount, t.direction, t.categoryId), (2000.0, TxDirection.outflow, 'insurance'));
    });

    test('mutual fund SIP ("NACH DR TO …") is an investment, not healthcare', () {
      final t = run('Dear Customer, Your A/C XXXXX08390 is debited by Rs.1,500.00 on 05/11/26 for NACH DR TO HDFC MUTUAL FUND. Avl Bal Rs 1,318.26 -SBI')!;
      expect((t.amount, t.categoryId, t.counterparty), (1500.0, 'investments', 'Hdfc Mutual Fund'));
    });

    test('Zerodha SIP is an investment', () {
      final t = run('Dear Customer,Your A/C XXXXX08390 has a debit by NACH- SIP ZERODHA BROKING LTD of Rs 1,000.00 on 10/11/26. Avl Bal Rs 3,818.26. Download YONO-SBI')!;
      expect((t.amount, t.categoryId), (1000.0, 'investments'));
    });

    test('"debited by Rs5250.0 … transfer to <lender>" names the lender, not the amount', () {
      final t = run('Dear SBI User, your A/c X8390-debited by Rs5250.0 on 05Nov26 transfer to BAJAJ FINANCE LIMITED Ref No 512345678901. If not done by u, fwd this SMS to 9223008333 -SBI')!;
      expect((t.amount, t.categoryId, t.counterparty), (5250.0, 'loan_emi', 'Bajaj Finance Limited'));
    });
  });
}
