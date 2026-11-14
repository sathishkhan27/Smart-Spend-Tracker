import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../data/credit_card_repository.dart';
import '../domain/card_cycle.dart';

/// Billing-cycle view of every card (cycle spend, statement status, next due),
/// keyed by card id. Recomputed when cards or this month's transactions change.
final cardCyclesProvider = FutureProvider<Map<String, CardCycle>>((ref) async {
  final cards = await ref.watch(creditCardsProvider.future);
  final wid = ref.watch(activeWorkspaceIdProvider);
  if (cards.isEmpty || wid == null) return const {};
  final now = AppClock.now();
  // Re-run when new transactions arrive (this month's stream emits on change).
  ref.watch(periodTransactionsProvider(DateRangePeriod.month(now.year, now.month)));

  final utcNow = DateTime.now().toUtc();
  final txs = await ref.read(transactionRepositoryProvider).candidatesBetween(wid, utcNow.subtract(const Duration(days: 125)), utcNow.add(const Duration(days: 1)));

  bool onAnyCard(t) => cards.any((c) => CreditCardRepository.belongsToCard(t, c));
  final unattributed = CardCycle.unattributedBillPayments(txs, onAnyCard: onAnyCard);
  final used = <CardPayment>{};

  final out = <String, CardCycle>{};
  for (final card in cards) {
    bool onCard(t) => CreditCardRepository.belongsToCard(t, card);
    final cardTxs = txs.where(onCard).toList();
    var payments = CardCycle.dedupe([
      ...CardCycle.paymentsFrom(card, txs, onCard: onCard),
      if (card.lastPaymentAmount != null && card.lastPaymentAt != null)
        CardPayment(card.lastPaymentAmount!, () {
          final d = AppClock.toLocal(card.lastPaymentAt!);
          return DateTime(d.year, d.month, d.day);
        }()),
    ]);
    var cycle = CardCycle.compute(card: card, cardTransactions: cardTxs, payments: payments, now: now);
    // e.g. "Paid to CRED" for exactly this statement's amount.
    final hints = [
      for (final h in card.paymentHints)
        CardPayment(h.amount, () {
          final d = AppClock.toLocal(h.at);
          return DateTime(d.year, d.month, d.day);
        }()),
    ];
    final extra = CardCycle.matchUnattributed(cycle, [...hints, ...unattributed.where((p) => !used.contains(p))]);
    if (extra != null) {
      used.add(extra);
      payments = CardCycle.dedupe([...payments, extra]);
      cycle = CardCycle.compute(card: card, cardTransactions: cardTxs, payments: payments, now: now);
    }
    out[card.id] = cycle;
  }
  return out;
});
