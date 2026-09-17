import 'dart:typed_data';

import 'gemini_product_recognition_client.dart';
import 'gemini_product_recognition_review_port.dart';
import 'product_multi_item_review_proposal.dart';
import 'product_recognition_candidate.dart';
import 'product_recognition_review_result.dart';

/// One physical product-recognition attempt.
///
/// Review-capable clients are invoked only through [recognizeForReview]; the
/// legacy candidate is then taken from that same response. This prevents a
/// review-aware caller from issuing a second Gemini request just to recover the
/// historical single-item candidate.
class ProductRecognitionAttemptResult {
  const ProductRecognitionAttemptResult({
    required this.candidate,
    this.reviewResult,
  });

  final ProductRecognitionCandidate candidate;
  final ProductRecognitionReviewResult? reviewResult;

  /// Optional structured evidence from the same physical recognition request.
  ///
  /// Keeping this projection on the attempt result gives the coordinator one
  /// additive seam for review evidence without allowing presentation code to
  /// invoke Gemini a second time.
  ProductMultiItemReviewProposal? get multiItemProposal =>
      reviewResult?.multiItemProposal;

  bool get hasReviewEvidence => reviewResult != null;
  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;
}

Future<ProductRecognitionAttemptResult> dispatchProductRecognitionAttempt({
  required GeminiProductRecognitionPort client,
  required String apiKey,
  required String model,
  required Uint8List imageBytes,
  required String mimeType,
}) async {
  if (client is GeminiProductRecognitionReviewPort) {
    // Keep the capability view explicit instead of relying on intersection-type
    // promotion across the two independent interface contracts.
    final reviewClient = client as GeminiProductRecognitionReviewPort;
    final reviewResult = await reviewClient.recognizeForReview(
      apiKey: apiKey,
      model: model,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
    return ProductRecognitionAttemptResult(
      candidate: reviewResult.candidate,
      reviewResult: reviewResult,
    );
  }

  final candidate = await client.recognize(
    apiKey: apiKey,
    model: model,
    imageBytes: imageBytes,
    mimeType: mimeType,
  );
  return ProductRecognitionAttemptResult(candidate: candidate);
}
