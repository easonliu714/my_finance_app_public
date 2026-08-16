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

  // Traditional Live is allowed to freeze on the first checksum-accepted
  // 8-digit seller tax observation once the invoice number itself has already
  // reached the two-observation green state. This deliberately removes the
  // previous second seller-tax observation requirement without weakening the
  // seller-tax format/checksum gate upstream.
  final identityReady = switch (profile) {
    InvoiceLiveReadinessProfile.traditionalExplicitSellerTax =>
      RegExp(r'^\d{8}$').hasMatch(seller),
    InvoiceLiveReadinessProfile.electronicOrUnresolved =>
      seller.isNotEmpty || hasSellerIdentityContext,
  };

  // Preserve the P4.16.16 signature shape for telemetry and the electronic /
  // unresolved path. Traditional readiness no longer uses seller-tax temporal
  // repetition as an authorization gate.
  final signature = invoice.isEmpty ? '' : '$invoice|$seller|$identityReady';

  var consecutive = 0;
  if (invoice.isNotEmpty && identityReady) {
    consecutive = signature == previousSignature
        ? previousConsecutiveObservations + 1
        : 1;
  }

  if (profile == InvoiceLiveReadinessProfile.traditionalExplicitSellerTax) {
    final invoiceStable = invoice.isNotEmpty &&
        consensus.invoiceNumber == invoice &&
        consensus.invoiceObservations >= 2 &&
        consensus.currentFrameRelevant;
    final ready = invoiceStable && identityReady;
    return InvoiceLiveFieldReadiness(
      signature: signature,
      consecutiveObservations: consecutive,
      stableObservations: ready ? 2 : (identityReady ? 1 : 0),
      identityEvidenceReady: identityReady,
      canFreeze: ready,
    );
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
