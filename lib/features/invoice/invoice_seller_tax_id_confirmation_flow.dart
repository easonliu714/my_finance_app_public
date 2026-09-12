import 'invoice_merchant_identity_review_service.dart';
import 'invoice_seller_tax_id_authority_bridge.dart';
import 'invoice_seller_tax_id_confirmation.dart';

/// P4.20.4+461 explicit user-action flow for sellerTaxId authority.
///
/// This object deliberately separates two operations:
/// 1. [synchronize] invalidates stale value/source confirmation without lookup.
/// 2. [confirmAndResolve] records the explicit confirmation first, then and only
///    then permits the injected local-only merchant review port to resolve.
///
/// It never creates a MerchantBrand and never writes a formal transaction.
class InvoiceSellerTaxIdConfirmationFlow {
  const InvoiceSellerTaxIdConfirmationFlow({
    this.authorityBridge = const InvoiceSellerTaxIdAuthorityBridge(),
  });

  final InvoiceSellerTaxIdAuthorityBridge authorityBridge;

  InvoiceSellerTaxIdConfirmationFlowResult synchronize({
    required InvoiceSellerTaxIdConfirmationState confirmationState,
    required String sellerIdentifier,
    required String sourceToken,
    required bool localQrAuthority,
    required bool explicitlyCorrected,
    required bool explicitlyAiSelected,
    required bool aiComparisonAcknowledged,
    required String initialLocalSellerIdentifierSource,
  }) {
    final bridge = authorityBridge.evaluate(
      confirmationState: confirmationState,
      sellerIdentifier: sellerIdentifier,
      sourceToken: sourceToken,
      localQrAuthority: localQrAuthority,
      explicitlyCorrected: explicitlyCorrected,
      explicitlyAiSelected: explicitlyAiSelected,
      aiComparisonAcknowledged: aiComparisonAcknowledged,
      initialLocalSellerIdentifierSource: initialLocalSellerIdentifierSource,
    );
    return InvoiceSellerTaxIdConfirmationFlowResult(
      confirmationState: bridge.confirmationState,
      authoritative: bridge.authoritative,
      resolvedContext: null,
    );
  }

  Future<InvoiceSellerTaxIdConfirmationFlowResult> confirmAndResolve({
    required InvoiceSellerTaxIdConfirmationState confirmationState,
    required String sellerIdentifier,
    required String sourceToken,
    required bool localQrAuthority,
    required bool explicitlyCorrected,
    required bool explicitlyAiSelected,
    required bool aiComparisonAcknowledged,
    required String initialLocalSellerIdentifierSource,
    required String literalMerchantText,
    required InvoiceMerchantIdentityReviewPort reviewPort,
  }) async {
    final synchronized = confirmationState.withCurrent(
      sellerTaxId: sellerIdentifier,
      sourceToken: sourceToken,
    );
    final confirmed = localQrAuthority
        ? synchronized
        : synchronized.confirmCurrent();
    final bridge = authorityBridge.evaluate(
      confirmationState: confirmed,
      sellerIdentifier: sellerIdentifier,
      sourceToken: sourceToken,
      localQrAuthority: localQrAuthority,
      explicitlyCorrected: explicitlyCorrected,
      explicitlyAiSelected: explicitlyAiSelected,
      aiComparisonAcknowledged: aiComparisonAcknowledged,
      initialLocalSellerIdentifierSource: initialLocalSellerIdentifierSource,
    );

    if (!bridge.authoritative) {
      return InvoiceSellerTaxIdConfirmationFlowResult(
        confirmationState: bridge.confirmationState,
        authoritative: false,
        resolvedContext: null,
      );
    }

    final context = await reviewPort.resolve(
      sellerIdentifier: bridge.decision.sellerIdentifier,
      sellerIdentifierAuthoritative: true,
      literalMerchantText: literalMerchantText,
    );
    return InvoiceSellerTaxIdConfirmationFlowResult(
      confirmationState: bridge.confirmationState,
      authoritative: true,
      resolvedContext: context,
    );
  }
}

class InvoiceSellerTaxIdConfirmationFlowResult {
  const InvoiceSellerTaxIdConfirmationFlowResult({
    required this.confirmationState,
    required this.authoritative,
    required this.resolvedContext,
  });

  final InvoiceSellerTaxIdConfirmationState confirmationState;
  final bool authoritative;
  final InvoiceMerchantIdentityReviewContext? resolvedContext;

  bool get lookupPerformed => resolvedContext != null;
}
