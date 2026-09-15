import 'product_multi_item_review_proposal.dart';
import 'product_recognition_candidate.dart';

/// Converts explicit recognition line evidence into a review-only proposal.
///
/// This assembler is deliberately transport-agnostic. It does not call Gemini,
/// create master data, or write transactions. Invalid or incomplete line values
/// are preserved as ambiguous review evidence rather than inferred.
class ProductMultiItemProposalAssembler {
  const ProductMultiItemProposalAssembler();

  ProductMultiItemReviewProposal assemble({
    required ProductRecognitionCandidate sourceCandidate,
    required Iterable<Map<String, Object?>> rawLines,
  }) {
    final lines = rawLines
        .map(_lineFromEvidence)
        .toList(growable: false);
    return ProductMultiItemReviewProposal(
      lines: List<ProductReviewLineProposal>.unmodifiable(lines),
      sourceCandidate: sourceCandidate,
    );
  }

  ProductReviewLineProposal _lineFromEvidence(Map<String, Object?> raw) {
    return ProductReviewLineProposal(
      name: _text(raw['name']),
      quantity: _positive(raw['quantity']),
      unitPrice: _nonNegative(raw['unitPrice']),
      subtotal: _nonNegative(raw['subtotal']),
      rawEvidence: _text(raw['rawEvidence']),
    );
  }

  String _text(Object? value) => value?.toString().trim() ?? '';

  double? _positive(Object? value) {
    final parsed = _finite(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  double? _nonNegative(Object? value) {
    final parsed = _finite(value);
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  double? _finite(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}
