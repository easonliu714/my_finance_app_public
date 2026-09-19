import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinator review wiring contract stays explicit and single-path', () {
    final source = File(
      'lib/features/product/gemini_product_recognition_coordinator.dart',
    ).readAsStringSync();
    final dispatcher = File(
      'lib/features/product/product_recognition_attempt_dispatch.dart',
    ).readAsStringSync();
    final coordinatorAttempt = File(
      'lib/features/product/product_recognition_coordinator_attempt.dart',
    ).readAsStringSync();
    final evidenceCarrier = File(
      'lib/features/product/product_recognition_execution_review_evidence.dart',
    ).readAsStringSync();

    // Production coordinator must have no direct legacy physical request seam.
    // Exactly one governed coordinator-attempt dispatch owns the physical call.
    expect(RegExp(r'client\.recognize\(').allMatches(source).length, 0);
    expect(
      RegExp(r'dispatchProductRecognitionCoordinatorAttempt\(')
          .allMatches(source)
          .length,
      1,
    );
    expect(source, contains('reviewEvidence: governedAttempt.reviewEvidence'));
    expect(source, contains('ProductRecognitionExecutionReviewEvidence? reviewEvidence'));

    // The lower dispatcher remains the sole capability split: review-capable
    // clients use one recognizeForReview request; legacy clients use one
    // recognize request. Neither path is allowed to become a double request.
    expect(dispatcher, contains('dispatchProductRecognitionAttempt'));
    expect(dispatcher, contains('canCreateFormalRecord => false'));
    expect(
      RegExp(r'reviewClient\.recognizeForReview\(').allMatches(dispatcher).length,
      1,
    );
    expect(RegExp(r'client\.recognize\(').allMatches(dispatcher).length, 1);
    expect(
      RegExp(r'dispatchProductRecognitionAttempt\(')
          .allMatches(coordinatorAttempt)
          .length,
      1,
    );

    // Evidence is proposal-only and cannot introduce a second network seam or
    // authorize a formal accounting write.
    expect(evidenceCarrier, isNot(contains('recognizeForReview(')));
    expect(evidenceCarrier, isNot(contains('client.recognize(')));
    expect(evidenceCarrier, contains('canCreateFormalRecord => false'));
    expect(source, contains('canCreateFormalRecord => false'));
  });
}
