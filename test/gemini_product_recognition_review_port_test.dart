import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_review_port.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

void main() {
  test('additive review port returns review-only result without formal authority',
      () async {
    final port = _FakeReviewPort();

    final result = await port.recognizeForReview(
      apiKey: 'test-key',
      model: 'test-model',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/jpeg',
    );

    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.multiItemProposal, isNull);
  });
}

class _FakeReviewPort implements GeminiProductRecognitionReviewPort {
  @override
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    return ProductRecognitionReviewResult.fromCandidateJson(
      <String, Object?>{
        'productName': '測試商品',
        'warnings': <String>[],
      },
    );
  }
}
