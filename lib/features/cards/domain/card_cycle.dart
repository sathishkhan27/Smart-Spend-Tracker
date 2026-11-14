import '../../../core/utils/app_clock.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import 'credit_card.dart';

enum StatementState {
  /// No statement amount (nothing billed / not known yet).
  none,
  paid,

  /// At least the minimum is paid, balance still open.
  partial,
  due,
  overdue,

  /// Amount worked out from card spends (no statement SMS) and no payment
  /// seen: we can't tell whether it's paid, so don't flag it as due.
  unconfirmed;

  bool get settled => this == none || this == paid;

  /// Counts towards "Pending due".
  bool get owing => this == due || this == overdue || this == partial;
}

/// A payment towards the card bill (issuer SMS or bank-side debit).
class CardPayment {
  const CardPayment(this.amount, this.date);
  final double amount;
  final DateTime date; // wall-clock

  @override
  String toString() => 'CardPayment($amount, $date)';
}

/// Everything the card UI shows, computed from the billing cycle:
/// current cycle spend, the last statement and whether it's paid, next due.
class CardCycle {
  const CardCycle({
    required this.cycleStart,
    required this.nextStatement,
    required this.cycleSpent,
    required this.state,
    required this.paidTowardsStatement,
    this.lastStatementDate,
    this.statementTotal,
    this.statementEstimated = false,
    this.minDue,
    this.statementDueDate,
    this.nextDueDate,
    this.lastPayment,
    this.statementDay,
    this.dueDay,
    this.countedPayments = const [],
  });

  /// Payments counted towards the statement shown (after its date).
  final List<CardPayment> countedPayments;

  final DateTime cycleStart;
  final DateTime nextStatement;
  final double cycleSpent;

  final DateTime? lastStatementDate;
  final double? statementTotal;

  /// Total worked out from card transactions (no statement SMS for it).
  final bool statementEstimated;
  final double? minDue;
  final DateTime? statementDueDate;
  final double paidTowardsStatement;
  final StatementState state;

  /// Due date to show next: the open statement's, or the upcoming one once paid.
  final DateTime? nextDueDate;
  final CardPayment? lastPayment;
  final int? statementDay;
  final int? dueDay;

  double get remaining {
    final t = statementTotal ?? 0;
    return (t - paidTowardsStatement).clamp(0, t).toDouble();
  }

