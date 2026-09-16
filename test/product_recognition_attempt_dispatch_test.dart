import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_review_port.dart';
import 'package:my_finance_app/features/product/product_recognition_attempt_dispatch.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

void main() {
  group('dispatchProductRecognitionAttempt', () {
    test('review-capable client uses exactly one review request', () async {
      final client = _ReviewCapableClient();

      final result = await dispatchProductRecognitionAttempt(
        client: client,
        apiKey: 'test-key',
        model: 'gemini-test',
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(client.reviewCalls, 1);
      expect(client.legacyCalls, 0);
      expect(result.reviewResult, isNotNull);
      expect(result.candidate.productName, 'review candidate');
      expect(result.reviewResult!.candidate, same(result.candidate));
      expect(result.requiresUserReview, isTrue);
      expect(result.canCreateFormalRecord, isFalse);
    });

    test('legacy-only client preserves one legacy request', () async {
      final client = _LegacyOnlyClient();

      final result = await dispatchProductRecognitionAttempt(
        client: client,
        apiKey: 'test-key',
        model: 'gemini-test',
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(client.legacyCalls, 1);
      expect(result.reviewResult, isNull);
      expect(result.candidate.productName, 'legacy candidate');
      expect(result.requiresUserReview, isTrue);
      expect(result.canCreateFormalRecord, isFalse);
    });
  });
}

class _ReviewCapableClient
    implements GeminiProductRecognitionPort, GeminiProductRecognitionReviewPort {
  int legacyCalls = 0;
  int reviewCalls = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    legacyCalls += 1;
    return _candidate('legacy should not run');
  }

  @override
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    reviewCalls += 1;
    return ProductRecognitionReviewResult(
      candidate: _candidate('review candidate'),
    );
  }
}

class _LegacyOnlyClient implements GeminiProductRecognitionPort {
  int legacyCalls = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    legacyCalls += 1;
    return _candidate('legacy candidate');
  }
}

ProductRecognitionCandidate _candidate(String productName) {
  return ProductRecognitionCandidate.fromJson(<String, Object?>{
    'product_name': productName,
    'quantity': 1,
    'unit_price': 10,
    'total_amount': 10,
  });
}
