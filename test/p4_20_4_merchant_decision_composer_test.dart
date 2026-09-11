import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';

void main() {
  group('P4.20.4 Merchant Decision Composer', () {
    const composer = InvoiceMerchantDecisionComposer();
    const input = InvoiceMerchantDecisionInput(
      recognizedMerchantName: 'OK超商 晶技門市',
      sellerTaxId: '31655572',
      recognitionSourceLabel: 'QR + OCR',
      existingMerchantBrand: 'OK Mart',
      officialLegalName: '富達零售股份有限公司晶技門市',
      officialEntityLabel: '分公司／門市',
      officialParentSellerTaxId: '22853565',
      officialSource: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      officialDataDate: '2026-09-09',
    );

    test('starts with no implicit merchant selection', () {
      final state = composer.compose(input);

      expect(state.hasExplicitSelection, isFalse);
      expect(state.selectedOption, isNull);
      expect(state.selection, isNull);
      expect(state.candidates, hasLength(3));
    });

    test('keeps recognition, MerchantBrand and official legal name separate', () {
      final state = composer.compose(input);

      expect(
        state.candidateFor(InvoiceMerchantDecisionOption.recognition).displayName,
        'OK超商 晶技門市',
      );
      expect(
        state
            .candidateFor(InvoiceMerchantDecisionOption.existingMerchantBrand)
            .displayName,
        'OK Mart',
      );
      final official =
          state.candidateFor(InvoiceMerchantDecisionOption.officialRegistry);
      expect(official.displayName, '富達零售股份有限公司晶技門市');
      expect(official.sellerTaxId, '31655572');
      expect(official.supportingLabel, contains('總機構 22853565'));
      expect(official.supportingLabel, contains('資料 2026-09-09'));
    });

    test('recognition choice preserves literal and requires second binding confirmation', () {
      final selection = composer
          .compose(input)
          .select(InvoiceMerchantDecisionOption.recognition)
          .selection!;

      expect(selection.displayName, 'OK超商 晶技門市');
      expect(selection.invoiceLiteral, 'OK超商 晶技門市');
      expect(selection.requiresMerchantBindingConfirmation, isTrue);
      expect(selection.writesFormalTransaction, isFalse);
    });

    test('existing MerchantBrand never becomes official legal name implicitly', () {
      final selection = composer
          .compose(input)
          .select(InvoiceMerchantDecisionOption.existingMerchantBrand)
          .selection!;

      expect(selection.displayName, 'OK Mart');
      expect(selection.displayName, isNot('富達零售股份有限公司晶技門市'));
      expect(selection.invoiceLiteral, 'OK超商 晶技門市');
      expect(selection.requiresMerchantBindingConfirmation, isFalse);
      expect(selection.writesFormalTransaction, isFalse);
    });

    test('official choice requires a second explicit merchant binding confirmation', () {
      final selection = composer
          .compose(input)
          .select(InvoiceMerchantDecisionOption.officialRegistry)
          .selection!;

      expect(selection.displayName, '富達零售股份有限公司晶技門市');
      expect(selection.sellerTaxId, '31655572');
      expect(selection.invoiceLiteral, 'OK超商 晶技門市');
      expect(selection.requiresMerchantBindingConfirmation, isTrue);
      expect(selection.writesFormalTransaction, isFalse);
    });

    test('official option is unavailable without an exact seller identity', () {
      const noSeller = InvoiceMerchantDecisionInput(
        recognizedMerchantName: '候選名稱',
        sellerTaxId: '',
        recognitionSourceLabel: 'OCR',
        officialLegalName: '官方名稱',
      );
      final state = composer.compose(noSeller);

      expect(
        state.candidateFor(InvoiceMerchantDecisionOption.officialRegistry).available,
        isFalse,
      );
      expect(
        () => state.select(InvoiceMerchantDecisionOption.officialRegistry),
        throwsStateError,
      );
    });
  });
}
