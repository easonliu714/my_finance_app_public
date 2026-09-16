import 'product_recognition_candidate.dart';
import 'product_recognition_review_decoder.dart';
import 'product_recognition_review_result.dart';

/// Immutable decode boundary for one Gemini candidate JSON payload.
///
/// Both the legacy single-item consumer and the additive explicit-review
/// consumer must derive from this same payload. This prevents a review flow
/// from requiring a second Gemini request or interpreting a different response.
/// The review result remains proposal evidence only and never authorizes a
/// transaction, merchant/category binding, or master-data write.
final class GeminiProductRecognitionCandidatePayload {
  GeminiProductRecognitionCandidatePayload._({
    required this.candidateJson,
    required this.legacyCandidate,
    required this.reviewResult,
  });

  factory GeminiProductRecognitionCandidatePayload.fromCandidateJson(
    Map<String, Object?> candidateJson,
  ) {
    final frozenJson = Map<String, Object?>.unmodifiable(candidateJson);
    return GeminiProductRecognitionCandidatePayload._(
      candidateJson: frozenJson,
      legacyCandidate: ProductRecognitionCandidate.fromJson(frozenJson),
      reviewResult: ProductRecognitionReviewDecoder.decode(frozenJson),
    );
  }

  final Map<String, Object?> candidateJson;
  final ProductRecognitionCandidate legacyCandidate;
  final ProductRecognitionReviewResult reviewResult;
}
