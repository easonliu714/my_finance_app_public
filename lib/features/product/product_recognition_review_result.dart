import 'product_multi_item_review_proposal.dart';
import 'product_multi_item_transport_evidence.dart';
import 'product_recognition_candidate.dart';

/// Recognition result prepared for explicit user review.
///
/// The legacy [candidate] remains the single-item authority. Optional structured
/// `lines` are decoded separately and can only produce a review proposal; they
/// never authorize a formal accounting or master-data write.
class ProductRecognitionReviewResult {
  const ProductRecognitionReviewResult({
    required this.candidate,
    this.multiItemProposal,
  });

  final ProductRecognitionCandidate candidate;
  final ProductMultiItemReviewProposal? multiItemProposal;

  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;

  static ProductRecognitionReviewResult fromCandidateJson(
    Map<String, Object?> candidateJson,
  ) {
    final candidate = ProductRecognitionCandidate.fromJson(candidateJson);
    final evidence = ProductMultiItemTransportEvidence.fromCandidateJson(
      candidateJson,
    );
    return ProductRecognitionReviewResult(
      candidate: candidate,
      multiItemProposal: evidence?.assembleReviewProposal(
        sourceCandidate: candidate,
      ),
    );
  }
}
