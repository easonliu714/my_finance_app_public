import 'invoice_merchant_decision_composer.dart';
import 'invoice_merchant_master_binding_service.dart';
import 'invoice_seller_tax_id_confirmation.dart';

/// P4.20.4+461 write-side guard for recognition -> MerchantBrand binding.
///
/// Selecting the recognition candidate never writes merchant state. The caller
/// must invoke this flow only after the user performs the second explicit bind
/// action. The flow then revalidates the exact current sellerTaxId authority at
/// write time, so stale UI evidence cannot authorize a MerchantBrand write.
class InvoiceRecognitionMerchantBindingFlow {
  const InvoiceRecognitionMerchantBindingFlow({
    this.bindingService = const InvoiceMerchantMasterBindingService(),
  });

  final InvoiceMerchantMasterBindingService bindingService;

  Future<InvoiceRecognitionMerchantBindingFlowResult> bind({
    required InvoiceMerchantDecisionSelection selection,
    required InvoiceSellerTaxIdConfirmationState sellerTaxIdConfirmation,
    bool trustedQrAuthority = false,
    String consumerFacingMerchantName = '',
  }) async {
    if (selection.option != InvoiceMerchantDecisionOption.recognition ||
        !selection.requiresMerchantBindingConfirmation) {
      return const InvoiceRecognitionMerchantBindingFlowResult.blocked(
        reasonCode: 'RECOGNITION_SECOND_CONFIRMATION_REQUIRED',
      );
    }

    final currentSellerTaxId = sellerTaxIdConfirmation.normalizedSellerTaxId;
    final selectionSellerTaxId =
        selection.sellerTaxId.replaceAll(RegExp(r'[^0-9]'), '');
    if (currentSellerTaxId.isEmpty ||
        currentSellerTaxId != selectionSellerTaxId) {
      return const InvoiceRecognitionMerchantBindingFlowResult.blocked(
        reasonCode: 'STALE_SELLER_TAX_ID_SELECTION',
      );
    }

    if (!sellerTaxIdConfirmation.isAuthoritative(
      trustedQrAuthority: trustedQrAuthority,
    )) {
      return const InvoiceRecognitionMerchantBindingFlowResult.blocked(
        reasonCode: 'SELLER_TAX_ID_AUTHORITY_REQUIRED',
      );
    }

    final merchantName = consumerFacingMerchantName.trim().isNotEmpty
        ? consumerFacingMerchantName.trim()
        : selection.displayName.trim();
    if (merchantName.isEmpty) {
      return const InvoiceRecognitionMerchantBindingFlowResult.blocked(
        reasonCode: 'MERCHANT_BRAND_NAME_REQUIRED',
      );
    }

    final result = await bindingService.bind(
      merchantName: merchantName,
      sellerTaxId: currentSellerTaxId,
      trustedQrSellerIdentifier: trustedQrAuthority,
      sourceReference: 'invoice-review-recognition-binding:$currentSellerTaxId',
    );
    return InvoiceRecognitionMerchantBindingFlowResult.bound(result);
  }
}

class InvoiceRecognitionMerchantBindingFlowResult {
  const InvoiceRecognitionMerchantBindingFlowResult._({
    required this.allowed,
    required this.reasonCode,
    this.bindingResult,
  });

  const InvoiceRecognitionMerchantBindingFlowResult.blocked({
    required String reasonCode,
  }) : this._(
          allowed: false,
          reasonCode: reasonCode,
        );

  const InvoiceRecognitionMerchantBindingFlowResult.bound(
    InvoiceMerchantMasterBindingResult result,
  ) : this._(
          allowed: true,
          reasonCode: 'BIND_ATTEMPTED',
          bindingResult: result,
        );

  final bool allowed;
  final String reasonCode;
  final InvoiceMerchantMasterBindingResult? bindingResult;

  bool get isSuccess => allowed && (bindingResult?.isSuccess ?? false);

  /// Merchant binding is never a formal accounting write.
  bool get writesFormalTransaction => false;
}
