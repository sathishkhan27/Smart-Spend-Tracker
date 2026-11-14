import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/raw_message.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_parser.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

RawMessage sms(String body, {String sender = 'VM-HDFCBK', DateTime? at}) => RawMessage(
      id: body.hashCode.toString(),
      source: TxSource.sms,
      sender: sender,
      body: body,
      receivedAt: at ?? DateTime(2026, 11, 5, 14, 30),
    );

void main() {
  final parser = TransactionParser();

  group('classification', () {
    test('ignores OTP messages', () {
      final r = parser.parse(sms('123456 is your OTP for txn of Rs 2,500 at AMAZON. Do not share it with anyone.'));
      expect(r.status, ExtractionStatus.ignored);
      expect(r.ignoreReason, 'otp');
    });

    test('ignores promotional messages', () {
      final r = parser.parse(sms('Get up to Rs 5,00,000 pre-approved personal loan! Apply now. T&C apply', sender: 'AD-HDFCBK'));
      expect(r.status, ExtractionStatus.ignored);
    });

    test('ignores bill due reminders', () {
      final r = parser.parse(sms('Your credit card bill of Rs 12,340 is due on 15-11-2026. Pay now to avoid charges.'));
      expect(r.status, ExtractionStatus.ignored);
    });

    test('ignores messages from personal numbers', () {
      final r = parser.parse(sms('I paid Rs 500 debited from my account', sender: '+919876543210'));
      expect(r.ignoreReason, 'personal-sender');
    });
  });

  group('extraction', () {
    test('HDFC UPI debit via template', () {
      final r = parser.parse(sms(
          'Rs.250.00 debited from A/c **1234 on 04-11-26 to VPA swiggy@icici (UPI Ref No. 430912345678). Not you? Call 18002586161'));
      expect(r.status, ExtractionStatus.success);
      expect(r.amount, 250);
      expect(r.direction, TxDirection.outflow);
      expect(r.maskedAccount, 'XX1234');
      expect(r.referenceNumber, '430912345678');
      expect(r.bankName, 'HDFC Bank');
      expect(r.paymentMode, PaymentMode.upi);
      expect(r.type, TxType.upiPayment);
      expect(r.transactionDate!.day, 4);
      expect(r.counterparty, isNotNull);
    });

    test('SBI credit with balance does not pick the balance amount', () {
      final r = parser.parse(sms(
          'Dear Customer, your A/c X5678 is credited by Rs.45,000.00 on 01Nov26 by NEFT from ACME TECHNOLOGIES SALARY. Avl Bal Rs 1,20,500.50 -SBI',
          sender: 'BZ-SBIINB'));
      expect(r.amount, 45000);
      expect(r.direction, TxDirection.inflow);
      expect(r.type, TxType.salaryCredit);
      expect(r.bankName, 'State Bank of India');
      expect(r.transactionDate, DateTime(2026, 11, 1, 12));
    });

    test('credit card spend', () {
      final r = parser.parse(sms(
          'Thank you for using your ICICI Bank Credit Card XX9012 for INR 1,299.00 at AMAZON on 03-Nov-26 at 18:42:10.',
          sender: 'JD-ICICIB'));
      expect(r.amount, 1299);
      expect(r.direction, TxDirection.outflow);
      expect(r.paymentMode, PaymentMode.creditCard);
      expect(r.type, TxType.creditCardPayment);
      expect(r.counterparty, 'Amazon');
      expect(r.transactionDate, DateTime(2026, 11, 3, 18, 42, 10));
      expect(r.hasExplicitTime, isTrue);
    });

    test('ATM withdrawal', () {
      final r = parser.parse(sms('Rs 5000 withdrawn at ATM S1AW123 from A/c XX4321 on 02/11/2026. Avl bal Rs 9,000', sender: 'AX-AXISBK'));
      expect(r.type, TxType.atmWithdrawal);
      expect(r.paymentMode, PaymentMode.atm);
      expect(r.amount, 5000);
    });

    test('failed transaction is flagged', () {
      final r = parser.parse(sms('Your transaction of Rs 799 at NETFLIX on card XX1111 has failed. No amount debited.', sender: 'VK-KOTAKB'));
      expect(r.isFailedTransaction, isTrue);
      expect(r.type, TxType.failed);
    });

    test('refund is inflow', () {
      final r = parser.parse(sms('Refund of Rs 499.00 from FLIPKART credited to your A/c XX1234 on 03-11-2026.'));
      expect(r.direction, TxDirection.inflow);
      expect(r.type, TxType.refund);
    });

    test('unknown institution is marked for review', () {
      final r = parser.parse(sms('Rs 300 debited towards order 5543', sender: 'VM-UNKNWN'));
      expect(r.status, ExtractionStatus.needsReview);
    });

    test('email with html body', () {
      final r = parser.parse(RawMessage(
        id: 'm1',
        source: TxSource.email,
        sender: 'alerts@hdfcbank.net',
        senderName: 'HDFC Bank InstaAlerts',
        subject: 'You have done a UPI txn. Check details!',
        body: '<p>Dear Customer,</p><p>Rs.1,250.00 has been debited from account **1234 to VPA zomato@hdfcbank ZOMATO LTD on 05-11-26.</p>'
            '<p>Your UPI transaction reference number is 431012349876.</p>',
        receivedAt: DateTime(2026, 11, 5, 21),
      ));
      expect(r.status, ExtractionStatus.success);
      expect(r.amount, 1250);
      expect(r.referenceNumber, '431012349876');
      expect(r.maskedAccount, 'XX1234');
    });
  });
}
