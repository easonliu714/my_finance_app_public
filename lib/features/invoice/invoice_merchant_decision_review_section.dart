import 'package:flutter/material.dart';

import 'invoice_merchant_decision_composer.dart';
import 'invoice_merchant_decision_composer_card.dart';
import 'invoice_merchant_decision_integration.dart';
import 'invoice_merchant_identity_review_service.dart';

/// Mountable P4.20.4 merchant-decision section for Invoice Review.
///
/// This seam deliberately owns no Registry lookup, MerchantBrand write, or
/// formal-transaction write. The parent review flow supplies already-resolved
/// identity evidence and owns every side effect. Selection is explicit and is
/// reset fail-closed whenever the selected candidate is no longer available.
class InvoiceMerchantDecisionReviewSection extends StatelessWidget {
  const InvoiceMerchantDecisionReviewSection({
    super.key,
    required this.recognizedMerchantName,
    required this.sellerTaxId,
    required this.recognitionSourceLabel,
    required this.identityContext,
    required this.selectedOption,
    required this.onSelected,
    required this.onConfirmOfficialBinding,
    this.bindingBusy = false,
    this.integration = const InvoiceMerchantDecisionIntegration(),
  });

  static const Key sectionKey = Key('invoice_merchant_decision_review_section');

  final String recognizedMerchantName;
  final String sellerTaxId;
  final String recognitionSourceLabel;
  final InvoiceMerchantIdentityReviewContext? identityContext;
  final InvoiceMerchantDecisionOption? selectedOption;
  final ValueChanged<InvoiceMerchantDecisionOption> onSelected;
  final ValueChanged<InvoiceMerchantDecisionSelection>
      onConfirmOfficialBinding;
  final bool bindingBusy;
  final InvoiceMerchantDecisionIntegration integration;

  @override
  Widget build(BuildContext context) {
    final base = integration.compose(
      recognizedMerchantName: recognizedMerchantName,
      sellerTaxId: sellerTaxId,
      recognitionSourceLabel: recognitionSourceLabel,
      identityContext: identityContext,
    );

    var state = base;
    final requested = selectedOption;
    if (requested != null && base.candidateFor(requested).available) {
      state = base.select(requested);
    }

    return KeyedSubtree(
      key: sectionKey,
      child: InvoiceMerchantDecisionComposerCard(
        state: state,
        bindingBusy: bindingBusy,
        onSelected: onSelected,
        onConfirmOfficialBinding: onConfirmOfficialBinding,
      ),
    );
  }
}
