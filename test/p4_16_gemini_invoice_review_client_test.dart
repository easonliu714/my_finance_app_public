import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_client.dart';

void main() {
  test('sends image with compatible JSON-schema config and parses candidate', () async {
    late http.Request captured;
    final client = GeminiInvoiceReviewClient(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          _responseBody(sellerTaxId: '12345675'),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final candidate = await client.review(
      apiKey: 'TEST_GEMINI_API_KEY_12345678',
      model: 'gemini-3.6-flash',
      imageBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      mimeType: 'image/jpeg',
      localSummary: const <String, Object?>{'status': 'ocrReviewCandidate'},
    );

    expect(captured.headers['x-goog-api-key'], 'TEST_GEMINI_API_KEY_12345678');
    expect(captured.url.path, contains('gemini-3.6-flash:generateContent'));
    expect(captured.body, isNot(contains('TEST_GEMINI_API_KEY_12345678')));
    expect(captured.body, contains('inline_data'));

    final request = Map<String, Object?>.from(
      (jsonDecode(captured.body) as Map).cast<String, Object?>(),
    );
    final generationConfig = Map<String, Object?>.from(
      (request['generationConfig'] as Map).cast<String, Object?>(),
    );
    expect(generationConfig['responseMimeType'], 'application/json');
    expect(generationConfig['responseJsonSchema'], isA<Map>());
    expect(generationConfig.containsKey('responseFormat'), isFalse);
    expect((generationConfig['thinkingConfig'] as Map)['thinkingLevel'], 'low');

    final contents = request['contents'] as List;
    final parts = ((contents.first as Map)['parts'] as List);
    final prompt = (parts.last as Map)['text'].toString();
    expect(prompt, contains('merchantName 必須逐字抄錄'));
    expect(prompt, contains('不得自行補成 00'));
    expect(prompt, contains('不得把任意 NO./No. 號碼直接當成統編'));
    expect(prompt, contains('位於商家 identity header 附近'));
    expect(prompt, contains('不得把「115年5-6月份」這類發票期別誤當交易日期'));

    expect(candidate.invoiceNumber, 'AB12345678');
    expect(candidate.sellerTaxId, '12345675');
    expect(candidate.totalAmount, 120);
    expect(candidate.lineItems.single.name, '商品');
    expect(candidate.canCreateFormalRecord, isFalse);
  });

  test('8-digit seller tax ID checksum mismatch is blanked with review warning', () async {
    final client = GeminiInvoiceReviewClient(
      client: MockClient(
        (_) async => http.Response(
          _responseBody(sellerTaxId: '12345678'),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );

    final candidate = await client.review(
      apiKey: 'KEY_1',
      model: 'gemini-3.6-flash',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/png',
    );

    expect(candidate.sellerTaxId, isEmpty);
    expect(
      candidate.warnings,
      contains('AI 統一編號校驗未通過，已保持空白。'),
    );
  });

  test('marks quota failure as retryable for the next key', () async {
    final client = GeminiInvoiceReviewClient(
      client: MockClient((_) async => http.Response('{}', 429)),
    );
    await expectLater(
      client.review(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/png',
      ),
      throwsA(
        isA<GeminiInvoiceReviewException>()
            .having(
              (error) => error.kind,
              'kind',
              GeminiInvoiceReviewFailureKind.quota,
            )
            .having((error) => error.retryWithNextKey, 'retry', isTrue),
      ),
    );
  });

  test('does not rotate keys for malformed successful response', () async {
    final client = GeminiInvoiceReviewClient(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      client.review(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/webp',
      ),
      throwsA(
        isA<GeminiInvoiceReviewException>()
            .having(
              (error) => error.kind,
              'kind',
              GeminiInvoiceReviewFailureKind.malformedResponse,
            )
            .having((error) => error.retryWithNextKey, 'retry', isFalse),
      ),
    );
  });

  test('rejects unsupported image before making a network request', () async {
    var requestCount = 0;
    final client = GeminiInvoiceReviewClient(
      client: MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.review(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'application/pdf',
      ),
      throwsA(
        isA<GeminiInvoiceReviewException>().having(
          (error) => error.kind,
          'kind',
          GeminiInvoiceReviewFailureKind.invalidInput,
        ),
      ),
    );
    expect(requestCount, 0);
  });
}

String _responseBody({required String sellerTaxId}) {
  return jsonEncode(<String, Object?>{
    'candidates': <Object?>[
      <String, Object?>{
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{
              'text': jsonEncode(<String, Object?>{
                'invoiceNumber': 'AB12345678',
                'invoicePeriod': '115年03-04月',
                'sellerTaxId': sellerTaxId,
                'invoiceDate': '2026-04-18',
                'invoiceTime': '14:59:52',
                'merchantName': '測試商店',
                'totalAmount': 120,
                'lineItems': <Object?>[
                  <String, Object?>{
                    'name': '商品',
                    'quantity': 1,
                    'unitPrice': 120,
                    'amount': 120,
                  },
                ],
                'confidence': <String, Object?>{
                  'invoiceNumber': 0.99,
                  'invoicePeriod': 0.98,
                  'sellerTaxId': 0.95,
                  'invoiceDate': 0.94,
                  'invoiceTime': 0.93,
                  'merchantName': 0.9,
                  'totalAmount': 0.97,
                  'lineItems': 0.8,
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
