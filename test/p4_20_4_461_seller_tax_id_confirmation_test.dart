import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation.dart';

void main() {
  group('P4.20.4+461 sellerTaxId explicit confirmation', () {
    test('weak OCR sellerTaxId is not authoritative before user confirmation', () {
      const state = InvoiceSellerTaxIdConfirmationState(
        currentSellerTaxId: '31655572',
        currentSourceToken: 'OCR',
      );

      expect(state.canExplicitlyConfirm, isTrue);
      expect(state.explicitlyConfirmedForCurrentValue, isFalse);
      expect(state.isAuthoritative(trustedQrAuthority: false), isFalse);
    });

    test('explicit user confirmation makes current value authoritative', () {
      const initial = InvoiceSellerTaxIdConfirmationState(
        currentSellerTaxId: '31655572',
        currentSourceToken: 'OCR',
      );
      final confirmed = initial.confirmCurrent();

      expect(confirmed.explicitlyConfirmedForCurrentValue, isTrue);
      expect(confirmed.isAuthoritative(trustedQrAuthority: false), isTrue);
    });

    test('confirmation is invalidated when sellerTaxId changes', () {
      const initial = InvoiceSellerTaxIdConfirmationState(
        currentSellerTaxId: '31655572',
        currentSourceToken: 'OCR',
      );
      final changed = initial.confirmCurrent().withCurrent(
            sellerTaxId: '60282181',
            sourceToken: 'OCR',
          );

      expect(changed.canExplicitlyConfirm, isTrue);
      expect(changed.explicitlyConfirmedForCurrentValue, isFalse);
      expect(changed.isAuthoritative(trustedQrAuthority: false), isFalse);
    });

    test('confirmation is invalidated when source changes', () {
      const initial = InvoiceSellerTaxIdConfirmationState(
        currentSellerTaxId: '31655572',
        currentSourceToken: 'OCR',
      );
      final changed = initial.confirmCurrent().withCurrent(
            sellerTaxId: '31655572',
            sourceToken: 'AI',
          );

      expect(changed.explicitlyConfirmedForCurrentValue, isFalse);
      expect(changed.isAuthoritative(trustedQrAuthority: false), isFalse);
    });

    test('trusted QR authority remains independently authoritative', () {
      const state = InvoiceSellerTaxIdConfirmationState(
        currentSellerTaxId: '12345678',
        currentSourceToken: 'QR',
      );

      expect(state.explicitlyConfirmedForCurrentValue, isFalse);
      expect(state.isAuthoritative(trustedQrAuthority: true), isTrue);
    });
  });
}
