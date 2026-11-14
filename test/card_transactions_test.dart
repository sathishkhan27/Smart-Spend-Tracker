import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/cards/data/credit_card_repository.dart';
import 'package:smart_spend_tracker/features/cards/domain/credit_card.dart';
import 'package:smart_spend_tracker/features/transactions/domain/category.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/categorization_engine.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/raw_message.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_parser.dart';
import 'package:smart_spend_tracker/features/transactions/domain/engines/transaction_processor.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction.dart';
import 'package:smart_spend_tracker/features/transactions/domain/transaction_enums.dart';

FinancialTransaction t({String? acct, PaymentMode mode = PaymentMode.creditCard, String? bank, TxType type = TxType.debit}) => FinancialTransaction(
      transactionId: 'x',
      workspaceId: 'w',
      ownerUserId: 'u',
      amount: 100,
      currency: 'INR',
      direction: TxDirection.outflow,
      transactionType: type,
      categoryId: 'shopping',
      categoryName: Categories.byId('shopping').name,
      transactionDate: DateTime.utc(2026, 11, 12),
      source: TxSource.sms,
      sources: const [TxSource.sms],
      status: TxStatus.success,
      maskedAccountNumber: acct,
      paymentMode: mode,
      bankName: bank,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  setUpAll(AppClock.init);
  const card = CreditCard(id: 'c', workspaceId: 'w', issuer: 'ICICI Bank', last4: '4007');

  test('matches however the card number was written', () {
    expect(CreditCardRepository.belongsToCard(t(acct: 'XX4007'), card), isTrue);
    expect(CreditCardRepository.belongsToCard(t(acct: 'XX007'), card), isTrue); // 3-digit mask
    expect(CreditCardRepository.belongsToCard(t(acct: 'XX9012'), card), isFalse);
  });

  test('card spend with no number matches by issuer', () {
    expect(CreditCardRepository.belongsToCard(t(bank: 'ICICI Bank'), card), isTrue);
    expect(CreditCardRepository.belongsToCard(t(bank: 'HDFC Bank'), card), isFalse);
    expect(CreditCardRepository.belongsToCard(t(bank: 'ICICI Bank', mode: PaymentMode.upi), card), isFalse);
  });

  test('card number with spaces is read from the SMS', () {
    final out = TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine()).process(
      RawMessage(
        id: '1',
        source: TxSource.sms,
        sender: 'AX-ICICIT-S',
        body: 'Rs 1,250.00 spent on your ICICI Bank Credit Card No. XXXX XXXX XXXX 4007 at AMAZON on 12-Nov-26. Avl Limit Rs 85,432.10',
        receivedAt: DateTime(2026, 11, 12, 10),
      ),
      const ProcessingContext(workspaceId: 'w', userId: 'u'),
    );
    expect(out.transaction!.maskedAccountNumber, 'XX4007');
    expect(CreditCardRepository.belongsToCard(out.transaction!, card), isTrue);
  });

  group('payment mode for card alerts', () {
    PaymentMode mode(String body, {String sender = 'AX-ICICIT-S'}) => TransactionProcessor(parser: TransactionParser(), categorizer: CategorizationEngine())
        .process(RawMessage(id: '1', source: TxSource.sms, sender: sender, body: body, receivedAt: DateTime(2026, 11, 12, 10)), const ProcessingContext(workspaceId: 'w', userId: 'u'))
        .transaction!
        .paymentMode;

    test('ICICI "Card XX4007 … Avl Limit" is a credit card', () {
      expect(mode('INR 1,250.00 spent using ICICI Bank Card XX4007 on 12-Nov-26 on AMAZON. Avl Limit: INR 85,432.10.'), PaymentMode.creditCard);
    });
    test('explicit credit card', () {
      expect(mode('Rs 999 spent on your ICICI Bank Credit Card XX4007 at FLIPKART on 12-Nov-26.'), PaymentMode.creditCard);
    });
    test('explicit debit card stays debit', () {
      expect(mode('Rs 500 debited from A/c XX1234 using Debit Card XX5678 at AMAZON on 12-11-26. Avl Bal Rs 9,000', sender: 'VM-INDBNK'), PaymentMode.debitCard);
    });
  });
}
