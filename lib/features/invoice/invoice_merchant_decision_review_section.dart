import 'package:flutter/material.dart';

import 'invoice_merchant_decision_composer.dart';
import 'invoice_merchant_decision_composer_card.dart';
import 'invoice_merchant_decision_integration.dart';
import 'invoice_merchant_identity_review_service.dart';
import 'invoice_merchant_master_binding_service.dart';

/// Mountable P4.20.4 merchant-decision section for Invoice Review.
///
/// Registry evidence remains supplied by the parent review flow. Selection is
/// explicit and is reset fail-closed whenever the selected candidate is no
/// longer available.
///
/// Recognition-to-MerchantBrand binding is fail-closed unless the parent proves
/// the current sellerTaxId already has independent authority. If the parent
/// supplies [onConfirmRecognitionBinding], that callback remains authoritative.
/// Otherwise this section provides the production fallback second-confirmation
/// flow: it rechecks the exact current sellerTaxId snapshot, lets the user edit
/// the consumer-facing MerchantBrand name, writes only through
/// [InvoiceMerchantMasterBindingService], then reports the resulting confirmed
/// MerchantBrand back through [onSelected]. It never writes a formal transaction.
class InvoiceMerchantDecisionReviewSection extends StatefulWidget {
  const InvoiceMerchantDecisionReviewSection({
    super.key,
    required this.recognizedMerchantName,
    required this.sellerTaxId,
    required this.recognitionSourceLabel,
    required this.identityContext,
    required this.selectedOption,
    required this.onSelected,
    required this.onConfirmOfficialBinding,
    this.onConfirmRecognitionBinding,
    this.sellerTaxIdAuthoritative = false,
    this.bindingBusy = false,
    this.integration = const InvoiceMerchantDecisionIntegration(),
    this.merchantBindingService = const InvoiceMerchantMasterBindingService(),
  });

  static const Key sectionKey = Key('invoice_merchant_decision_review_section');
  static const Key recognitionBindingDialogKey =
      Key('invoice_merchant_decision_recognition_binding_dialog');
  static const Key recognitionMerchantNameKey =
      Key('invoice_merchant_decision_recognition_merchant_name');
  static const Key recognitionBindingDialogConfirmKey =
      Key('invoice_merchant_decision_recognition_binding_dialog_confirm');

  final String recognizedMerchantName;
  final String sellerTaxId;
  final String recognitionSourceLabel;
  final InvoiceMerchantIdentityReviewContext? identityContext;
  final InvoiceMerchantDecisionOption? selectedOption;
  final ValueChanged<InvoiceMerchantDecisionSelection> onSelected;
  final ValueChanged<InvoiceMerchantDecisionSelection>?
      onConfirmRecognitionBinding;
  final ValueChanged<InvoiceMerchantDecisionSelection>
      onConfirmOfficialBinding;
  final bool sellerTaxIdAuthoritative;
  final bool bindingBusy;
  final InvoiceMerchantDecisionIntegration integration;
  final InvoiceMerchantMasterBindingService merchantBindingService;

  @override
  State<InvoiceMerchantDecisionReviewSection> createState() =>
      _InvoiceMerchantDecisionReviewSectionState();
}

class _InvoiceMerchantDecisionReviewSectionState
    extends State<InvoiceMerchantDecisionReviewSection> {
  bool _recognitionBindingBusy = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.integration.compose(
      recognizedMerchantName: widget.recognizedMerchantName,
      sellerTaxId: widget.sellerTaxId,
      recognitionSourceLabel: widget.recognitionSourceLabel,
      identityContext: widget.identityContext,
    );

    var state = base;
    final requested = widget.selectedOption;
    if (requested != null && base.candidateFor(requested).available) {
      state = base.select(requested);
    }

    final busy = widget.bindingBusy || _recognitionBindingBusy;
    final recognitionBindingHandler = widget.sellerTaxIdAuthoritative
        ? widget.onConfirmRecognitionBinding ?? _confirmRecognitionBinding
        : null;

    return KeyedSubtree(
      key: InvoiceMerchantDecisionReviewSection.sectionKey,
      child: InvoiceMerchantDecisionComposerCard(
        state: state,
        bindingBusy: busy,
        onSelected: (option) {
          final selection = base.select(option).selection;
          if (selection != null) widget.onSelected(selection);
        },
        onConfirmRecognitionBinding: recognitionBindingHandler,
        onConfirmOfficialBinding: widget.onConfirmOfficialBinding,
      ),
    );
  }

  Future<void> _confirmRecognitionBinding(
    InvoiceMerchantDecisionSelection selection,
  ) async {
    if (!widget.sellerTaxIdAuthoritative ||
        selection.option != InvoiceMerchantDecisionOption.recognition ||
        !selection.requiresMerchantBindingConfirmation) {
      return;
    }

    final currentTaxId = _digits(widget.sellerTaxId);
    final selectedTaxId = _digits(selection.sellerTaxId);
    if (currentTaxId.length != 8 || currentTaxId != selectedTaxId) return;

    final controller = TextEditingController(text: selection.displayName.trim());
    final merchantName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: InvoiceMerchantDecisionReviewSection.recognitionBindingDialogKey,
        title: const Text('以此次辨識建立／綁定正式商家'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('賣方統編：$currentTaxId'),
            const SizedBox(height: 8),
            const Text(
              '可使用消費者熟悉的 MerchantBrand 名稱；不會強制改成官方法定名稱，也不會建立正式交易。',
            ),
            const SizedBox(height: 12),
            TextField(
              key: InvoiceMerchantDecisionReviewSection
                  .recognitionMerchantNameKey,
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '正式商家名稱',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: InvoiceMerchantDecisionReviewSection
                .recognitionBindingDialogConfirmKey,
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            child: const Text('確認建立／綁定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || merchantName == null || merchantName.trim().isEmpty) return;

    // Fail closed again after the dialog: the widget may have rebuilt while the
    // confirmation was open. A changed sellerTaxId or lost authority cannot use
    // the old recognition selection to write MerchantBrand state.
    final latestTaxId = _digits(widget.sellerTaxId);
    if (!widget.sellerTaxIdAuthoritative || latestTaxId != selectedTaxId) return;

    setState(() => _recognitionBindingBusy = true);
    try {
      final result = await widget.merchantBindingService.bind(
        merchantName: merchantName.trim(),
        sellerTaxId: latestTaxId,
        trustedQrSellerIdentifier:
            widget.recognitionSourceLabel.trim().toUpperCase().contains('QR'),
        sourceReference: 'invoice-review-recognition-binding:$latestTaxId',
      );
      if (!mounted || !result.isSuccess || result.merchant == null) return;

      final bound = result.merchant!;
      widget.onSelected(
        InvoiceMerchantDecisionSelection(
          option: InvoiceMerchantDecisionOption.existingMerchantBrand,
          displayName: bound.displayName,
          sellerTaxId: latestTaxId,
          invoiceLiteral: selection.invoiceLiteral,
          requiresMerchantBindingConfirmation: false,
        ),
      );
    } finally {
      if (mounted) setState(() => _recognitionBindingBusy = false);
    }
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
