import '../../transactions/domain/category.dart';
import '../../transactions/domain/engines/raw_message.dart';
import '../../transactions/domain/engines/transaction_parser.dart';
import 'recurring_expense.dart';

enum DueKind { emi, creditCard, insurance, bill }

/// A payment the bank says is coming up ("EMI of Rs 5,250 is due on 05-12-26").
/// Not a transaction: it becomes an entry on the Upcoming page.
class DueReminder {
  const DueReminder({
    required this.kind,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.key,
    required this.categoryId,
    this.currency = 'INR',
    this.institution,
    this.maskedAccount,
  });

  final DueKind kind;
  final String title;
  final double amount;
  final String currency;

  /// Wall-clock date (workspace timezone), midnight.
  final DateTime dueDate;
  final String? institution;
  final String? maskedAccount;
  final String categoryId;

  /// Stable identity of the obligation (kind + lender + account), so every
  /// month's reminder updates the same Upcoming entry.
  final String key;

  RecurrenceFrequency get frequency => kind == DueKind.insurance ? RecurrenceFrequency.yearly : RecurrenceFrequency.monthly;
}

/// Reads due / auto-debit reminders from SMS and email.
class DueReminderParser {
  DueReminderParser({TransactionParser? parser}) : _parser = parser ?? TransactionParser();
  final TransactionParser _parser;

  static final _cue = RegExp(
      r'(\bis due\b|\bdue on\b|\bdue by\b|\bdue date\b|payment due|amount due|\bdue for\b|will be (?:auto[\s-]?)?debited|is scheduled|scheduled (?:for|on)|\bpresent(?:ed|ation)\b.*\b(?:nach|ecs|mandate)\b|\bmandate\b.*\bon\b|auto[\s-]?debit (?:of|on|for))',
      caseSensitive: false);

  /// Phrases that confirm a completed payment (handled as a transaction instead).
  static final _done = RegExp(
      r'\b(has been debited|is debited|was debited|debited from|debited by|debited with|has been credited|credited to|successfully paid|has been paid|payment (?:of .{1,30} )?(?:is )?received|received (?:your )?payment|thank you for (?:your )?payment|paid successfully|is successful)\b',
      caseSensitive: false);
  static final _promo = RegExp(r'(pre[\s-]?approved|apply now|get up ?to|eligible for|emi starting|lowest interest|offer|t&c)', caseSensitive: false);

  static final _emi = RegExp(r'\b(emi|loan|instal?ment|nach|ecs|mandate)\b', caseSensitive: false);
  static final _card = RegExp(r'(credit card|card ending|card no|card xx|total amount due|total due|minimum amount due|min(?:imum)? due|statement)', caseSensitive: false);
  static final _insurance = RegExp(r'\b(premium|policy|insurance|lic)\b', caseSensitive: false);
  static final _bill = RegExp(r'\b(bill|electricity|broadband|postpaid|recharge|gas|water|dth|fastag)\b', caseSensitive: false);

