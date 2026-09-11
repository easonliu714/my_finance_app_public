import 'taiwan_tax_id.dart';

/// P4.20.4+461 explicit sellerTaxId authority carried by the review UI.
///
/// OCR/AI recognition alone never becomes authoritative. The user must confirm
/// the exact current 8-digit value (with checksum), or an existing trusted QR
/// authority must already cover the exact current value. A value/source change
/// invalidates a prior user confirmation immediately.
class InvoiceSellerTaxIdConfirmationState {
  const InvoiceSellerTaxIdConfirmationState({
    required this.currentSellerTaxId,
    required this.currentSourceToken,
    this.confirmedSellerTaxId = '',
    this.confirmedSourceToken = '',
  });

  final String currentSellerTaxId;
  final String currentSourceToken;
  final String confirmedSellerTaxId;
  final String confirmedSourceToken;

  String get normalizedSellerTaxId =>
      currentSellerTaxId.replaceAll(RegExp(r'[^0-9]'), '');

  bool get canExplicitlyConfirm {
    final seller = normalizedSellerTaxId;
    return seller.length == 8 &&
        isTaiwanTaxIdFormat(seller) &&
        hasValidTaiwanTaxIdChecksum(seller);
  }

  bool get explicitlyConfirmedForCurrentValue =>
      confirmedSellerTaxId == normalizedSellerTaxId &&
      confirmedSourceToken == currentSourceToken &&
      confirmedSellerTaxId.isNotEmpty;

  bool isAuthoritative({required bool trustedQrAuthority}) =>
      trustedQrAuthority || explicitlyConfirmedForCurrentValue;

  InvoiceSellerTaxIdConfirmationState confirmCurrent() {
    if (!canExplicitlyConfirm) return this;
    return InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: currentSellerTaxId,
      currentSourceToken: currentSourceToken,
      confirmedSellerTaxId: normalizedSellerTaxId,
      confirmedSourceToken: currentSourceToken,
    );
  }

  InvoiceSellerTaxIdConfirmationState withCurrent({
    required String sellerTaxId,
    required String sourceToken,
  }) {
    final next = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: sellerTaxId,
      currentSourceToken: sourceToken,
      confirmedSellerTaxId: confirmedSellerTaxId,
      confirmedSourceToken: confirmedSourceToken,
    );
    if (next.explicitlyConfirmedForCurrentValue) return next;
    return InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: sellerTaxId,
      currentSourceToken: sourceToken,
    );
  }
}
