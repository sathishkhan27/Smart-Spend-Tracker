/// A credit card tracked from its issuer's SMS / email alerts.
class CreditCard {
  const CreditCard({
    required this.id,
    required this.workspaceId,
    required this.issuer,
    required this.last4,
    this.creditLimit,
    this.availableLimit,
    this.availableAt,
    this.totalDue,
    this.minDue,
    this.dueDate,
    this.statementAt,
    this.lastPaymentAmount,
    this.lastPaymentAt,
    this.limitSetManually = false,
    this.statementDay,
    this.dueDay,
    this.paymentHints = const [],
    this.cycleSetManually = false,
    this.statementFromSms = false,
  });

  final String id;
  final String workspaceId;
  final String issuer;
  final String last4;

  final double? creditLimit;
  final double? availableLimit;
  final DateTime? availableAt;

  /// Latest statement.
  final double? totalDue;
  final double? minDue;
  final DateTime? dueDate;
  final DateTime? statementAt;

  final double? lastPaymentAmount;
  final DateTime? lastPaymentAt;
  final bool limitSetManually;

  /// Billing cycle (day of month), set by the user or read from statements.
  final int? statementDay;
  final int? dueDay;

  /// Probable bill payments that don't name the card (e.g. SBI "OTP to approve
  /// transaction of Rs X to ICICI Bank Credit card"). Count only when the
  /// amount matches a statement.
  final List<({double amount, DateTime at})> paymentHints;

  /// The billing cycle was entered by the user (SMS can't change it).
  final bool cycleSetManually;

  /// [statementAt] is a real "Statement is sent…" SMS (not inferred).
  final bool statementFromSms;

  /// Day the latest statement SMS arrived, when it disagrees with a manually
  /// set cycle by more than a day — the cycle was probably saved wrong.
  int? get cycleMismatchDay {
    final s = statementAt;
    if (!cycleSetManually || !statementFromSms || s == null || statementDay == null) return null;
    final smsDay = s.toLocal().day;
    final diff = (smsDay - statementDay!).abs();
    return (diff > 1 && diff < 27) ? smsDay : null; // 27+ = month wrap (e.g. 31st vs 1st)
  }

  String get maskedNumber => 'XX$last4';

  /// Amount used = limit − available (both from the bank), when known.
  double? get used {
    final l = creditLimit, a = availableLimit;
    if (l == null || a == null) return null;
    return (l - a).clamp(0, l).toDouble();
  }

  /// 0–1 share of the limit in use.
  double? get utilization {
    final l = creditLimit, u = used;
    if (l == null || u == null || l <= 0) return null;
    return (u / l).clamp(0, 1).toDouble();
  }

  /// The latest statement has been paid (a payment arrived after it).
  bool get statementPaid {
    final s = statementAt, p = lastPaymentAt;
    if (totalDue == null || totalDue! <= 0) return true;
    if (s == null || p == null || p.isBefore(s)) return false;
    return (lastPaymentAmount ?? 0) >= (minDue ?? totalDue!) * 0.99;
  }

  /// Amount still to pay for the latest statement (0 when paid / none).
  double get pendingDue => statementPaid ? 0 : (totalDue ?? 0);
}

/// What one message says about a card. Every field is optional; a sync
/// merges the newest value of each field into the stored card.
class CardSnapshot {
  const CardSnapshot({
    required this.issuer,
    required this.last4,
    required this.at,
    this.creditLimit,
    this.availableLimit,
    this.totalDue,
    this.minDue,
    this.dueDate,
    this.paymentAmount,
    this.isStatement = false,
    this.revisedTotalDue,
    this.revisedMinDue,
  });

  final String issuer;
  final String last4;

  /// When the message was received (newer values win).
  final DateTime at;
  final double? creditLimit;
  final double? availableLimit;
  final double? totalDue;
  final double? minDue;
  final DateTime? dueDate;
  final double? paymentAmount;

  /// A statement-generation message (sets the billing cycle). Payment
  /// reminders ("Pay Total Amount Due … by …") carry amounts but not the cycle.
  final bool isStatement;

  /// "Revised total due Rs …, minimum due Rs …" after a refund/reversal.
  final double? revisedTotalDue;
  final double? revisedMinDue;

  String get key => '${issuer.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '')}_$last4';

  bool get isEmpty => creditLimit == null && availableLimit == null && totalDue == null && paymentAmount == null && revisedTotalDue == null;
}

/// A probable card-bill payment seen from the paying bank, naming only the
/// issuer (no card number).
class BillPaymentHint {
  const BillPaymentHint({required this.issuer, required this.amount, required this.at});
  final String issuer;
  final double amount;
  final DateTime at;
}
