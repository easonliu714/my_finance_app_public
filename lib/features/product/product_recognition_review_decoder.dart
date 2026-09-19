import 'product_recognition_review_result.dart';

/// Decodes a recognition candidate payload into an explicit-review result.
///
/// This adapter is deliberately downstream of transport JSON decoding and
/// upstream of UI presentation. It preserves the legacy candidate authority,
/// keeps optional multi-item evidence separate, and never authorizes a formal
/// transaction or master-data write.
abstract final class ProductRecognitionReviewDecoder {
  static ProductRecognitionReviewResult decode(
    Map<String, Object?> candidateJson,
  ) {
    return ProductRecognitionReviewResult.fromCandidateJson(candidateJson);
  }
}
