import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_item_detail_parser.dart';
import 'invoice_review_form_view_model.dart';

class InvoiceReviewQrLineItemEnricher {
  const InvoiceReviewQrLineItemEnricher({
    this.parser = const InvoiceItemDetailParser(),
  });

  final InvoiceItemDetailParser parser;

  InvoiceReviewFormViewModel enrich({
    required InvoiceReviewFormViewModel review,
    required InvoiceAutomaticRecognitionResult recognition,
  }) {
    final pairs = recognition.qrResult?.routingResult?.pairs;
    if (pairs == null || pairs.isEmpty) return review;

    final rightPayload = pairs.first.right?.rawPayload.trim() ?? '';
    if (rightPayload.isEmpty) return review;

    final parsed = parser.parse(rightPayload);
    if (!parsed.isValid) return review;

    final lineItems = parsed.items
        .map(
          (item) => InvoiceReviewLineItemViewModel(
            name: item.name.trim(),
            amountText: _formatAmount(item.amount),
            confidenceLabel: 'QR 明細',
            warnings: parsed.warnings,
          ),
        )
        .where((item) => !item.isBlank)
        .toList(growable: false);

    if (lineItems.isEmpty) return review;

    return InvoiceReviewFormViewModel(
      title: review.title,
      routeReason: review.routeReason,
      disclaimer: review.disclaimer,
      fields: review.fields,
      lineItems: List<InvoiceReviewLineItemViewModel>.unmodifiable(lineItems),
      warnings: review.warnings,
      availableOverrides: review.availableOverrides,
      canOpenReview: review.canOpenReview,
      requiresAcknowledgement: review.requiresAcknowledgement,
      disclaimerAcknowledged: review.disclaimerAcknowledged,
    );
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
