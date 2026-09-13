import 'invoice_registry_corroboration_policy.dart';
import 'invoice_seller_tax_id_confirmation.dart';

/// P4.20.4+461 fail-closed bridge used by Invoice Review to keep the explicit
/// sellerTaxId confirmation and Registry lookup authority in the same exact
/// value/source domain.
///
/// The caller owns UI state and local Registry refresh. This bridge performs no
/// lookup and no write. It first synchronizes the confirmation state to the
/// current sellerTaxId/source pair; only then may that exact confirmation be
/// presented to [InvoiceRegistryCorroborationAuthorityPolicy].
class InvoiceSellerTaxIdAuthorityBridge {
  const InvoiceSellerTaxIdAuthorityBridge({
    this.policy = const InvoiceRegistryCorroborationAuthorityPolicy(),
  });

  final InvoiceRegistryCorroborationAuthorityPolicy policy;

  InvoiceSellerTaxIdAuthorityBridgeResult evaluate({
    required InvoiceSellerTaxIdConfirmationState confirmationState,
    required String sellerIdentifier,
    required String sourceToken,
    required bool localQrAuthority,
    required bool explicitlyCorrected,
    required bool explicitlyAiSelected,
    required bool aiComparisonAcknowledged,
    required String initialLocalSellerIdentifierSource,
  }) {
    final synchronized = confirmationState.withCurrent(
      sellerTaxId: sellerIdentifier,
      sourceToken: sourceToken,
    );
    final decision = policy.evaluateReviewSelection(
      sellerIdentifier: sellerIdentifier,
      localQrAuthority: localQrAuthority,
      explicitlyCorrected: explicitlyCorrected,
      explicitlyAiSelected: explicitlyAiSelected,
      aiComparisonAcknowledged: aiComparisonAcknowledged,
      initialLocalSellerIdentifierSource: initialLocalSellerIdentifierSource,
      explicitUserConfirmed: synchronized.explicitlyConfirmedForCurrentValue,
    );
    return InvoiceSellerTaxIdAuthorityBridgeResult(
      confirmationState: synchronized,
      decision: decision,
    );
  }
}

class InvoiceSellerTaxIdAuthorityBridgeResult {
  const InvoiceSellerTaxIdAuthorityBridgeResult({
    required this.confirmationState,
    required this.decision,
  });

  final InvoiceSellerTaxIdConfirmationState confirmationState;
  final InvoiceRegistryCorroborationAuthorityDecision decision;

  bool get authoritative => decision.authoritative;
}
