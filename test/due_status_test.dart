import 'package:flutter_test/flutter_test.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/due_status.dart';
import 'package:smart_spend_tracker/features/upcoming/domain/recurring_expense.dart';

RecurringExpense _r(DateTime due) => RecurringExpense(
      id: 'r',
      workspaceId: 'w',
      name: 'Rent',
      expectedAmount: 15000,
      frequency: RecurrenceFrequency.monthly,
      nextDueDate: due,
      categoryId: 'rent',
      status: RecurringStatus.active,
      createdBy: 'u',
    );

void main() {
  final now = DateTime(2026, 11, 13, 9);

  test('levels for 2 days, 1 day, today and overdue', () {
    expect(DueStatus.of(DateTime(2026, 11, 15), now).level, DueLevel.twoDays);
    expect(DueStatus.of(DateTime(2026, 11, 14), now).level, DueLevel.tomorrow);
    expect(DueStatus.of(DateTime(2026, 11, 13), now).level, DueLevel.today);
    expect(DueStatus.of(DateTime(2026, 11, 11), now).label, 'Overdue 2d');
    expect(DueStatus.of(DateTime(2026, 11, 20), now).level.isAlert, isFalse);
  });

  test('unpaid due stays overdue within grace, then rolls forward', () {
    expect(_r(DateTime(2026, 11, 10)).currentDue(now), DateTime(2026, 11, 10));
    expect(_r(DateTime(2026, 11, 10)).dueStatus(now).level, DueLevel.overdue);
    // 13 days late: treated as missed, next month's due is shown.
    expect(_r(DateTime(2026, 10, 31)).currentDue(now), DateTime(2026, 11, 30));
  });
}
