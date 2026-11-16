import '../transaction_enums.dart';
import 'bank_templates.dart';
import 'raw_message.dart';

/// Rule-based extraction engine shared by SMS and email sources.
///
/// Pipeline: classify (financial vs OTP/promo/reminder) → apply bank template
/// regexes → generic extraction → validation → confidence scoring.
class TransactionParser {
  TransactionParser({List<BankTemplate>? templates}) : templates = templates ?? defaultTemplates;

  final List<BankTemplate> templates;

  // ---------- Classification vocab ----------
  static final _otp = RegExp(r'\b(otp|one[\s-]?time[\s-]?password|verification code|security code|passcode)\b', caseSensitive: false);
  static final _promo = RegExp(
      r'(\boffer\b|cashback (?:up ?to|of up)|apply now|pre[\s-]?approved|you are eligible|get up ?to|\bwin\b|click here|limited period|\bdiscount\b|\bcoupon\b|loan of up ?to|emi starting|lowest interest|upgrade your|hurry|t&c apply|exclusive)',
      caseSensitive: false);
  static final _reminder = RegExp(
      r'(\bis due\b|\bdue on\b|payment due|minimum amount due|total amount due|will be debited|is scheduled|due date|request(?:ed)? money|collect request|has requested)',
      caseSensitive: false);
  static final _txnVerb = RegExp(
      r'\b(debited|credited|spent|withdrawn|paid|sent|received|deposited|deducted|transferred|purchase[d]?|txn of|transaction of|refund(?:ed)?|reversed|thank you for using|charged|payment of|amount paid|order total|debit(?:ed)? for|has a credit|has a debit|credit(?:ed)? (?:of|by|with)|debit(?:ed)? (?:of|by|with)|n?ach[\s\-:]*(?:credit|debit)|is cr|cr(?:edited)? to|nach[\s\-:]*(?:cr|dr)|e?ach[\s\-:]*(?:cr|dr|c|d)\b|dividend)\b',
      caseSensitive: false);

  /// Bank short forms that fix the direction regardless of word order:
  /// "NACH-CR", "ACH C-", "has a credit", dividend → money in;
  /// "NACH-DR", "ACH D-", "has a debit" → money out (e.g. EMI auto-debit).
  static final _strongCredit = RegExp(
      r'(nach[\s\-:]*cr\b|\be?ach[\s\-:]*cr?\b[\s\-:]|n?ach[\s\-:]*credit\b|has a credit|\bcredit(?:ed)? (?:of|by|with)\b|\bdividend\b|\bint(?:erim)?\.? div\b|\bfin(?:al)? div\b)',
      caseSensitive: false);
  static final _strongDebit = RegExp(r'(nach[\s\-:]*dr\b|\be?ach[\s\-:]*dr?\b[\s\-:]|n?ach[\s\-:]*debit\b|has a debit)', caseSensitive: false);

  static final _debitCue = RegExp(
      r'\b(debited|spent|withdrawn|paid|sent|deducted|transferred to|trf to|purchase[d]?|txn of|transaction of|thank you for using|charged|payment of|amount paid|order total|debit(?:ed)? for|dr\b)',
      caseSensitive: false);
  static final _creditCue = RegExp(
      r'\b(credited|received|deposited|refund(?:ed)?|reversed|reversal|cr\b|added to your)',
      caseSensitive: false);

