import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/core/utils/app_clock.dart';
import 'package:smart_spend_tracker/features/cards/domain/card_cycle.dart';
import 'package:smart_spend_tracker/features/cards/domain/credit_card.dart';
import 'package:smart_spend_tracker/features/cards/presentation/credit_card_widgets.dart';

void main() {
  setUpAll(AppClock.init);
  const card = CreditCard(id: 'a', workspaceId: 'w', issuer: 'ICICI Bank', last4: '8003', creditLimit: 100000, availableLimit: 91994.08, statementDay: 23, dueDay: 3);
  final paid = CardCycle(cycleStart: DateTime(2026, 10, 24), nextStatement: DateTime(2026, 11, 23), cycleSpent: 4321, state: StatementState.paid, paidTowardsStatement: 23000.54, statementTotal: 23000.54, nextDueDate: DateTime(2026, 12, 3), statementDay: 23, dueDay: 3);
  final due = CardCycle(cycleStart: DateTime(2026, 10, 24), nextStatement: DateTime(2026, 11, 23), cycleSpent: 4321, state: StatementState.overdue, paidTowardsStatement: 0, statementTotal: 23000.54, statementDueDate: DateTime(2026, 11, 3), nextDueDate: DateTime(2026, 11, 3), statementDay: 23, dueDay: 3);

  for (final screen in [320.0, 360.0, 393.0, 412.0]) {
    for (final (name, cycle) in [('paid', paid), ('due', due)]) {
      testWidgets('card tile fits at ${screen.toInt()}dp ($name), text scale 1.1', (t) async {
        t.view.physicalSize = Size(screen, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.1)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (_, c) => SizedBox(width: c.maxWidth * 0.88 - 12, child: CreditCardVisual(card: card, cycle: cycle)),
                ),
              ),
            ),
          ),
        ));
        expect(t.takeException(), isNull);
      });
    }
  }
}
