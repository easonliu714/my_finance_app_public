import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_integration.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';

void main() {
  group('P4.20.4 Invoice Review composer integration', () {
    const integration = InvoiceMerchantDecisionIntegration();

    test('maps existing review identity authority into three separate lanes', () {
      const context = InvoiceMerchantIdentityReviewContext(
        decision: MerchantIdentityResolutionDecision(
          literalMerchantText: 'OK超商 晶技門市',
          sellerIdentifier: '31655572',
          registryLookupAllowed: true,
          officialLegalNameSuggestion: '富達零售股份有限公司晶技門市',
          formalMerchantName: 'OK Mart',
          requiresBrandConfirmation: false,
          reason: MerchantIdentityResolutionReason.confirmedBrandLink,
        ),
        registryStatus: BusinessRegistryLookupStatus.hit,
        registryVersion: 'p4.20.3-fia-2026-09-09-b98874df3998',
        registryCoverage: '全台公司／商業／分公司',
        registrySourceDataDate: '2026-09-09',
      );

      final state = integration.compose(
        recognizedMerchantName: 'OK超商 晶技門市',
        sellerTaxId: '31655572',
        recognitionSourceLabel: 'QR + OCR',
        identityContext: context,
      );

      expect(state.hasExplicitSelection, isFalse);
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
      expect(official.supportingLabel, contains('2026-09-09'));
      expect(official.supportingLabel, contains('本機官方 Registry'));
    });

    test('no Registry context keeps official and existing lanes unavailable', () {
      final state = integration.compose(
        recognizedMerchantName: '辨識商家',
        sellerTaxId: '31655572',
        recognitionSourceLabel: 'OCR',
      );

      expect(state.hasExplicitSelection, isFalse);
      expect(
        state
            .candidateFor(InvoiceMerchantDecisionOption.existingMerchantBrand)
            .available,
        isFalse,
      );
      expect(
        state.candidateFor(InvoiceMerchantDecisionOption.officialRegistry).available,
        isFalse,
      );
    });

    test('official selection stays review-only and requires explicit binding', () {
      const context = InvoiceMerchantIdentityReviewContext(
        decision: MerchantIdentityResolutionDecision(
          literalMerchantText: '門市原文',
          sellerIdentifier: '31655572',
          registryLookupAllowed: true,
          officialLegalNameSuggestion: '官方法定名稱',
          formalMerchantName: '',
          requiresBrandConfirmation: true,
          reason:
              MerchantIdentityResolutionReason.registryLegalNameNeedsBrandConfirmation,
        ),
        registryStatus: BusinessRegistryLookupStatus.hit,
        registrySourceDataDate: '2026-09-09',
      );

      final selection = integration
          .compose(
            recognizedMerchantName: '門市原文',
            sellerTaxId: '31655572',
            recognitionSourceLabel: 'QR',
            identityContext: context,
          )
          .select(InvoiceMerchantDecisionOption.officialRegistry)
          .selection!;

      expect(selection.invoiceLiteral, '門市原文');
      expect(selection.displayName, '官方法定名稱');
      expect(selection.requiresMerchantBindingConfirmation, isTrue);
      expect(selection.writesFormalTransaction, isFalse);
    });
  });
}