  // ---------- Field extraction ----------
  static final _amount = RegExp(r'(rs\.?|inr|₹|usd|\$|eur|€|gbp|£|aed)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false);
  static final _amountSuffix = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:rs|inr)\b', caseSensitive: false);
  /// Words that mark the NEXT amount as a balance/limit, not the transaction.
  /// Whole words only: "INFOSYS LIMITED of Rs 26" or "BALAJI STORES Rs 300"
  /// must not be mistaken for "limit"/"bal".
  static final _balanceContext = RegExp(
      r'\b(bal(?:ance)?|avl|available|limit|outstanding|total due|min(?:imum)? due)\b[\s:.a-z]{0,12}$',
      caseSensitive: false);
  static final _account = RegExp(
      r'\b(?:a/c|a/c\.|acct|account|ac|card)\s*(?:no\.?|number)?\s*(?:ending(?:\s+(?:with|in))?)?\s*[:\-]?\s*(?:[xX*•\.]+[\s\-]*)*(\d{3,6})\b',
      caseSensitive: false);
  static final _upiId = RegExp(r'\b([a-zA-Z0-9.\-_]{2,64})@([a-zA-Z]{2,20})\b(?![.@\w])');
  static final _upiRef = RegExp(
      r'\b(?:upi)\s*(?:ref(?:erence)?|txn|transaction)?\.?\s*(?:ref(?:erence)?)?\s*(?:no|id|#|number)?\.?\s*(?:is\s+)?[:\-]?\s*(\d{10,16})',
      caseSensitive: false);
  static final _genericRef = RegExp(
      r'\b(?:ref(?:erence)?|utr|txn|transaction|rrn|imps ref|neft ref)\s*(?:no|id|#|number)?\.?\s*(?:is\s+)?[:\-]?\s*([A-Z0-9]{8,22})\b',
      caseSensitive: false);
  static final _time = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\s*(am|pm)?\b', caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _dateNumeric = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');
  static final _dateIso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  static final _dateMonthName = RegExp(
      r'\b(\d{1,2})[\s\-/]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s\-/,]*(\d{2,4})?\b',
      caseSensitive: false);

  static final _merchantPatterns = <RegExp>[
    // Card spends (ICICI and similar), checked first because the generic
    // patterns below miss this wording:
    // "Credit Card XX4007 debited for INR 20.00 on 13-Nov-26 for UPI-XXXXXXXX4496-Juice. To dispute…"
    RegExp(r'\bfor\s+upi[\s\-/]+[x\d]+[\s\-/]+([a-z0-9&.\x27*\- ]{2,40}?)(?=\.\s|\.$|\s+to dispute|\s+avl|,|;|$)', caseSensitive: false),
    // "Credit Card XX8003 debited for INR 1,299.00 on 12-Nov-26 for AMAZON PAY INDIA PRIVA. To dispute…"
    RegExp(
        r'\bcard\s+[x*]*\d{3,4}\s+debited\s+for\s+(?:rs\.?|inr|₹)\s*[\d,]+(?:\.\d{1,2})?\s+on\s+\S+?\s+(?:for|at|towards)\s+(?!upi\b)([a-z0-9&.\x27*\- ]{2,40}?)(?=\.\s|\.$|\s+to dispute|\s+avl|,|;|$)',
        caseSensitive: false),
    // "INR 265.00 spent using ICICI Bank Card XX8003 on 07-Nov-26 on TATAPLAYLTD. Avl Limit…"
    RegExp(r'\bspent\s+(?:using|on|via)\s+.{0,40}?card\s+[x*]*\d{3,4}\s+on\s+\S+?\s+(?:on|at)\s+([a-z0-9&.\x27*\- ]{2,40}?)(?=\.\s|\.$|\s+avl|,|;|$)',
        caseSensitive: false),
    // SBI: "has a credit by NACH- INFOSYS LIMITED of Rs 26.00"
    RegExp(r'\bn?ach[\s\-:]+(?!cr\b|dr\b|c\b|d\b|credit\b|debit\b)([a-z][a-z0-9&.\x27 ]{2,40}?)(?=\s+of\s|\s+on\b|\s*[-/]|\s+(?:div|dividend|int|fin|final|interim|ref|dt)\b|\.|,|;|$)', caseSensitive: false),
    // "ACH/INFOSYS LIMITED/FIN DIV", "ACH Credit INFOSYS LTD DIVIDEND"
    RegExp(r'\bn?ach(?:\s*/|[\s\-:]+(?:credit|debit)\s+)([a-z][a-z0-9&.\x27 ]{2,40}?)(?=\s*/|\s+(?:div|dividend|int|fin|final|interim|on|ref|dt)\b|\.|,|;|$)', caseSensitive: false),
    RegExp(
        r'\be?n?ach[\s\-:]*(?:cr|dr|c|d)\b[\s\-:]+(?:to\s+|from\s+|for\s+)?([a-z0-9&.\x27 ]{3,40}?)(?=\s*[-/]|\s+(?:div|dividend|int|fin|final|interim|on|ref|dt|a/c)\b|\.|,|;|$)',
        caseSensitive: false),
    // "Info: MAKEMYTRIP INDIA. Avl Lmt…" — stop at the sentence end, not 40 chars on.
    RegExp(r'\binfo[:\-]\s*(?:upi/[a-z0-9]+/\d+/)?([a-z0-9&.\x27 \-]{3,40}?)(?=\.\s|\.$|,|;|\s+avl\b|\s+avbl\b|$)', caseSensitive: false),
    RegExp(r'\b(?:at|@)\s+([a-z0-9&.\x27*\- ]{2,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+txn|\s+using|\.|,|;|\s*\(|$)', caseSensitive: false),
    RegExp(r'\b(?:paid to|sent to|transfer(?:red)? to|trf to|payment to|to vpa|towards)\s+([a-z0-9&.\x27@\- ]{2,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+upi|\.|,|;|\s*\(|$)', caseSensitive: false),
    RegExp(r'\b(?:from|by)\s+(?!transfer\b|cash\b|clearing\b|rs\.?\s*\d|inr\s*\d|₹)(?:vpa\s+)?([a-z0-9&.\x27@\- ]{2,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+upi|\s+a/c|\.|,|;|\s*\(|$)', caseSensitive: false),
    RegExp(r'\bto\s+(?:vpa\s+)?([a-z0-9&.\x27@\- ]{2,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+upi|\.|,|;|\s*\(|$)', caseSensitive: false),
  ];
  static final _upiNarration = RegExp(r'upi/(?:p2[am]|dr|cr)?/?(\d{6,})/([^/\n]{2,40})', caseSensitive: false);
  static final _personalSender = RegExp(r'^\+?\d{10,14}$');
  static final _nonMerchantWords = RegExp(
      r'^(your|you|a/c|ac|account|card|the|bank|rs|inr|upi|vpa|imps|neft|rtgs|self|xx+\d*|\d+|on|ref|via|beneficiary|linked|registered)$',
      caseSensitive: false);

  // ---------------------------------------------------------------------------

  ExtractedTransaction parse(RawMessage message) {
    final text = message.source == TxSource.email ? _cleanEmail(message) : message.body.trim();
    final lower = text.toLowerCase();

    if (message.source == TxSource.sms && _personalSender.hasMatch(message.sender.replaceAll(' ', ''))) {
      return ExtractedTransaction.ignored(message, 'personal-sender');
    }
    final hasVerb = _txnVerb.hasMatch(text);
    if (_otp.hasMatch(text) && !RegExp(r'\b(debited|credited|spent|withdrawn)\b', caseSensitive: false).hasMatch(text)) {
      return ExtractedTransaction.ignored(message, 'otp');
    }
    if (_reminder.hasMatch(text) && !RegExp(r'\b(debited|credited|received|spent)\b', caseSensitive: false).hasMatch(text)) {
      return ExtractedTransaction.ignored(message, 'reminder');
    }
    if (_promo.hasMatch(text) && !RegExp(r'\b(debited|credited|spent|withdrawn|refunded)\b', caseSensitive: false).hasMatch(text)) {
      return ExtractedTransaction.ignored(message, 'promotional');
    }
    if (!hasVerb) return ExtractedTransaction.ignored(message, 'no-transaction-verb');

    final institution = _detectInstitution(message, lower);

    // 1. Template-specific extraction.
    _TemplateHit? hit;
    if (institution != null) {
      for (final p in institution.patterns) {
        final m = RegExp(p.regex, caseSensitive: false).firstMatch(text);
        if (m != null) {
          hit = _TemplateHit(m, p.direction);
          break;
        }
      }
    }

    // 2. Generic extraction.
    final amountInfo = _extractAmount(text, hit?.group('amount'));
    if (amountInfo == null || amountInfo.$1 <= 0) {
      return ExtractedTransaction.ignored(message, 'no-amount');
    }
    final (amount, currency) = amountInfo;

    final isFailed = RegExp(r'\b(failed|declined|unsuccessful|could not be processed|rejected)\b', caseSensitive: false).hasMatch(text);
    final isReversed = RegExp(r'\b(reversed|reversal)\b', caseSensitive: false).hasMatch(text);
    final direction = hit?.direction ?? _detectDirection(text, isReversed);
    final paymentMode = _detectPaymentMode(lower);
    final type = _detectType(lower, direction, paymentMode, isFailed: isFailed, isReversed: isReversed);

    final account = hit?.group('account') ?? _account.firstMatch(text)?.group(1);
    final masked = account == null ? null : 'XX${account.length > 4 ? account.substring(account.length - 4) : account}';

    final upiMatch = _upiId.allMatches(text).where((m) => !m.group(0)!.contains('.com')).firstOrNull;
    final upiId = upiMatch?.group(0)?.toLowerCase();
    final reference = _normalizeRef(hit?.group('ref') ?? _upiRef.firstMatch(text)?.group(1) ?? _extractGenericRef(text));

    final dateResult = _extractDate(text, hit?.group('date'), message.receivedAt);

    var counterparty = _cleanName(hit?.group('merchant')) ?? _extractCounterparty(text, upiId);
    if (counterparty == null && message.source == TxSource.email && institution?.kind != InstitutionKind.bank) {
      counterparty = _cleanName(message.senderName);
    }
    final merchant = counterparty;

    final isCardBillPaymentReceived = lower.contains('credit card') &&
        RegExp(r'payment (?:of .{0,20})?(?:has been )?received|received (?:a )?payment', caseSensitive: false).hasMatch(text);

    final missing = <String>[
      if (direction == null) 'direction',
      if (institution == null && masked == null) 'institution',
      if (!dateResult.explicitDate) 'date',
    ];

    var confidence = 0.35; // amount
    if (direction != null) confidence += 0.2;
    if (dateResult.explicitDate) confidence += 0.15;
    if (masked != null) confidence += 0.1;
    if (reference != null) confidence += 0.1;
    if (counterparty != null) confidence += 0.05;
    if (institution != null) confidence += 0.05;

    final status = (direction == null || (institution == null && masked == null))
        ? ExtractionStatus.needsReview
        : ExtractionStatus.success;

    return ExtractedTransaction(
      status: status,
      message: message,
      amount: amount,
      currency: currency,
      direction: direction,
      type: type,
      paymentMode: paymentMode,
      transactionDate: dateResult.date,
      hasExplicitDate: dateResult.explicitDate,
      hasExplicitTime: dateResult.explicitTime,
      bankName: institution?.name,
      maskedAccount: masked,
      merchant: merchant,
      counterparty: counterparty,
      upiId: upiId,
      referenceNumber: reference,
      originalNarration: _sanitizeNarration(text, reference),
      normalizedNarration: _normalizedNarration(type, direction, counterparty, paymentMode, institution?.name),
      confidence: confidence.clamp(0, 1).toDouble(),
      isFailedTransaction: isFailed,
      isInternalTransfer: isCardBillPaymentReceived ||
          RegExp(r'\b(self transfer|own account|to self|sweep (?:in|out))\b', caseSensitive: false).hasMatch(text),
      missingFields: missing,
    );
  }

  // ---------------------------------------------------------------------------

  /// Institution (bank / card issuer / insurer) that sent [m], if known.
  BankTemplate? institutionFor(RawMessage m) => _detectInstitution(m, m.body.toLowerCase());

  BankTemplate? _detectInstitution(RawMessage m, String lower) {
    if (m.source == TxSource.sms) {
      for (final t in templates) {
        if (t.matchesSender(m.sender)) return t;
      }
    } else {
      for (final t in templates) {
        if (t.matchesEmail(m.sender)) return t;
      }
    }
    for (final t in templates) {
      if (t.kind == InstitutionKind.bank && t.matchesBody(lower)) return t;
    }
    for (final t in templates) {
      if (t.matchesBody(lower)) return t;
    }
    return null;
  }

  (double, String)? _extractAmount(String text, String? templateAmount) {
    if (templateAmount != null) {
      final v = double.tryParse(templateAmount.replaceAll(',', ''));
      if (v != null) return (v, 'INR');
    }
    for (final m in _amount.allMatches(text)) {
      final before = text.substring((m.start - 30).clamp(0, m.start), m.start);
      if (_balanceContext.hasMatch(before)) continue;
      final v = double.tryParse(m.group(2)!.replaceAll(',', ''));
      if (v == null || v <= 0) continue;
      return (v, _currency(m.group(1)!));
    }
    for (final m in _amountSuffix.allMatches(text)) {
      final before = text.substring((m.start - 30).clamp(0, m.start), m.start);
      if (_balanceContext.hasMatch(before)) continue;
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return (v, 'INR');
    }
    return null;
  }

  String _currency(String token) => switch (token.toLowerCase()) {
        'usd' || r'$' => 'USD',
        'eur' || '€' => 'EUR',
        'gbp' || '£' => 'GBP',
        'aed' => 'AED',
        _ => 'INR',
      };

  TxDirection? _detectDirection(String text, bool isReversed) {
    if (isReversed) return TxDirection.inflow;
    final strongIn = _strongCredit.hasMatch(text), strongOut = _strongDebit.hasMatch(text);
    if (strongIn != strongOut) return strongIn ? TxDirection.inflow : TxDirection.outflow;
    final d = _debitCue.firstMatch(text);
    final c = _creditCue.firstMatch(text);
    if (d == null && c == null) return null;
    if (d == null) return TxDirection.inflow;
    if (c == null) return TxDirection.outflow;
    return d.start <= c.start ? TxDirection.outflow : TxDirection.inflow;
  }

  PaymentMode _detectPaymentMode(String lower) {
    // Spend ON a credit card, even via UPI ("ICICI Bank Credit Card XX4007
    // debited … for UPI-…"). A bank account paying a card bill mentions "A/c".
    if (RegExp(r'credit\s*card\s*(?:no\.?\s*)?[x*•]+\s*\d{3,4}').hasMatch(lower) && !RegExp(r'\ba/c\b|\baccount\b|\bacct\b').hasMatch(lower)) {
      return PaymentMode.creditCard;
    }
    if (RegExp(r'\b(upi|vpa)\b').hasMatch(lower) || lower.contains('@ybl') || lower.contains('@okaxis')) return PaymentMode.upi;
    if (lower.contains('imps')) return PaymentMode.imps;
    if (lower.contains('neft')) return PaymentMode.neft;
    if (lower.contains('rtgs')) return PaymentMode.rtgs;
    if (RegExp(r'\batm\b').hasMatch(lower) || lower.contains('cash withdrawal')) return PaymentMode.atm;
    if (lower.contains('credit card')) return PaymentMode.creditCard;
    if (RegExp(r'debit\s*card|atm\s*card|rupay\s*debit').hasMatch(lower)) return PaymentMode.debitCard;
    // Plain "Card XX4007" (e.g. ICICI alerts): a credit limit means a credit card.
    final mentionsCard = RegExp(r'\bcard\b').hasMatch(lower) || lower.contains('pos ');
    if (mentionsCard && RegExp(r'(avl\.?|avbl\.?|available)\s*(?:credit\s*)?(?:lmt|limit)|credit\s*limit').hasMatch(lower)) {
      return PaymentMode.creditCard;
    }
    if (mentionsCard) return PaymentMode.debitCard;
    if (RegExp(r'\b(nach|ach|ecs|auto[\s-]?debit|standing instruction|si\b|mandate)').hasMatch(lower)) return PaymentMode.autoDebit;
    if (lower.contains('wallet')) return PaymentMode.wallet;
    if (lower.contains('net banking') || lower.contains('netbanking')) return PaymentMode.netBanking;
    if (lower.contains('cheque') || lower.contains(' chq')) return PaymentMode.cheque;
    if (lower.contains('cash deposit') || lower.contains('by cash')) return PaymentMode.cash;
    return PaymentMode.other;
  }

  TxType _detectType(String lower, TxDirection? dir, PaymentMode mode, {required bool isFailed, required bool isReversed}) {
    if (isFailed) return TxType.failed;
    if (isReversed) return TxType.reversed;
    if (RegExp(r'\brefund').hasMatch(lower)) return TxType.refund;
    if (dir == TxDirection.inflow) {
      if (RegExp(r'\b(salary|sal cr|payroll)\b').hasMatch(lower)) return TxType.salaryCredit;
      if (RegExp(r'\b(interest|int\.? cr|int pd)\b').hasMatch(lower)) return TxType.interestCredit;
      if (lower.contains('cash deposit') || lower.contains('by cash') || lower.contains('cash dep')) return TxType.cashDeposit;
      if (lower.contains('credit card') && lower.contains('payment')) return TxType.creditCardBillPayment;
    } else if (dir == TxDirection.outflow) {
      if (mode == PaymentMode.atm || lower.contains('withdrawn')) return TxType.atmWithdrawal;
      if (RegExp(r'\b(emi|loan)\b').hasMatch(lower)) return TxType.emiDebit;
      if (RegExp(r'credit card (?:bill|payment|dues)|card ?bill|towards your credit card').hasMatch(lower)) {
        return TxType.creditCardBillPayment;
      }
      if (RegExp(r'\b(bill ?pay|bbps|bill payment|electricity bill|postpaid)').hasMatch(lower)) return TxType.billPayment;
      if (mode == PaymentMode.creditCard) return TxType.creditCardPayment;
      if (mode == PaymentMode.debitCard) return TxType.debitCardPayment;
    }
    switch (mode) {
      case PaymentMode.upi:
        return dir == TxDirection.inflow ? TxType.credit : TxType.upiPayment;
      case PaymentMode.neft:
        return TxType.neft;
      case PaymentMode.imps:
        return TxType.imps;
      case PaymentMode.rtgs:
        return TxType.rtgs;
      default:
        return dir == TxDirection.inflow ? TxType.credit : TxType.debit;
    }
  }

  String? _extractGenericRef(String text) {
    for (final m in _genericRef.allMatches(text)) {
      final v = m.group(1)!;
      if (RegExp(r'\d').hasMatch(v) && !RegExp(r'^x+\d+$', caseSensitive: false).hasMatch(v)) return v;
    }
    return null;
  }

  String? _normalizeRef(String? ref) {
    if (ref == null) return null;
    final r = ref.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return r.length >= 6 ? r : null;
  }

  ({DateTime date, bool explicitDate, bool explicitTime}) _extractDate(String text, String? templateDate, DateTime receivedAt) {
    DateTime? date;
    final candidates = <String>[?templateDate, text];
    for (final c in candidates) {
      date = _parseDate(c, receivedAt);
      if (date != null) break;
    }
    final timeMatch = _time.firstMatch(text);
    var hasTime = false;
    if (date != null && timeMatch != null) {
      var h = int.parse(timeMatch.group(1)!);
      final min = int.parse(timeMatch.group(2)!);
      final s = int.tryParse(timeMatch.group(3) ?? '') ?? 0;
      final ampm = timeMatch.group(4)?.toLowerCase();
      if (ampm == 'pm' && h < 12) h += 12;
      if (ampm == 'am' && h == 12) h = 0;
      date = DateTime(date.year, date.month, date.day, h, min, s);
      hasTime = true;
    }
    // Validate: a bank date cannot be meaningfully after the message arrived,
    // nor absurdly old. Fall back to arrival time if implausible.
    if (date != null) {
      final latest = receivedAt.add(const Duration(days: 1));
      final earliest = receivedAt.subtract(const Duration(days: 400));
      if (date.isAfter(latest) || date.isBefore(earliest)) date = null;
    }
    if (date == null) return (date: receivedAt, explicitDate: false, explicitTime: false);
    if (!hasTime) {
      // Keep the bank date; borrow arrival time only when it's the same day.
      final sameDay = date.year == receivedAt.year && date.month == receivedAt.month && date.day == receivedAt.day;
      date = sameDay ? receivedAt : DateTime(date.year, date.month, date.day, 12);
    }
    return (date: date, explicitDate: true, explicitTime: hasTime);
  }

  DateTime? _parseDate(String s, DateTime ref) {
    final iso = _dateIso.firstMatch(s);
    if (iso != null) {
      return _safeDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }
    final named = _dateMonthName.firstMatch(s);
    if (named != null) {
      final d = int.parse(named.group(1)!);
      final m = _months[named.group(2)!.toLowerCase().substring(0, 3)]!;
      final yRaw = named.group(3);
      var y = yRaw == null ? ref.year : _fullYear(int.parse(yRaw));
      var dt = _safeDate(y, m, d);
      if (yRaw == null && dt != null && dt.isAfter(ref.add(const Duration(days: 1)))) {
        y -= 1;
        dt = _safeDate(y, m, d);
      }
      return dt;
    }
    final num = _dateNumeric.firstMatch(s);
    if (num != null) {
      // Indian banks use dd-mm-yyyy.
      return _safeDate(_fullYear(int.parse(num.group(3)!)), int.parse(num.group(2)!), int.parse(num.group(1)!));
    }
    return null;
  }

  int _fullYear(int y) => y < 100 ? 2000 + y : y;

  DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null;
  }

  String? _extractCounterparty(String text, String? upiId) {
    final upiNarr = _upiNarration.firstMatch(text);
    if (upiNarr != null) {
      final name = _cleanName(upiNarr.group(2));
      if (name != null) return name;
    }
    for (final p in _merchantPatterns) {
      for (final m in p.allMatches(text)) {
        final name = _cleanName(m.group(1));
        if (name != null) return name;
      }
    }
    if (upiId != null) {
      final handle = upiId.split('@').first;
      if (!RegExp(r'^\d+$').hasMatch(handle)) return _titleCase(handle.replaceAll(RegExp(r'[._\-]'), ' '));
    }
    return null;
  }

  String? _cleanName(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.contains('@')) {
      final handle = s.split('@').first;
      if (RegExp(r'^\d+$').hasMatch(handle)) return null;
      s = handle.replaceAll(RegExp(r'[._\-]'), ' ');
    }
    s = s
        .replaceAll(RegExp(r'\b(a/c|acct|account)\b.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(on|via|ref|upi|vpa|your)\b.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[*_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    s = s.replaceAll(RegExp(r'^[\-.,:\s]+|[\-.,:\s]+$'), '');
    if (s.length < 2 || _nonMerchantWords.hasMatch(s) || RegExp(r'^[x\d\s]+$', caseSensitive: false).hasMatch(s)) {
      return null;
    }
    return _titleCase(s);
  }

  String _titleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 3 && w.toUpperCase() == w && RegExp(r'[A-Z]').hasMatch(w)
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  String _cleanEmail(RawMessage m) {
    var body = m.body
        .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</tr>|</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&#8377;', '₹')
        .replaceAll('&#x20B9;', '₹')
        .replaceAll('&rsquo;', "'")
        .replaceAll(RegExp(r'&#?\w+;'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n');
    if (body.length > 4000) body = body.substring(0, 4000);
    return '${m.subject ?? ''}\n$body'.trim();
  }

  /// Keeps a short, privacy-safe excerpt: long digit runs that are not the
  /// reference number are masked.
  String _sanitizeNarration(String text, String? ref) {
    final firstLines = text.split('\n').where((l) => l.trim().isNotEmpty).take(3).join(' ');
    var s = firstLines.replaceAllMapped(RegExp(r'\d{8,}'), (m) {
      final v = m.group(0)!;
      if (ref != null && v == ref) return v;
      return 'XX${v.substring(v.length - 4)}';
    });
    if (s.length > 200) s = '${s.substring(0, 197)}...';
    return s;
  }

  String _normalizedNarration(TxType? type, TxDirection? dir, String? cp, PaymentMode mode, String? bank) {
    final label = type?.label ?? (dir == TxDirection.inflow ? 'Money credited' : 'Money debited');
    final prep = dir == TxDirection.inflow ? 'from' : (mode == PaymentMode.debitCard || mode == PaymentMode.creditCard ? 'at' : 'to');
    // "Credit card payment at X" already names the card; skip " via Credit Card".
    final cardLabel = type == TxType.creditCardPayment || type == TxType.debitCardPayment;
    final via = mode == PaymentMode.other || (cardLabel && cp != null) ? '' : ' via ${mode.label}';
    if (cp != null) return '$label $prep $cp$via';
    if (bank != null) return '$label • $bank$via';
    return '$label$via';
  }
}

class _TemplateHit {
  _TemplateHit(this.match, String? dir)
      : direction = switch (dir) {
          'inflow' => TxDirection.inflow,
          'outflow' => TxDirection.outflow,
          _ => null,
        };
  final RegExpMatch match;
  final TxDirection? direction;

  String? group(String name) => match.groupNames.contains(name) ? match.namedGroup(name) : null;
}
