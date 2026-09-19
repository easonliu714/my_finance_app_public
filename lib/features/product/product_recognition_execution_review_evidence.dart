import 'product_multi_item_review_proposal.dart';
import 'product_recognition_review_result.dart';

/// Proposal-only review evidence attached to a successful product-recognition
/// execution.
///
/// This carrier deliberately has no persistence or transaction-writing API.
/// It exists so the coordinator can propagate structured evidence from the
/// same physical recognition request without giving presentation code another
/// Gemini invocation seam.
class ProductRecognitionExecutionReviewEvidence {
  const ProductRecognitionExecutionReviewEvidence._({
    required this.reviewResult,
  });

  factory ProductRecognitionExecutionReviewEvidence.fromReviewResult(
    ProductRecognitionReviewResult reviewResult,
  ) {
    return ProductRecognitionExecutionReviewEvidence._(
      reviewResult: reviewResult,
    );
  }

  /// Converts nullable same-request review evidence at the coordinator seam.
  ///
  /// Failed or legacy-only attempts remain null; this helper never synthesizes
  /// evidence and has no network or formal-write capability.
  static ProductRecognitionExecutionReviewEvidence? fromNullableReviewResult(
    ProductRecognitionReviewResult? reviewResult,
  ) {
    if (reviewResult == null) return null;
    return ProductRecognitionExecutionReviewEvidence.fromReviewResult(
      reviewResult,
    );
  }

  final ProductRecognitionReviewResult reviewResult;

  ProductMultiItemReviewProposal? get multiItemProposal =>
      reviewResult.multiItemProposal;

  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;

  Map<String, Object?> toSafeSummary() => <String, Object?>{
        'requiresUserReview': requiresUserReview,
        'canCreateFormalRecord': canCreateFormalRecord,
        'hasMultiItemProposal': multiItemProposal != null,
      };
}
