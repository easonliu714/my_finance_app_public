import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_review_port.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_recognition_coordinator_attempt.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

class _ReviewClient
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
    legacyCalls++;
    throw StateError('review-capable client must not use legacy request');
  }

  @override
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    reviewCalls++;
    return const ProductRecognitionReviewResult(
      candidate: ProductRecognitionCandidate(productName: '測試商品'),
    );
  }
}

class _LegacyClient implements GeminiProductRecognitionPort {
  int legacyCalls = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    legacyCalls++;
    return const ProductRecognitionCandidate(productName: '舊版商品');
  }
}

void main() {
  test(
    'coordinator attempt keeps review-capable recognition single-request',
    () async {
      final client = _ReviewClient();
      final result = await dispatchProductRecognitionCoordinatorAttempt(
        client: client,
        apiKey: 'test-key',
        model: 'test-model',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/jpeg',
      );

      expect(client.reviewCalls, 1);
      expect(client.legacyCalls, 0);
      expect(result.reviewEvidence, isNotNull);
      expect(result.requiresUserReview, isTrue);
      expect(result.canCreateFormalRecord, isFalse);
    },
  );

  test(
    'coordinator attempt preserves legacy single-request candidate parity',
    () async {
      final client = _LegacyClient();
      final result = await dispatchProductRecognitionCoordinatorAttempt(
        client: client,
        apiKey: 'test-key',
        model: 'test-model',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/jpeg',
      );

      expect(client.legacyCalls, 1);
      expect(result.candidate.productName, '舊版商品');
      expect(result.reviewEvidence, isNull);
      expect(result.requiresUserReview, isTrue);
      expect(result.canCreateFormalRecord, isFalse);
    },
  );
}
