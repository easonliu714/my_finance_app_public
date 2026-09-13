import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer_card.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_review_section.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_master_binding_service.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';

class _FakeBindingService extends InvoiceMerchantMasterBindingService {
  _FakeBindingService();

  int calls = 0;
  String merchantName = '';
  String sellerTaxId = '';

  @override
  Future<InvoiceMerchantMasterBindingResult> bind({
    required String merchantName,
    required String sellerTaxId,
    bool trustedQrSellerIdentifier = false,
    String sourceReference = '',
  }) async {
    calls += 1;
    this.merchantName = merchantName;
    this.sellerTaxId = sellerTaxId;
    return InvoiceMerchantMasterBindingResult(
      status: InvoiceMerchantMasterBindingStatus.created,
      merchant: MerchantRecord(
        id: 'merchant-tax-$sellerTaxId',
        name: merchantName,
        sellerIdentifier: sellerTaxId,
      ),
      message: 'created',
    );
  }
}

void main() {
  testWidgets(
    'authoritative recognition fallback requires dialog then reports bound MerchantBrand',
    (tester) async {
      final binding = _FakeBindingService();
      InvoiceMerchantDecisionSelection? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvoiceMerchantDecisionReviewSection(
                recognizedMerchantName: 'OK超商 晶技門市',
                sellerTaxId: '31655572',
                recognitionSourceLabel: 'OCR',
                identityContext: null,
                selectedOption: InvoiceMerchantDecisionOption.recognition,
                sellerTaxIdAuthoritative: true,
                merchantBindingService: binding,
                onSelected: (value) => selected = value,
                onConfirmOfficialBinding: (_) {},
              ),
            ),
          ),
        ),
      );

      final secondAction = find.byKey(
        InvoiceMerchantDecisionComposerCard.recognitionBindingConfirmKey,
      );
      expect(secondAction, findsOneWidget);
      await tester.ensureVisible(secondAction);
      await tester.tap(secondAction);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          InvoiceMerchantDecisionReviewSection.recognitionBindingDialogKey,
        ),
        findsOneWidget,
      );
      expect(binding.calls, 0);

      final nameField = find.byKey(
        InvoiceMerchantDecisionReviewSection.recognitionMerchantNameKey,
      );
      await tester.enterText(nameField, 'OK Mart 晶技');
      await tester.tap(
        find.byKey(
          InvoiceMerchantDecisionReviewSection
              .recognitionBindingDialogConfirmKey,
        ),
      );
      await tester.pumpAndSettle();

      expect(binding.calls, 1);
      expect(binding.merchantName, 'OK Mart 晶技');
      expect(binding.sellerTaxId, '31655572');
      expect(selected, isNotNull);
      expect(
        selected!.option,
        InvoiceMerchantDecisionOption.existingMerchantBrand,
      );
      expect(selected!.displayName, 'OK Mart 晶技');
      expect(selected!.sellerTaxId, '31655572');
      expect(selected!.invoiceLiteral, 'OK超商 晶技門市');
      expect(selected!.requiresMerchantBindingConfirmation, isFalse);
      expect(selected!.writesFormalTransaction, isFalse);
    },
  );

  testWidgets(
    'recognition fallback stays unavailable without current sellerTaxId authority',
    (tester) async {
      final binding = _FakeBindingService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvoiceMerchantDecisionReviewSection(
              recognizedMerchantName: 'OK超商 晶技門市',
              sellerTaxId: '31655572',
              recognitionSourceLabel: 'OCR',
              identityContext: null,
              selectedOption: InvoiceMerchantDecisionOption.recognition,
              sellerTaxIdAuthoritative: false,
              merchantBindingService: binding,
              onSelected: (_) {},
              onConfirmOfficialBinding: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.byKey(
          InvoiceMerchantDecisionComposerCard.recognitionBindingConfirmKey,
        ),
        findsNothing,
      );
      expect(binding.calls, 0);
    },
  );
}
