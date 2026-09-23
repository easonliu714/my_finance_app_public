import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_period_catalog.dart';

void main() {
  test('before 115-07-08 draw defaults to still-redeemable 115-05-06', () {
    final now = DateTime(2026, 9, 23, 12);
    final visible = InvoiceAwardRecentPeriodCatalog.visibleAt(now);
    final selected = InvoiceAwardRecentPeriodCatalog.defaultAt(now);

    expect(
      visible.map((item) => item.period.id).toList(),
      <String>['115-07-08', '115-05-06'],
    );
    expect(
      InvoiceAwardRecentPeriodCatalog.period1150708.canCheckAt(now),
      isFalse,
    );
    expect(selected.period.id, '115-05-06');
    expect(
      InvoiceAwardRecentPeriodCatalog.usesPreviousPublication(selected, now),
      isFalse,
    );
  });

  test('after draw latest period is default and 05-06 uses previous page', () {
    final now = DateTime(2026, 9, 26, 12);
    final selected = InvoiceAwardRecentPeriodCatalog.defaultAt(now);

    expect(selected.period.id, '115-07-08');
    expect(
      InvoiceAwardRecentPeriodCatalog.usesPreviousPublication(
        InvoiceAwardRecentPeriodCatalog.period1150506,
        now,
      ),
      isTrue,
    );
  });

  test('expired prior period is hidden', () {
    final visible =
        InvoiceAwardRecentPeriodCatalog.visibleAt(DateTime(2026, 11, 6, 12));
    expect(
      visible.map((item) => item.period.id).toList(),
      <String>['115-07-08'],
    );
  });
}
