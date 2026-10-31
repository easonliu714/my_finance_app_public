import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_local_match_input.dart';

void main() {
  group('InvoiceAwardLocalMatchInput', () {
    test('normalizes explicit invoice identity and derives Jul-Aug 115 period', () {
      final input = InvoiceAwardLocalMatchInput(
        invoiceNumber: 'ab-1234 5678',
        invoiceDate: DateTime(2026, 8, 31),
      );

      expect(input.normalizedInvoiceNumber, 'AB12345678');
      expect(input.hasValidInvoiceNumber, isTrue);
      expect(input.period.id, '115-07-08');
      expect(input.isValid, isTrue);
    });

    test('rejects malformed invoice number instead of inferring identity', () {
      final input = InvoiceAwardLocalMatchInput(
        invoiceNumber: '12345678',
        invoiceDate: DateTime(2026, 7, 1),
      );

      expect(input.hasValidInvoiceNumber, isFalse);
      expect(input.isValid, isFalse);
    });

    test('maps every month to its canonical two-month award period', () {
      expect(
        InvoiceAwardLocalMatchInput(
          invoiceNumber: 'AB12345678',
          invoiceDate: DateTime(2026, 1, 1),
        ).period.id,
        '115-01-02',
      );
      expect(
        InvoiceAwardLocalMatchInput(
          invoiceNumber: 'AB12345678',
          invoiceDate: DateTime(2026, 12, 31),
        ).period.id,
        '115-11-12',
      );
    });
  });
}
