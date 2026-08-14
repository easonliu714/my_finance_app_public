import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_client.dart';

void main() {
  test('Gemini 3 invoice review uses low thinking and 75 second timeout', () async {
    late http.Request captured;
    final client = GeminiInvoiceReviewClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          _successBody(),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    expect(client.timeout, const Duration(seconds: 75));
    await client.review(
      apiKey: 'KEY_1',
      model: 'gemini-3.6-flash',
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      mimeType: 'image/jpeg',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final config = body['generationConfig'] as Map<String, dynamic>;
    expect(config['maxOutputTokens'], 4096);
    expect(
      (config['thinkingConfig'] as Map<String, dynamic>)['thinkingLevel'],
      'low',
    );
  });

  test('Gemini 2 model does not receive Gemini 3 thinkingLevel', () async {
    late http.Request captured;
    final client = GeminiInvoiceReviewClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          _successBody(),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    await client.review(
      apiKey: 'KEY_1',
      model: 'gemini-2.5-flash-lite',
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      mimeType: 'image/jpeg',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final config = body['generationConfig'] as Map<String, dynamic>;
    expect(config.containsKey('thinkingConfig'), isFalse);
  });

  test('HTTP failure exposes bounded Google reason without exposing key', () async {
    final client = GeminiInvoiceReviewClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 400,
              'status': 'INVALID_ARGUMENT',
              'message': 'Request schema is not supported.',
            },
          }),
          400,
        ),
      ),
    );

    await expectLater(
      client.review(
        apiKey: 'TEST_GEMINI_API_KEY_12345678',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/png',
      ),
      throwsA(
        isA<GeminiInvoiceReviewException>()
            .having((error) => error.message, 'message', contains('INVALID_ARGUMENT'))
            .having(
              (error) => error.message,
              'key-safe',
              isNot(contains('TEST_GEMINI_API_KEY_12345678')),
            ),
      ),
    );
  });
}

String _successBody() {
  return jsonEncode(<String, Object?>{
    'candidates': <Object?>[
      <String, Object?>{
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{
              'text': jsonEncode(<String, Object?>{
                'invoiceNumber': 'AB12345678',
                'invoicePeriod': '115年07-08月',
                'sellerTaxId': null,
                'invoiceDate': '2026-08-08',
                'invoiceTime': '10:00:00',
                'merchantName': '測試商店',
                'totalAmount': 100,
                'lineItems': <Object?>[],
                'confidence': <String, Object?>{
                  'invoiceNumber': 0.99,
                  'invoicePeriod': 0.9,
                  'sellerTaxId': 0.1,
                  'invoiceDate': 0.95,
                  'invoiceTime': 0.9,
                  'merchantName': 0.9,
                  'totalAmount': 0.95,
                  'lineItems': 0.5,
                },
                'warnings': <String>[],
              }),
            },
          ],
        },
      },
    ],
  });
}
