import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import 'card_providers.dart';
import 'credit_card_widgets.dart';

/// Home: swipeable credit cards with totals. Hidden until a card is detected.
class CreditCardsSection extends ConsumerStatefulWidget {
  const CreditCardsSection({super.key});

  @override
  ConsumerState<CreditCardsSection> createState() => _CreditCardsSectionState();
}

class _CreditCardsSectionState extends ConsumerState<CreditCardsSection> {
  final _page = PageController(viewportFraction: 0.88);
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(creditCardsProvider).value ?? const [];
    if (cards.isEmpty) return const SizedBox.shrink();
    final cycles = ref.watch(cardCyclesProvider).value ?? const {};
    // Pending = unpaid part of each card's latest statement.
    final totalDue = cards.fold<double>(0, (s, c) {
      final cy = cycles[c.id];
      return s + (cy == null ? c.pendingDue : (cy.state.owing ? cy.remaining : 0));
    });
    final available = cards.where((c) => c.availableLimit != null).fold<double>(0, (s, c) => s + c.availableLimit!);
    final anyAvailable = cards.any((c) => c.availableLimit != null);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      SectionHeader(
        'Credit cards',
        subtitle: '${cards.length} card${cards.length == 1 ? '' : 's'} • tap a card for details',
      ),
      LayoutBuilder(builder: (context, c) {
        final cardWidth = c.maxWidth * 0.88 - 12;
        return SizedBox(
          height: cardWidth / 1.586 + 24, // room for the shadow
          child: PageView.builder(
            controller: _page,
            padEnds: false,
            clipBehavior: Clip.none,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 24),
              child: CreditCardVisual(card: cards[i], cycle: cycles[cards[i].id], onTap: () => context.push(Routes.card(cards[i].id))),
            ),
          ),
        );
      }),
      if (cards.length > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < cards.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _index ? AppColors.blue : AppColors.blue.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _Total(
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.income,
            label: 'Available limit',
            value: anyAvailable ? Fmt.money(available) : 'Not known yet',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Total(
            icon: Icons.receipt_long_outlined,
            color: totalDue > 0 ? AppColors.expense : AppColors.income,
            label: 'Pending due',
            value: totalDue > 0 ? Fmt.money(totalDue) : 'Nothing due',
          ),
        ),
      ]),
    ]);
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: context.text.labelSmall?.copyWith(color: context.secondaryText)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
      );
}