  static final _amount = RegExp(r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false);
  static final _account = RegExp(
      r'\b(?:loan\s*)?(?:a/c|acct|account|ac|card|loan)\s*(?:no\.?|number|ending(?:\s+(?:with|in))?)?\s*[:\-]?\s*[xX*\.]*\s*(\d{3,6})\b',
      caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _dNum = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');
  static final _dIso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  static final _dDayMon = RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-/]*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?[\s\-/,]*(\d{2,4})?\b', caseSensitive: false);
  static final _dMonDay = RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{4})?\b', caseSensitive: false);

  DueReminder? parse(RawMessage m) {
    final text = [m.subject, m.body].whereType<String>().join(' \n ');
    final cue = _cue.firstMatch(text);
    if (cue == null) return null;
    final withoutFuture = text.replaceAll(RegExp(r'will be (?:auto[\s-]?)?debited', caseSensitive: false), '');
    if (_done.hasMatch(withoutFuture)) return null;
    if (_promo.hasMatch(text)) return null;

    final kind = _card.hasMatch(text)
        ? DueKind.creditCard
        : _emi.hasMatch(text)
            ? DueKind.emi
            : _insurance.hasMatch(text)
                ? DueKind.insurance
                : _bill.hasMatch(text)
                    ? DueKind.bill
                    : null;
    if (kind == null) return null;

    final amount = _pickAmount(text, kind);
    if (amount == null || amount <= 0) return null;
    final due = _pickDate(text, cue.start, m.receivedAt);
    if (due == null) return null;

    final acct = _account.firstMatch(text)?.group(1);
    final last4 = acct == null ? null : (acct.length > 4 ? acct.substring(acct.length - 4) : acct);
    final institution = _parser.institutionFor(m)?.name;

    final lower = text.toLowerCase();
    final (title, categoryId) = switch (kind) {
      DueKind.emi => ('${institution ?? 'Loan'} EMI', Categories.loanEmi.id),
      DueKind.creditCard => ('${institution ?? 'Credit card'} card bill', Categories.creditCardPayment.id),
      DueKind.insurance => ('${institution ?? 'Insurance'} premium', Categories.insurance.id),
      DueKind.bill => lower.contains('electric')
          ? ('Electricity bill', Categories.electricity.id)
          : lower.contains('broadband') || lower.contains('internet')
              ? ('Internet bill', Categories.internet.id)
              : lower.contains('postpaid') || lower.contains('recharge') || lower.contains('mobile')
                  ? ('Mobile bill', Categories.mobile.id)
                  : ('${institution ?? 'Utility'} bill', Categories.others.id),
    };

    final slug = (institution ?? m.senderName ?? m.sender).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    final key = '${kind.name}_${slug.isEmpty ? 'x' : slug}_${last4 ?? 'na'}';

    return DueReminder(
      kind: kind,
      title: last4 == null ? title : '$title ••$last4',
      amount: amount,
      dueDate: due,
      key: key,
      categoryId: categoryId,
      institution: institution,
      maskedAccount: last4 == null ? null : 'XX$last4',
    );
  }

  /// Picks the payable amount, skipping balances, limits and (for cards) the minimum due.
  double? _pickAmount(String text, DueKind kind) {
    final lower = text.toLowerCase();
    if (kind == DueKind.creditCard) {
      final total = RegExp(r'total (?:amount )?due[^0-9₹]{0,20}(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false).firstMatch(text);
      if (total != null) return _num(total.group(1)!);
    }
    if (kind == DueKind.emi) {
      final emi = RegExp(r'(?:emi|instal?ment)(?: amount)?(?: of)?[^0-9₹]{0,12}(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false)
          .firstMatch(text);
      if (emi != null) return _num(emi.group(1)!);
    }
    for (final a in _amount.allMatches(text)) {
      final before = lower.substring((a.start - 28).clamp(0, a.start), a.start);
      if (RegExp(r'\b(bal|balance|available|avl|limit|outstanding|principal|min(?:imum)?(?: amount)? due)\b[\s:.a-z]{0,12}$').hasMatch(before)) continue;
      return _num(a.group(1)!);
    }
    return null;
  }

  double? _num(String s) => double.tryParse(s.replaceAll(',', ''));

  /// The due date: the first date after the reminder cue, else any date in
  /// the message. A date without a year is the next one on/after receipt.
  DateTime? _pickDate(String text, int cueAt, DateTime receivedAt) {
    final after = text.substring((cueAt - 5).clamp(0, text.length));
    return _date(after, receivedAt) ?? _date(text, receivedAt);
  }

  DateTime? _date(String s, DateTime ref) {
    final iso = _dIso.firstMatch(s);
    if (iso != null) return _safe(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    final dm = _dDayMon.firstMatch(s);
    if (dm != null) return _withYear(int.parse(dm.group(1)!), _months[dm.group(2)!.toLowerCase().substring(0, 3)]!, dm.group(3), ref);
    final md = _dMonDay.firstMatch(s);
    if (md != null) return _withYear(int.parse(md.group(2)!), _months[md.group(1)!.toLowerCase().substring(0, 3)]!, md.group(3), ref);
    final n = _dNum.firstMatch(s);
    if (n != null) {
      final y = int.parse(n.group(3)!);
      return _safe(y < 100 ? 2000 + y : y, int.parse(n.group(2)!), int.parse(n.group(1)!)); // dd-mm-yyyy
    }
    return null;
  }

  DateTime? _withYear(int d, int mo, String? yRaw, DateTime ref) {
    if (yRaw != null) {
      final y = int.parse(yRaw);
      return _safe(y < 100 ? 2000 + y : y, mo, d);
    }
    var dt = _safe(ref.year, mo, d);
    // Due dates are in the future; "05 Jan" received in December means next year.
    if (dt != null && dt.isBefore(DateTime(ref.year, ref.month, ref.day).subtract(const Duration(days: 15)))) {
      dt = _safe(ref.year + 1, mo, d);
    }
    return dt;
  }

  DateTime? _safe(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null;
  }
}
