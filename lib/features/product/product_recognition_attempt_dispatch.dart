import 'dart:typed_data';

import 'gemini_product_recognition_client.dart';
import 'gemini_product_recognition_review_port.dart';
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
    final reviewResult = await client.recognizeForReview(
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
