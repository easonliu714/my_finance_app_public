import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_redemption_window.dart';

void main() {
  InvoiceAwardRedemptionWindow window({
    required String periodId,
    required DateTime draw,
    required DateTime start,
    required DateTime end,
  }) => InvoiceAwardRedemptionWindow(
        periodId: periodId,
        drawDate: draw,
        redemptionStart: start,
        redemptionEnd: end,
      );

  test('distinguishes matchable from redeemable boundaries', () {
    final item = window(
      periodId: '115-05-06',
      draw: DateTime.utc(2026, 7, 25),
      start: DateTime.utc(2026, 8, 6),
      end: DateTime.utc(2026, 11, 5, 23, 59, 59),
    );

    expect(item.isMatchableAt(DateTime.utc(2026, 7, 24)), isFalse);
    expect(item.isMatchableAt(DateTime.utc(2026, 7, 25)), isTrue);
    expect(item.isRedeemableAt(DateTime.utc(2026, 8, 5)), isFalse);
    expect(item.isRedeemableAt(DateTime.utc(2026, 8, 6)), isTrue);
    expect(item.isRedeemableAt(DateTime.utc(2026, 11, 5, 23, 59, 59)), isTrue);
    expect(item.isRedeemableAt(DateTime.utc(2026, 11, 6)), isFalse);
    expect(item.canCreateFormalTransaction, isFalse);
  });

  test('fails closed for invalid or non-UTC authority', () {
    final invalid = window(
      periodId: '115-05-06',
      draw: DateTime.utc(2026, 7, 25),
      start: DateTime.utc(2026, 7, 24),
      end: DateTime.utc(2026, 11, 5),
    );
    expect(invalid.hasValidUtcBounds, isFalse);
    expect(invalid.isMatchableAt(DateTime.utc(2026, 8, 6)), isFalse);

    final valid = window(
      periodId: '115-05-06',
      draw: DateTime.utc(2026, 7, 25),
      start: DateTime.utc(2026, 8, 6),
      end: DateTime.utc(2026, 11, 5),
    );
    expect(valid.isMatchableAt(DateTime(2026, 8, 6)), isFalse);
    expect(valid.isRedeemableAt(DateTime(2026, 8, 6)), isFalse);
  });

  test('selection keeps newest matchable and every still-redeemable period', () {
    final older = window(
      periodId: '115-03-04',
      draw: DateTime.utc(2026, 5, 25),
      start: DateTime.utc(2026, 6, 6),
      end: DateTime.utc(2026, 9, 5, 23, 59, 59),
    );
    final current = window(
      periodId: '115-05-06',
      draw: DateTime.utc(2026, 7, 25),
      start: DateTime.utc(2026, 8, 6),
      end: DateTime.utc(2026, 11, 5, 23, 59, 59),
    );

    final selected = InvoiceAwardPeriodSelection.select(
      windows: [older, current],
      now: DateTime.utc(2026, 8, 20),
    );

    expect(selected.currentMatchable?.periodId, '115-05-06');
    expect(
      selected.stillRedeemable.map((item) => item.periodId),
      ['115-05-06', '115-03-04'],
    );
  });

  test('non-UTC selection instant fails closed', () {
    final selected = InvoiceAwardPeriodSelection.select(
      windows: const [],
      now: DateTime(2026, 8, 20),
    );
    expect(selected.currentMatchable, isNull);
    expect(selected.stillRedeemable, isEmpty);
  });
}
