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

    // Production UI/orchestration must converge on the governed dispatcher.
    // This guard intentionally records the exact migration target without
    // weakening the current legacy path before the coordinator mutation lands.
    expect(dispatcher, contains('dispatchProductRecognitionAttempt'));
    expect(dispatcher, contains('recognizeForReview'));
    expect(dispatcher, contains('canCreateFormalRecord => false'));

    // Until the next production mutation lands there is exactly one legacy
    // physical recognition seam to replace. More than one would make the
    // authorized wiring slice ambiguous and could create duplicate inference.
    expect(RegExp(r'client\.recognize\(').allMatches(source).length, 1);
    expect(
      RegExp(r'recognizeForReview\(').allMatches(source).length,
      0,
    );

    // The coordinator itself must never authorize a formal write.
    expect(source, contains('canCreateFormalRecord => false'));
  });
}
