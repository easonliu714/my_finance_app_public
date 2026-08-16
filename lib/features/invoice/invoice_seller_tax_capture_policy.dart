const int sellerTaxCaptureOnlyWindowSize = 7;
const int sellerTaxCaptureOnlyThreshold = 3;

class InvoiceSellerTaxCaptureOnlyDecision {
  const InvoiceSellerTaxCaptureOnlyDecision({
    required this.window,
    required this.evidenceCount,
    required this.ready,
  });

  final List<bool> window;
  final int evidenceCount;
  final bool ready;
}

InvoiceSellerTaxCaptureOnlyDecision resolveInvoiceSellerTaxCaptureOnly({
  required List<bool> previousWindow,
  required bool currentStructuralEvidence,
  required bool invoiceGreen,
  required bool electronicWideEvidence,
  int windowSize = sellerTaxCaptureOnlyWindowSize,
  int threshold = sellerTaxCaptureOnlyThreshold,
}) {
  if (windowSize <= 0) {
    throw ArgumentError.value(windowSize, 'windowSize');
  }
  if (threshold <= 0 || threshold > windowSize) {
    throw ArgumentError.value(threshold, 'threshold');
  }

  final next = <bool>[...previousWindow, currentStructuralEvidence];
  final window = next.length <= windowSize
      ? next
      : next.sublist(next.length - windowSize);
  final evidenceCount = window.where((value) => value).length;

  return InvoiceSellerTaxCaptureOnlyDecision(
    window: List<bool>.unmodifiable(window),
    evidenceCount: evidenceCount,
    ready: invoiceGreen &&
        !electronicWideEvidence &&
        evidenceCount >= threshold,
  );
}
