import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_coordinator.dart';

void main() {
  const coordinator = InvoiceMerchantDecisionCoordinator();

  test('coordinator keeps merchant decision outside formal transaction writes', () {
    final state = coordinator.compose(
      recognizedMerchantName: 'OK mart 晶技門市',
      sellerTaxId: '31655572',
      recognitionSourceLabel: 'QR',
    );

    expect(state.hasExplicitSelection, isFalse);
    expect(coordinator.writesFormalTransaction, isFalse);

    final selected = coordinator.select(
      state,
      InvoiceMerchantDecisionOption.recognition,
    );
    expect(selected.selection, isNotNull);
    expect(selected.selection!.invoiceLiteral, 'OK mart 晶技門市');
    expect(selected.selection!.writesFormalTransaction, isFalse);
  });

  test('non-official selection cannot enter official binding path', () async {
    final state = coordinator.compose(
      recognizedMerchantName: 'OK mart 晶技門市',
      sellerTaxId: '31655572',
      recognitionSourceLabel: 'QR',
    );
    final selected = coordinator.select(
      state,
      InvoiceMerchantDecisionOption.recognition,
    );

    expect(
      () => coordinator.confirmOfficialBinding(
        selection: selected.selection!,
        trustedQrSellerIdentifier: true,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'OFFICIAL_MERCHANT_BINDING_CONFIRMATION_REQUIRED',
        ),
      ),
    );
  });

  test('formal MerchantBrand adoption requires an explicit existing-brand choice', () {
    const recognition = InvoiceMerchantDecisionSelection(
      option: InvoiceMerchantDecisionOption.recognition,
      displayName: 'OK mart 晶技門市',
      sellerTaxId: '31655572',
      invoiceLiteral: 'OK mart 晶技門市',
      requiresMerchantBindingConfirmation: false,
    );
    const existing = InvoiceMerchantDecisionSelection(
      option: InvoiceMerchantDecisionOption.existingMerchantBrand,
      displayName: 'OK Mart',
      sellerTaxId: '31655572',
      invoiceLiteral: 'OK mart 晶技門市',
      requiresMerchantBindingConfirmation: false,
    );
    const official = InvoiceMerchantDecisionSelection(
      option: InvoiceMerchantDecisionOption.officialRegistry,
      displayName: '富達零售股份有限公司晶技門市',
      sellerTaxId: '31655572',
      invoiceLiteral: 'OK mart 晶技門市',
      requiresMerchantBindingConfirmation: true,
    );

    expect(
      coordinator.formalMerchantNameForExplicitSelection(recognition),
      isEmpty,
    );
    expect(
      coordinator.formalMerchantNameForExplicitSelection(existing),
      'OK Mart',
    );
    expect(
      coordinator.formalMerchantNameForExplicitSelection(official),
      isEmpty,
    );

    expect(recognition.writesFormalTransaction, isFalse);
    expect(existing.writesFormalTransaction, isFalse);
    expect(official.writesFormalTransaction, isFalse);
  });
}
