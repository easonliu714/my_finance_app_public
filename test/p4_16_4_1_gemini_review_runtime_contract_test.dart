import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gemini review runtime is bounded for Gemini 3 invoice extraction', () {
    final client = File(
      'lib/features/invoice/gemini/gemini_invoice_review_client.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/invoice/gemini/gemini_invoice_validation_page.dart',
    ).readAsStringSync();

    expect(client, contains('Duration(seconds: 75)'));
    expect(client, contains("'thinkingLevel': 'low'"));
    expect(client, contains("RegExp(r'^gemini-3')"));
    expect(client, contains("'maxOutputTokens': 4096"));
    expect(page, contains('Key 覆核嘗試'));
    expect(page, contains('attempt.maskedKey'));
    expect(page, contains('attempt.message'));
  });
}
