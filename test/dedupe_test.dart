import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/duplicate_detector.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

DedupeCandidate c(
  String id,
  TxSource src, {
  double amount = 420,
  DateTime? at,
  String? ref,
  String? acct,
  String? bank,
  String? payee,
  PaymentMode? mode,
}) =>
    DedupeCandidate(
      transactionId: id,
      amount: amount,
      direction: TxDirection.outflow,
      dateUtc: at ?? AppClock.toUtc(DateTime(2026, 11, 13, 14, 5)),
      referenceNumber: ref,
      maskedAccount: acct,
      bankName: bank,
      counterparty: payee,
      paymentMode: mode,
      sources: [src],
    );

void main() {
  setUpAll(AppClock.init);
  const d = DuplicateDetector();
  bool dup(DedupeCandidate a, DedupeCandidate b) => d.check(a, [b], sourceKey: 'k').isDuplicate;

  test('SMS + email from the same bank within 2h merge (no account or ref)', () {
    final sms = c('s', TxSource.sms, bank: 'HDFC Bank');
    final mail = c('e', TxSource.email, bank: 'HDFC', at: AppClock.toUtc(DateTime(2026, 11, 13, 14, 40)));
    expect(dup(mail, sms), isTrue);
  });

  test('masks of different length still match on shared trailing digits', () {
    final sms = c('s', TxSource.sms, acct: 'XX234');
    final mail = c('e', TxSource.email, acct: 'XXXXXXXX1234');
    expect(dup(mail, sms), isTrue);
  });

  test('different accounts never merge', () {
    final sms = c('s', TxSource.sms, acct: 'XX1234', bank: 'HDFC');
    final mail = c('e', TxSource.email, acct: 'XX9876', bank: 'HDFC');
    expect(dup(mail, sms), isFalse);
  });

  test('email order ID vs SMS UPI reference is not treated as a conflict', () {
    final sms = c('s', TxSource.sms, ref: '512345678901', bank: 'ICICI Bank', payee: 'Swiggy', mode: PaymentMode.upi);
    final mail = c('e', TxSource.email, ref: 'ORD-88AB21', payee: 'SWIGGY', mode: PaymentMode.upi);
    expect(dup(mail, sms), isTrue);
  });

  test('two different UPI references are two payments', () {
    final a = c('s', TxSource.sms, ref: '512345678901');
    final b = c('e', TxSource.email, ref: '512345678999');
    expect(dup(b, a), isFalse);
  });

  test('date-only email matches an SMS from the same day', () {
    final sms = c('s', TxSource.sms, acct: 'XX1234', at: AppClock.toUtc(DateTime(2026, 11, 13, 19, 30)));
    final mail = c('e', TxSource.email, acct: '1234', at: AppClock.toUtc(DateTime(2026, 11, 13)));
    expect(dup(mail, sms), isTrue);
  });

  test('two SMS of the same amount stay separate (two coffees)', () {
    final a = c('s1', TxSource.sms, bank: 'HDFC', acct: 'XX1234');
    final b = c('s2', TxSource.sms, bank: 'HDFC', acct: 'XX1234', at: AppClock.toUtc(DateTime(2026, 11, 13, 14, 30)));
    expect(dup(b, a), isFalse);
  });

  test('a bank SMS and a payment-app email for the same payee still merge', () {
    final sms = c('s', TxSource.sms, bank: 'HDFC Bank', payee: 'Swiggy');
    final mail = c('e', TxSource.email, bank: 'Paytm', payee: 'Swiggy Instamart', at: AppClock.toUtc(DateTime(2026, 11, 13, 14, 20)));
    expect(dup(mail, sms), isTrue);
  });

  test('merged record keeps details only the email had', () {
    final sms = c('s', TxSource.sms, acct: 'XX1234');
    final mail = c('e', TxSource.email, ref: '512345678901', payee: 'Swiggy');
    final merged = sms.enrichedWith(mail);
    expect(merged.referenceNumber, '512345678901');
    expect(merged.counterparty, 'Swiggy');
    expect(merged.maskedAccount, 'XX1234');
    expect(merged.sources.toSet(), {TxSource.sms, TxSource.email});
  });
}
