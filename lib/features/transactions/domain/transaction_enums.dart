enum TxDirection { inflow, outflow }

enum TxType {
  credit('Money credited'),
  debit('Money debited'),
  upiPayment('UPI payment'),
  neft('NEFT transfer'),
  imps('IMPS transfer'),
  rtgs('RTGS transfer'),
  atmWithdrawal('ATM withdrawal'),
  debitCardPayment('Debit card payment'),
  creditCardPayment('Credit card payment'),
  creditCardBillPayment('Credit card bill payment'),
  refund('Refund'),
  cashDeposit('Cash deposit'),
  interestCredit('Interest credit'),
  salaryCredit('Salary credit'),
  emiDebit('EMI debit'),
  billPayment('Bill payment'),
  failed('Failed transaction'),
  reversed('Reversed transaction');

  const TxType(this.label);
  final String label;
}

enum PaymentMode {
  upi('UPI'),
  neft('NEFT'),
  imps('IMPS'),
  rtgs('RTGS'),
  debitCard('Debit Card'),
  creditCard('Credit Card'),
  netBanking('Net Banking'),
  atm('ATM'),
  cash('Cash'),
  wallet('Wallet'),
  autoDebit('Auto Debit'),
  cheque('Cheque'),
  other('Other');

  const PaymentMode(this.label);
  final String label;
}

enum TxSource {
  sms('SMS'),
  email('Email'),
  manual('Manual');

  const TxSource(this.label);
  final String label;
}

enum TxStatus {
  pending('Pending'),
  processing('Processing'),
  success('Success'),
  failed('Failed'),
  duplicate('Duplicate'),
  needsReview('Needs Review'),
  ignored('Ignored');

  const TxStatus(this.label);
  final String label;
}

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
