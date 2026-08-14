import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:my_finance_app/features/transaction/taiwan_business_calendar.dart';

void main() {
  const calendar = TaiwanBusinessCalendar.bundled();

  test('T+2 skips Mid-Autumn weekend and Teachers Day substitute holiday', () {
    final result = DebitCardSettlementPlanner.addBusinessDays(
      DateTime.utc(2026, 9, 24, 15, 30),
      2,
      businessCalendar: calendar,
    );

    expect(result, DateTime.utc(2026, 9, 30, 15, 30));
  });

  test('T+2 skips National Day substitute holiday and weekend', () {
    final result = DebitCardSettlementPlanner.addBusinessDays(
      DateTime.utc(2026, 10, 8, 9),
      2,
      businessCalendar: calendar,
    );

    expect(result, DateTime.utc(2026, 10, 13, 9));
  });

  test('T+2 crosses year boundary and skips New Year holiday', () {
    final result = DebitCardSettlementPlanner.addBusinessDays(
      DateTime.utc(2026, 12, 30, 8),
      2,
      businessCalendar: calendar,
    );

    expect(result, DateTime.utc(2027, 1, 4, 8));
  });

  test('2027 Lunar New Year weekdays are not business days', () {
    for (final day in <int>[4, 5, 8, 9, 10]) {
      expect(calendar.isBusinessDay(DateTime(2027, 2, day)), isFalse);
    }
    expect(calendar.isBusinessDay(DateTime(2027, 2, 11)), isTrue);
  });

  test('unsupported calendar range fails closed', () {
    expect(
      () => DebitCardSettlementPlanner.addBusinessDays(
        DateTime.utc(2027, 12, 31),
        2,
        businessCalendar: calendar,
      ),
      throwsA(isA<BusinessCalendarCoverageException>()),
    );
  });

  test('zero business days preserves timestamp inside coverage', () {
    final start = DateTime.utc(2026, 6, 29, 10, 45);
    expect(
      DebitCardSettlementPlanner.addBusinessDays(
        start,
        0,
        businessCalendar: calendar,
      ),
      start,
    );
  });
}
