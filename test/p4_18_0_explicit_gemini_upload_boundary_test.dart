import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Frozen Review requires explicit Gemini image send', () {
    final source = File('lib/features/invoice/invoice_frozen_review_page.dart')
        .readAsStringSync();
    expect(
      source,
      isNot(contains('await _runGemini(local, forceReview: false);')),
    );
    expect(source, contains('送出至 Gemini 必要覆核'));
    expect(source, contains('只有你明確按下按鈕才會送出目前發票影像'));
    expect(source, contains('我已核對 Local 與 Gemini 結果'));
  });
}
