import 'dart:typed_data';

import 'product_recognition_review_result.dart';

/// Additive recognition capability for explicit-review consumers.
///
/// This contract intentionally does not replace the legacy
/// `GeminiProductRecognitionPort`. Callers that only understand the historical
/// single-item candidate remain on that port. New review UI may opt into this
/// capability to receive separately decoded multi-item evidence.
///
/// Implementations must preserve the governance boundary that recognition is
/// proposal evidence only. Returning a [ProductRecognitionReviewResult] never
/// authorizes a transaction, merchant/category binding, or master-data write.
abstract interface class GeminiProductRecognitionReviewPort {
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  });
}
