import 'invoice_merchant_decision_composer.dart';
import 'invoice_merchant_identity_review_service.dart';

/// P4.20.4 integration seam between the existing Invoice Review identity
/// resolver and the presentation-only Merchant Decision Composer.
///
/// This adapter deliberately does not perform Registry lookup, MerchantBrand
/// writes, or transaction writes. The existing review flow remains the owner of
/// authority checks and explicit binding side effects.
class InvoiceMerchantDecisionIntegration {
  const InvoiceMerchantDecisionIntegration({
    this.composer = const InvoiceMerchantDecisionComposer(),
  });

  final InvoiceMerchantDecisionComposer composer;

  InvoiceMerchantDecisionComposerState compose({
    required String recognizedMerchantName,
    required String sellerTaxId,
    required String recognitionSourceLabel,
    InvoiceMerchantIdentityReviewContext? identityContext,
  }) {
    final seller = _digits(sellerTaxId);
    final suppliedContext = identityContext;

    // A Registry/MerchantBrand review context is evidence for one exact seller
    // identifier. If the user edits or switches the sellerTaxId before the
    // asynchronous corroboration refresh completes, fail closed and do not
    // expose stale official or MerchantBrand candidates for the new invoice
    // identity.
    final contextSeller =
        _digits(suppliedContext?.decision.sellerIdentifier ?? '');
    final context = seller.isNotEmpty && contextSeller == seller
        ? suppliedContext
        : null;

    final metadata = <String>[
      if ((context?.registryCoverage ?? '').trim().isNotEmpty)
        (context?.registryCoverage ?? '').trim(),
      if ((context?.registryVersion ?? '').trim().isNotEmpty)
        'Registry ${(context?.registryVersion ?? '').trim()}',
    ].join(' · ');

    return composer.compose(
      InvoiceMerchantDecisionInput(
        recognizedMerchantName: recognizedMerchantName,
        sellerTaxId: seller,
        recognitionSourceLabel: recognitionSourceLabel,
        existingMerchantBrand:
            context?.decision.formalMerchantName.trim() ?? '',
        officialLegalName:
            context?.decision.officialLegalNameSuggestion.trim() ?? '',
        officialEntityLabel: metadata,
        officialSource: context == null ? '' : '本機官方 Registry',
        officialDataDate: context?.registrySourceDataDate.trim() ?? '',
      ),
    );
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
