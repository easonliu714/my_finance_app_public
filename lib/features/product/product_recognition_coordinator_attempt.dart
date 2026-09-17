import 'dart:typed_data';

import 'gemini_product_recognition_client.dart';
import 'product_recognition_attempt_dispatch.dart';
import 'product_recognition_candidate.dart';
import 'product_recognition_execution_review_evidence.dart';

/// Bounded coordinator-facing projection of one physical recognition attempt.
///
/// This adapter deliberately exposes only the legacy candidate plus optional
/// proposal-only review evidence from the same request. It has no persistence
/// or formal-accounting write authority.
class ProductRecognitionCoordinatorAttempt {
  const ProductRecognitionCoordinatorAttempt({
    required this.candidate,
    this.reviewEvidence,
  });

  final ProductRecognitionCandidate candidate;
  final ProductRecognitionExecutionReviewEvidence? reviewEvidence;

  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;
}

/// Executes exactly one governed physical product-recognition attempt.
///
/// Review-capable clients remain single-request because the underlying
/// dispatcher obtains the legacy candidate and review evidence from the same
/// `recognizeForReview` response. Legacy clients keep their historical single
/// `recognize` request.
Future<ProductRecognitionCoordinatorAttempt>
    dispatchProductRecognitionCoordinatorAttempt({
  required GeminiProductRecognitionPort client,
  required String apiKey,
  required String model,
  required Uint8List imageBytes,
  required String mimeType,
}) async {
  final attempt = await dispatchProductRecognitionAttempt(
    client: client,
    apiKey: apiKey,
    model: model,
    imageBytes: imageBytes,
    mimeType: mimeType,
  );
  return ProductRecognitionCoordinatorAttempt(
    candidate: attempt.candidate,
    reviewEvidence: attempt.executionReviewEvidence,
  );
}
