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
    final evidenceCarrier = File(
      'lib/features/product/product_recognition_execution_review_evidence.dart',
    ).readAsStringSync();

    // Production UI/orchestration must converge on the governed dispatcher.
    expect(dispatcher, contains('dispatchProductRecognitionAttempt'));
    expect(dispatcher, contains('recognizeForReview'));
    expect(dispatcher, contains('canCreateFormalRecord => false'));

    // Before the bounded coordinator mutation lands there is exactly one
    // legacy physical seam. The dispatcher owns both capability branches and
    // the evidence carrier must not introduce any network invocation API.
    expect(RegExp(r'client\.recognize\(').allMatches(source).length, 1);
    expect(RegExp(r'recognizeForReview\(').allMatches(source).length, 0);
    expect(RegExp(r'reviewClient\.recognizeForReview\(').allMatches(dispatcher).length, 1);
    expect(RegExp(r'client\.recognize\(').allMatches(dispatcher).length, 1);
    expect(evidenceCarrier, isNot(contains('recognizeForReview(')));
    expect(evidenceCarrier, isNot(contains('client.recognize(')));
    expect(evidenceCarrier, contains('canCreateFormalRecord => false'));

    // The coordinator itself must never authorize a formal write.
    expect(source, contains('canCreateFormalRecord => false'));
  });
}
