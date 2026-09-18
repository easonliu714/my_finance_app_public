import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #29 review orchestration governance', () {
    test('existing coordinator remains the only recognition network seam', () {
      final coordinator = File(
        'lib/features/product/gemini_product_recognition_coordinator.dart',
      ).readAsStringSync();
      final capturePage = File(
        'lib/features/product/product_capture_page.dart',
      ).readAsStringSync();

      expect(coordinator, contains('class ProductRecognitionCoordinator'));
      expect(coordinator, contains('final GeminiProductRecognitionPort client;'));
      expect(
        coordinator,
        contains('await dispatchProductRecognitionCoordinatorAttempt('),
      );
      expect(coordinator, isNot(contains('await client.recognize(')));

      // ProductCapturePage must not create a second Gemini inference path.
      expect(capturePage, isNot(contains('.recognizeForReview(')));
      expect(capturePage, isNot(contains('GeminiProductRecognitionReviewPort')));
    });

    test('execution remains explicit-review only and cannot authorize writes', () {
      final coordinator = File(
        'lib/features/product/gemini_product_recognition_coordinator.dart',
      ).readAsStringSync();

      expect(coordinator, contains('class ProductRecognitionExecution'));
      expect(coordinator, contains('bool get canCreateFormalRecord => false;'));
      expect(coordinator, contains('bool get requiresUserReview => candidate != null;'));
    });
  });
}
