// Regexes are built from raw-string pieces; interpolation can't be used in raw strings.
// ignore_for_file: prefer_interpolation_to_compose_strings
import '../../transactions/domain/engines/bank_templates.dart';
import '../../transactions/domain/engines/raw_message.dart';
import '../../transactions/domain/engines/transaction_parser.dart';
import '../../upcoming/domain/due_reminder_parser.dart';
import 'credit_card.dart';

/// Pulls credit-card facts from issuer messages:
/// * spend alerts → available limit ("Avl Lmt: INR 85,432.10")
/// * limit messages → credit limit ("limit on … Card XX4007 from Rs 1,00,000")
/// * statements → total / minimum due and due date
/// * payment confirmations → last payment
class CardSmsParser {
  CardSmsParser({TransactionParser? parser, DueReminderParser? dues})
      : _parser = parser ?? TransactionParser(),
        _dues = dues ?? DueReminderParser(parser: parser);

  final TransactionParser _parser;
  final DueReminderParser _dues;

  static const _amt = r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)';
  /// Needs real credit-card evidence: the words "credit card", or a credit
  /// limit (not "Avl Bal", which is a bank balance).
  static final _isCreditCard = RegExp(r'(credit\s*card|\bcc\b|avl\.?\s*(?:credit\s*)?lmt|avbl\.?\s*lmt|available\s*(?:credit\s*)?limit|avl\.?\s*limit|credit\s*limit)', caseSensitive: false);
  static final _debitCard = RegExp(r'(debit\s*card|atm\s*card|rupay\s*debit|\bdc\b\s*(?:no|ending|xx))', caseSensitive: false);
  static final _last4 = RegExp(r'card\s*(?:no\.?|number|ending(?:\s+(?:with|in))?)?\s*[:\-]?\s*(?:[xX*•]+\s*)?(\d{4})\b', caseSensitive: false);
  static final _anyMasked = RegExp(r'[xX*•]{2,}\s*(\d{4})\b');
  // Limit only: "Avl Bal" is a savings balance, never a card limit.
  static final _available = RegExp(r'(?:avl|avbl|available)\.?\s*(?:credit\s*)?(?:lmt|limit)\s*(?:is|:|-)?\s*' + _amt, caseSensitive: false);
  static final _limit = RegExp(r'(?:credit|total|card)\s*(?:card\s*)?(?:lmt|limit)\s*(?:is|of|:|-)?\s*' + _amt, caseSensitive: false);
  static final _limitFrom = RegExp(r'limit\s+(?:on\s+.{0,60}?\s+)?from\s+' + _amt, caseSensitive: false);
  // "Minimum Amount Due of Rs 9,570" / "minimum of Rs 9,570 is due"
  static final _minDue = RegExp(r'min(?:imum)?\.?\s*(?:(?:amount|amt)\.?\s*)?(?:due\s*(?:is|:|-|of)?|of)\s*' + _amt, caseSensitive: false);
  static final _revised = RegExp(r'revised\s+total\s+due\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?|\.[0-9]{1,2})(?:[\s,]+min(?:imum)?\s+due\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?|\.[0-9]{1,2}))?', caseSensitive: false);
  // SBI / other bank: "OTP to approve transaction of Rs. 23000.54 … to ICICI Bank Credit card"
  static final _hintOtp = RegExp(r'transaction\s+of\s+' + _amt + r'.{0,80}?\bto\s+([A-Za-z]+(?:\s+Bank)?)\s+credit\s*card', caseSensitive: false);
  static final _payment = RegExp(
      r'(?:payment\s+(?:of\s+)?' + _amt + r'.{0,60}?(?:received|credited|successful|posted)'
      r'|received\s+(?:a\s+|your\s+)?payment\s+(?:of\s+)?' + _amt +
      r'|thank\s+you\s+for\s+(?:the\s+|your\s+)?payment\s+(?:of\s+)?' + _amt +
      r'|we\s+have\s+received\s+' + _amt +
      r'|' + _amt + r'\s+(?:has\s+been\s+|is\s+)?(?:received|credited|paid)\s+(?:towards|to|on|in|for)\s+(?:your\s+)?(?:\w+\s+){0,4}(?:credit\s*)?card)',
      caseSensitive: false);
  static final _issuerInText = RegExp(r'\b([A-Z][A-Za-z]+(?:\s+Bank)?)\s+Credit\s*Card', caseSensitive: true);

  /// A card-bill payment seen from the paying bank (no card number).
  BillPaymentHint? parseHint(RawMessage m) {
    final x = _hintOtp.firstMatch(m.body);
    if (x == null) return null;
    final amount = double.tryParse(x.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;
    return BillPaymentHint(issuer: x.group(2)!.trim(), amount: amount, at: m.receivedAt);
  }

  CardSnapshot? parse(RawMessage m) {
    final text = [m.subject, m.body].whereType<String>().join(' \n ');
    if (!_isCreditCard.hasMatch(text)) return null;
    // Debit / ATM card alerts aren't credit cards (unless they also say "credit card").
    if (_debitCard.hasMatch(text) && !RegExp(r'credit\s*card', caseSensitive: false).hasMatch(text)) return null;
    final last4 = _last4.firstMatch(text)?.group(1) ?? _anyMasked.firstMatch(text)?.group(1);
    if (last4 == null) return null;

    final template = _parser.institutionFor(m);
    final issuer = template?.name ?? _issuerInText.firstMatch(text)?.group(1) ?? 'Credit card';
    final mentionsCard = RegExp(r'card', caseSensitive: false).hasMatch(text);
    if (!mentionsCard && template?.kind != InstitutionKind.creditCard) return null;

    double? num(Match? x) {
      if (x == null) return null;
      for (var i = 1; i <= x.groupCount; i++) {
        final g = x.group(i);
        if (g != null) return double.tryParse(g.replaceAll(',', ''));
      }
      return null;
    }

    final available = num(_available.firstMatch(text));
    final limit = num(_limit.firstMatch(text)) ?? num(_limitFrom.firstMatch(text));
    final due = _dues.parse(m);
    final hasDue = due != null && due.kind == DueKind.creditCard;
    final isStatement = hasDue && RegExp(r'statement', caseSensitive: false).hasMatch(text);
    // Refunds / reversals credited to the card are not bill payments.
    final isRefund = RegExp(r'\b(refund|reversal|reversed|cashback)\b', caseSensitive: false).hasMatch(text);
    final payment = isRefund ? null : num(_payment.firstMatch(text));
    final rev = _revised.firstMatch(text);
    double? revNum(String? g) => g == null ? null : double.tryParse(g.replaceAll(',', '').replaceFirst(RegExp(r'^\.'), '0.'));

    final snap = CardSnapshot(
      issuer: issuer,
      last4: last4,
      at: m.receivedAt,
      availableLimit: available,
      creditLimit: limit,
      totalDue: hasDue ? due.amount : null,
      minDue: hasDue ? num(_minDue.firstMatch(text)) : null,
      dueDate: hasDue ? due.dueDate : null,
      isStatement: isStatement,
      paymentAmount: payment,
      revisedTotalDue: revNum(rev?.group(1)),
      revisedMinDue: revNum(rev?.group(2)),
    );
    return snap.isEmpty ? null : snap;
  }
}