  bool get cycleKnown => statementDay != null;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _onDay(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > last ? last : day);
  }

  /// Latest date on [day]-of-month that is on/before [ref].
  static DateTime lastOnOrBefore(int day, DateTime ref) {
    final r = _day(ref);
    final thisMonth = _onDay(r.year, r.month, day);
    return thisMonth.isAfter(r) ? _onDay(r.year, r.month - 1, day) : thisMonth;
  }

  /// First date on [day]-of-month that is strictly after [ref].
  static DateTime firstAfter(int day, DateTime ref) {
    final r = _day(ref);
    final thisMonth = _onDay(r.year, r.month, day);
    return thisMonth.isAfter(r) ? thisMonth : _onDay(r.year, r.month + 1, day);
  }

  factory CardCycle.compute({
    required CreditCard card,
    required List<FinancialTransaction> cardTransactions,
    required List<CardPayment> payments,
    required DateTime now,
  }) {
    final today = _day(now);
    final statementDay = card.statementDay ?? (card.statementAt == null ? null : AppClock.toLocal(card.statementAt!).day);
    final dueDay = card.dueDay ?? card.dueDate?.day;

    DateTime local(FinancialTransaction t) => _day(AppClock.toLocal(t.transactionDate));
    double spentBetween(DateTime from, DateTime toInclusive) {
      var s = 0.0;
      for (final t in cardTransactions) {
        if (t.status != TxStatus.success) continue;
        final d = local(t);
        if (d.isBefore(from) || d.isAfter(toInclusive)) continue;
        if (_isBillPayment(t)) continue; // paying the bill isn't spending
        s += t.isInflow ? -t.amount : t.amount; // refunds reduce spend
      }
      return s < 0 ? 0 : s;
    }

    final sortedPayments = [...payments]..sort((a, b) => b.date.compareTo(a.date));
    final lastPayment = sortedPayments.isEmpty ? null : sortedPayments.first;

    if (statementDay == null) {
      // No cycle yet: show the last 30 days and whatever the statement SMS said.
      final start = today.subtract(const Duration(days: 30));
      final paid = card.statementAt == null
          ? 0.0
          : payments.where((p) => !p.date.isBefore(_day(AppClock.toLocal(card.statementAt!)))).fold<double>(0, (s, p) => s + p.amount);
      final total = card.totalDue;
      return CardCycle(
        cycleStart: start,
        nextStatement: today,
        cycleSpent: spentBetween(start, today),
        lastStatementDate: card.statementAt == null ? null : _day(AppClock.toLocal(card.statementAt!)),
        statementTotal: total,
        minDue: card.minDue,
        statementDueDate: card.dueDate,
        paidTowardsStatement: paid,
        state: _state(total, card.minDue, paid, card.dueDate, today),
        nextDueDate: card.dueDate,
        lastPayment: lastPayment,
        dueDay: dueDay,
      );
    }

    var lastStatement = lastOnOrBefore(statementDay, today);
    var prevStatement = lastOnOrBefore(statementDay, lastStatement.subtract(const Duration(days: 1)));
    final smsDay = card.statementAt == null ? null : _day(AppClock.toLocal(card.statementAt!));
    // Statement date today/yesterday but its SMS hasn't arrived yet: keep
    // showing the last statement we have an SMS for (don't estimate ₹0).
    if (smsDay != null && today.difference(lastStatement).inDays <= 2 && smsDay.difference(lastStatement).inDays.abs() > 6 && smsDay.difference(prevStatement).inDays.abs() <= 6) {
      lastStatement = prevStatement;
      prevStatement = lastOnOrBefore(statementDay, lastStatement.subtract(const Duration(days: 1)));
    }
    final cycleStart = lastStatement.add(const Duration(days: 1));
    final nextStatement = firstAfter(statementDay, today);

    DateTime dueAfter(DateTime statement) {
      if (dueDay != null) return firstAfter(dueDay, statement);
      return statement.add(const Duration(days: 20)); // typical grace period
    }

    // Statement amount: the issuer's SMS for this statement, else estimate it
    // from card spends in that billing cycle.
    final smsStatement = card.statementAt == null ? null : _day(AppClock.toLocal(card.statementAt!));
    final smsMatches = smsStatement != null && smsStatement.difference(lastStatement).inDays.abs() <= 6 && card.totalDue != null;
    final total = smsMatches ? card.totalDue : spentBetween(prevStatement.add(const Duration(days: 1)), lastStatement);
    final minDue = smsMatches ? card.minDue : null;
    final statementDue = smsMatches && card.dueDate != null ? card.dueDate! : dueAfter(lastStatement);

    final counted = payments.where((p) => p.date.isAfter(lastStatement)).toList();
    final paid = counted.fold<double>(0, (s, p) => s + p.amount);
    var state = _state(total, minDue, paid, statementDue, today);
    if (!smsMatches && (state == StatementState.due || state == StatementState.overdue)) state = StatementState.unconfirmed;

    return CardCycle(
      cycleStart: cycleStart,
      nextStatement: nextStatement,
      cycleSpent: spentBetween(cycleStart, today),
      lastStatementDate: lastStatement,
      statementTotal: total,
      statementEstimated: !smsMatches,
      minDue: minDue,
      statementDueDate: statementDue,
      paidTowardsStatement: paid,
      state: state,
      // Once paid, the next due belongs to the statement after the one shown.
      nextDueDate: state.settled ? dueAfter(firstAfter(statementDay, lastStatement)) : statementDue,
      lastPayment: lastPayment,
      statementDay: statementDay,
      dueDay: dueDay,
      countedPayments: counted,
    );
  }

  static StatementState _state(double? total, double? minDue, double paid, DateTime? due, DateTime today) {
    if (total == null || total < 1) return StatementState.none;
    if (paid >= total - 1) return StatementState.paid;
    if (minDue != null && minDue > 0 && paid >= minDue - 1) return StatementState.partial;
    if (due != null && today.isAfter(due)) return StatementState.overdue;
    return StatementState.due;
  }

  static final _billWords = RegExp(r'(credit\s*card|\bcc\b|card\s*(?:bill|payment|dues)|\bcred\b|billdesk|card\s*a/?c|towards\s+your\s+card)', caseSensitive: false);

  /// A bill payment (card account credited by the user's payment), as
  /// opposed to a purchase or a merchant refund.
  static bool _isBillPayment(FinancialTransaction t) =>
      t.transactionType == TxType.creditCardBillPayment ||
      (t.isInflow && RegExp(r'payment\s*(?:received|credited|successful)|received.*payment|thank you for (?:the |your )?payment', caseSensitive: false)
          .hasMatch([t.counterparty, t.narration].whereType<String>().join(' ')));

  /// Payments towards [card] found among transactions: a "payment received"
  /// credit on the card itself, or a bill payment debited from a bank account
  /// that names this card (last digits) or its issuer.
  static List<CardPayment> paymentsFrom(CreditCard card, Iterable<FinancialTransaction> all, {required bool Function(FinancialTransaction) onCard}) {
    final out = <CardPayment>[];
    final issuer = card.issuer.toLowerCase().split(RegExp(r'\s+')).first;
    for (final t in all) {
      if (t.status != TxStatus.success) continue;
      final text = [t.counterparty, t.merchant, t.narration].whereType<String>().join(' ');
      final d = _day(AppClock.toLocal(t.transactionDate));
      // Credit on the card account itself = payment received.
      if (t.isInflow && onCard(t) && (t.transactionType == TxType.creditCardBillPayment || RegExp(r'payment', caseSensitive: false).hasMatch(text))) {
        out.add(CardPayment(t.amount, d));
        continue;
      }
      // Bank-side debit paying the card bill.
      if (!t.isInflow && !onCard(t)) {
        final billLike = t.categoryId == 'credit_card_payment' || t.transactionType == TxType.creditCardBillPayment || _billWords.hasMatch(text);
        if (!billLike) continue;
        final namesCard = RegExp('(?<![0-9])${card.last4}(?![0-9])').hasMatch(text);
        final namesIssuer = issuer.length >= 3 && text.toLowerCase().contains(issuer);
        if (namesCard || namesIssuer) out.add(CardPayment(t.amount, d));
      }
    }
    return out;
  }

  /// Bill payments that don't say which card they were for ("Paid to CRED").
  static List<CardPayment> unattributedBillPayments(Iterable<FinancialTransaction> all, {required bool Function(FinancialTransaction) onAnyCard}) => [
        for (final t in all)
          if (!t.isInflow &&
              t.status == TxStatus.success &&
              !onAnyCard(t) &&
              (t.categoryId == 'credit_card_payment' || t.transactionType == TxType.creditCardBillPayment ||
                  _billWords.hasMatch([t.counterparty, t.merchant, t.narration].whereType<String>().join(' '))) &&
              !RegExp(r'(?<![0-9])[0-9]{4}(?![0-9])').hasMatch([t.counterparty, t.narration].whereType<String>().join(' ')))
            CardPayment(t.amount, _day(AppClock.toLocal(t.transactionDate))),
      ];

  /// An unattributed payment of the statement amount (±₹1), made after the
  /// statement, settles that statement.
  static CardPayment? matchUnattributed(CardCycle cycle, List<CardPayment> candidates) {
    final total = cycle.statementTotal, stmt = cycle.lastStatementDate;
    if (total == null || stmt == null || cycle.state.settled) return null;
    for (final p in candidates) {
      if (p.date.isAfter(stmt) && ((p.amount - total).abs() <= 1 || (p.amount - cycle.remaining).abs() <= 1)) return p;
    }
    return null;
  }

  /// Merges payments from several sources; the same payment seen as an issuer
  /// SMS and as a bank debit (same amount within 3 days) is counted once.
  static List<CardPayment> dedupe(List<CardPayment> payments) {
    final sorted = [...payments]..sort((a, b) => a.date.compareTo(b.date));
    final out = <CardPayment>[];
    for (final p in sorted) {
      final dup = out.any((q) => (q.amount - p.amount).abs() <= 1 && q.date.difference(p.date).inDays.abs() <= 3);
      if (!dup) out.add(p);
    }
    return out;
  }
}
