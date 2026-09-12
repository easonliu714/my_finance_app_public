enum MerchantIdentityResolutionReason {
  sellerIdentifierNotAuthoritative,
  confirmedBrandLink,
  registryLegalNameNeedsBrandConfirmation,
  authoritativeSellerNeedsReview,
}

class MerchantIdentityResolutionDecision {
  const MerchantIdentityResolutionDecision({
    required this.literalMerchantText,
    required this.sellerIdentifier,
    required this.registryLookupAllowed,
    required this.officialLegalNameSuggestion,
    required this.formalMerchantName,
    required this.requiresBrandConfirmation,
    required this.reason,
  });

  final String literalMerchantText;
  final String sellerIdentifier;
  final bool registryLookupAllowed;
  final String officialLegalNameSuggestion;
  final String formalMerchantName;
  final bool requiresBrandConfirmation;
  final MerchantIdentityResolutionReason reason;
}

/// Pure P4.20.0 authority policy.
///
/// Official registry data can corroborate an already-authoritative seller
/// identifier and provide a legal-name suggestion. It never repairs seller
/// identity, silently replaces literal invoice text, or creates a new formal
/// MerchantBrand mapping from fuzzy/legal-name similarity alone.
class MerchantIdentityResolutionPolicy {
  const MerchantIdentityResolutionPolicy();

  MerchantIdentityResolutionDecision evaluate({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
    String officialRegistryLegalName = '',
    String existingConfirmedBrandName = '',
  }) {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    final literal = literalMerchantText.trim();
    final legalName = officialRegistryLegalName.trim();
    final confirmedBrand = existingConfirmedBrandName.trim();
    final authoritative = sellerIdentifierAuthoritative && seller.length == 8;

    if (!authoritative) {
      return MerchantIdentityResolutionDecision(
        literalMerchantText: literal,
        sellerIdentifier: seller,
        registryLookupAllowed: false,
        officialLegalNameSuggestion: '',
        formalMerchantName: '',
        requiresBrandConfirmation: true,
        reason: MerchantIdentityResolutionReason.sellerIdentifierNotAuthoritative,
      );
    }

    if (confirmedBrand.isNotEmpty) {
      return MerchantIdentityResolutionDecision(
        literalMerchantText: literal,
        sellerIdentifier: seller,
        registryLookupAllowed: true,
        officialLegalNameSuggestion: legalName,
        formalMerchantName: confirmedBrand,
        requiresBrandConfirmation: false,
        reason: MerchantIdentityResolutionReason.confirmedBrandLink,
      );
    }

    if (legalName.isNotEmpty) {
      return MerchantIdentityResolutionDecision(
        literalMerchantText: literal,
        sellerIdentifier: seller,
        registryLookupAllowed: true,
        officialLegalNameSuggestion: legalName,
        formalMerchantName: '',
        requiresBrandConfirmation: true,
        reason:
            MerchantIdentityResolutionReason.registryLegalNameNeedsBrandConfirmation,
      );
    }

    return MerchantIdentityResolutionDecision(
      literalMerchantText: literal,
      sellerIdentifier: seller,
      registryLookupAllowed: true,
      officialLegalNameSuggestion: '',
      formalMerchantName: '',
      requiresBrandConfirmation: true,
      reason: MerchantIdentityResolutionReason.authoritativeSellerNeedsReview,
    );
  }
}

String businessRegistryNegativeLookupKey({
  required String sellerIdentifier,
  required String snapshotVersion,
}) {
  final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
  return '$seller|${snapshotVersion.trim()}';
}
