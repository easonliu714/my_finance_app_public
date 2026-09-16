import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_candidate_payload.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_review_port.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

/// Regression harness for the production integration slice.
///
/// The real Gemini client must eventually satisfy this same observable
/// contract: one review invocation consumes one transport response, exposes
/// review-only evidence, and never acquires formal-write authority.
final class _SingleResponseReviewHarness
    implements GeminiProductRecognitionReviewPort {
  _SingleResponseReviewHarness(this._candidateJson);

  final Map<String, Object?> _candidateJson;
  int transportInvocationCount = 0;

  @override
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    transportInvocationCount += 1;
    final payload =
        GeminiProductRecognitionCandidatePayload.fromCandidateJson(_candidateJson);
    return payload.reviewResult;
  }
}

void main() {
  test('one review invocation consumes exactly one response payload', () async {
    final harness = _SingleResponseReviewHarness(<String, Object?>{
      'productName': '牛奶',
      'warnings': <String>[],
      'lines': <Object?>[
        <String, Object?>{
          'productName': '牛奶',
          'quantity': 1,
          'unitPrice': 65,
          'lineTotal': 65,
        },
      ],
    });

    final result = await harness.recognizeForReview(
      apiKey: 'fixture-key',
      model: 'fixture-model',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/jpeg',
    );

    expect(harness.transportInvocationCount, 1);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('malformed line evidence remains review-only and fail closed', () async {
    final harness = _SingleResponseReviewHarness(<String, Object?>{
      'productName': '組合商品',
      'warnings': <String>['multiple_products_visible'],
      'lines': <Object?>[
        <String, Object?>{
          'productName': 'A',
          'quantity': 1,
          'unitPrice': 20,
          'lineTotal': 999,
        },
      ],
    });

    final result = await harness.recognizeForReview(
      apiKey: 'fixture-key',
      model: 'fixture-model',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/jpeg',
    );

    expect(harness.transportInvocationCount, 1);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });
}
