import 'invoice_live_capture_page.dart';

enum InvoiceLiveReadinessProfile {
  electronicOrUnresolved,
  traditionalExplicitSellerTax,
}

class InvoiceLiveFieldReadiness {
  const InvoiceLiveFieldReadiness({
    required this.signature,
    required this.consecutiveObservations,
    required this.stableObservations,
    required this.identityEvidenceReady,
    required this.canFreeze,
  });

  final String signature;
  final int consecutiveObservations;
  final int stableObservations;
  final bool identityEvidenceReady;
  final bool canFreeze;
}

InvoiceLiveFieldReadiness resolveInvoiceLiveFieldReadiness({
  required TraditionalLiveIdentityConsensus consensus,
  required String invoiceNumber,
  required String sellerTaxId,
  required bool hasSellerIdentityContext,
  required String previousSignature,
  required int previousConsecutiveObservations,
  InvoiceLiveReadinessProfile profile =
      InvoiceLiveReadinessProfile.electronicOrUnresolved,
}) {
  final invoice = invoiceNumber
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .toUpperCase();
  final seller = sellerTaxId.replaceAll(RegExp(r'[^0-9]'), '');

  // P4.17.2 Traditional-first contract: merchant-name/header context is useful
  // for OCR diagnosis but is no longer sufficient to auto-freeze a Traditional
  // candidate. The Live result must carry a real authoritative 8-digit seller
  // tax ID in addition to the invoice number. Electronic/unresolved receipts
  // retain the previous identity-context behavior.
  final identityReady = switch (profile) {
    InvoiceLiveReadinessProfile.traditionalExplicitSellerTax =>
      RegExp(r'^\d{8}$').hasMatch(seller),
    InvoiceLiveReadinessProfile.electronicOrUnresolved =>
      seller.isNotEmpty || hasSellerIdentityContext,
  };

  // Preserve the P4.16.16 signature contract. The readiness profile may change
  // how identityReady is resolved, but it must not change the serialized
  // signature shape used for consecutive-observation stability.
  final signature = invoice.isEmpty ? '' : '$invoice|$seller|$identityReady';

  var consecutive = 0;
  if (invoice.isNotEmpty && identityReady) {
    consecutive = signature == previousSignature
        ? previousConsecutiveObservations + 1
        : 1;
  }
  final stable = consecutive < consensus.stableObservations
      ? consecutive
      : consensus.stableObservations;

  return InvoiceLiveFieldReadiness(
    signature: signature,
    consecutiveObservations: consecutive,
    stableObservations: stable,
    identityEvidenceReady: identityReady,
    canFreeze: consensus.canFreeze && stable >= 2,
  );
}
