import 'invoice_merchant_decision_composer.dart';
import 'invoice_merchant_decision_integration.dart';
import 'invoice_merchant_identity_review_service.dart';
import 'invoice_merchant_master_binding_service.dart';

/// P4.20.4 production coordinator for the Merchant Decision Composer.
///
/// This coordinator owns only explicit review/binding intent. It never writes a
/// formal transaction and never performs Registry lookup on its own. Registry
/// evidence must already have been resolved by the existing identity-review
/// service and passed in as [identityContext].
class InvoiceMerchantDecisionCoordinator {
  const InvoiceMerchantDecisionCoordinator({
    this.integration = const InvoiceMerchantDecisionIntegration(),
    this.bindingService = const InvoiceMerchantMasterBindingService(),
  });

  final InvoiceMerchantDecisionIntegration integration;
  final InvoiceMerchantMasterBindingService bindingService;

  InvoiceMerchantDecisionComposerState compose({
    required String recognizedMerchantName,
    required String sellerTaxId,
    required String recognitionSourceLabel,
    InvoiceMerchantIdentityReviewContext? identityContext,
  }) {
    return integration.compose(
      recognizedMerchantName: recognizedMerchantName,
      sellerTaxId: sellerTaxId,
      recognitionSourceLabel: recognitionSourceLabel,
      identityContext: identityContext,
    );
  }

  InvoiceMerchantDecisionComposerState select(
    InvoiceMerchantDecisionComposerState state,
    InvoiceMerchantDecisionOption option,
  ) {
    return state.select(option);
  }

  /// Returns the formal MerchantBrand name that may be adopted immediately from
  /// an explicit decision selection.
  ///
  /// Only an already-confirmed MerchantBrand is eligible. Recognition text is
  /// still invoice evidence rather than a formal MerchantBrand, while Registry
  /// legal identity requires the separate explicit binding confirmation path
  /// below before it may become a formal merchant.
  String formalMerchantNameForExplicitSelection(
    InvoiceMerchantDecisionSelection selection,
  ) {
    switch (selection.option) {
      case InvoiceMerchantDecisionOption.existingMerchantBrand:
        return selection.displayName.trim();
      case InvoiceMerchantDecisionOption.recognition:
      case InvoiceMerchantDecisionOption.officialRegistry:
        return '';
    }
  }

  Future<InvoiceMerchantMasterBindingResult> confirmOfficialBinding({
    required InvoiceMerchantDecisionSelection selection,
    required bool trustedQrSellerIdentifier,
  }) {
    if (selection.option != InvoiceMerchantDecisionOption.officialRegistry ||
        !selection.requiresMerchantBindingConfirmation) {
      throw StateError('OFFICIAL_MERCHANT_BINDING_CONFIRMATION_REQUIRED');
    }
    return bindingService.bind(
      merchantName: selection.displayName,
      sellerTaxId: selection.sellerTaxId,
      trustedQrSellerIdentifier: trustedQrSellerIdentifier,
      sourceReference: 'p4.20.4-explicit-official-binding:${selection.sellerTaxId}',
    );
  }

  /// Merchant decision/binding remains outside the formal accounting write
  /// boundary. The invoice review flow must still hand off through an editable
  /// transaction draft and require explicit Save.
  bool get writesFormalTransaction => false;
}
