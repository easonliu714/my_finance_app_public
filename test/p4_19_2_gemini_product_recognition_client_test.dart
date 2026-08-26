import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';

void main() {
  test('sends exact staged bytes with structured schema and parses candidate', () async {
    late http.Request captured;
    final frozenBytes = Uint8List.fromList(<int>[9, 7, 5, 3, 1]);
    final client = GeminiProductRecognitionClient(
      client: MockClient((request) async {
        captured = request;
        return _utf8Response(_responseBody(), 200);
      }),
    );

    final candidate = await client.recognize(
      apiKey: 'TEST_GEMINI_API_KEY_12345678',
      model: 'gemini-3.6-flash',
      imageBytes: frozenBytes,
      mimeType: 'image/jpeg',
    );

    expect(captured.headers['x-goog-api-key'], 'TEST_GEMINI_API_KEY_12345678');
    expect(captured.url.path, contains('gemini-3.6-flash:generateContent'));
    expect(captured.body, isNot(contains('TEST_GEMINI_API_KEY_12345678')));

    final request = Map<String, Object?>.from(
      (jsonDecode(captured.body) as Map).cast<String, Object?>(),
    );
    final generationConfig = Map<String, Object?>.from(
      (request['generationConfig'] as Map).cast<String, Object?>(),
    );
    expect(generationConfig['responseMimeType'], 'application/json');
    expect(generationConfig['responseJsonSchema'], isA<Map>());
    expect((generationConfig['thinkingConfig'] as Map)['thinkingLevel'], 'low');

    final contents = request['contents'] as List;
    final parts = ((contents.first as Map)['parts'] as List);
    final inlineData = Map<String, Object?>.from(
      ((parts.first as Map)['inline_data'] as Map).cast<String, Object?>(),
    );
    expect(inlineData['mime_type'], 'image/jpeg');
    expect(base64Decode(inlineData['data']! as String), frozenBytes);

    final prompt = (parts.last as Map)['text'].toString();
    expect(prompt, contains('不得為了完成記帳而猜測價格、店家、數量或品名'));
    expect(prompt, contains('商品品牌、製造商、代理商不能直接當成 merchantName'));
    expect(prompt, contains('不得自行用 quantity × unitPrice 填入 totalAmount'));
    expect(prompt, contains('不要自行建立多筆交易'));

    expect(candidate.productName, '無糖綠茶');
    expect(candidate.quantity, 2);
    expect(candidate.unitPrice, 35);
    expect(candidate.totalAmount, 70);
    expect(candidate.categorySuggestion, '飲料水果');
    expect(candidate.merchantName, '測試商店');
    expect(candidate.canCreateFormalRecord, isFalse);
  });

  test('nullable uncertain fields stay empty without invented values', () async {
    final client = GeminiProductRecognitionClient(
      client: MockClient(
        (_) async => _utf8Response(
          _responseBody(
            payload: <String, Object?>{
              'productName': '品牌 A',
              'quantity': null,
              'unitPrice': null,
              'totalAmount': null,
              'categorySuggestion': null,
              'merchantName': null,
              'recognizedText': '品牌 A',
              'confidence': <String, Object?>{'productName': 0.7},
              'warnings': <String>['price_not_visible'],
            },
          ),
          200,
        ),
      ),
    );

    final candidate = await client.recognize(
      apiKey: 'KEY_1',
      model: 'gemini-3.6-flash',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/png',
    );

    expect(candidate.productName, '品牌 A');
    expect(candidate.quantity, isNull);
    expect(candidate.unitPrice, isNull);
    expect(candidate.totalAmount, isNull);
    expect(candidate.resolvedTotalAmount, isNull);
    expect(candidate.merchantName, isEmpty);
    expect(candidate.warnings, contains('price_not_visible'));
  });

  test('429 is quota retryable, while 400 fails fast', () async {
    final quotaClient = GeminiProductRecognitionClient(
      client: MockClient((_) async => _utf8Response('{}', 429)),
    );
    await expectLater(
      quotaClient.recognize(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/png',
      ),
      throwsA(
        isA<GeminiProductRecognitionException>()
            .having(
              (error) => error.kind,
              'kind',
              GeminiProductRecognitionFailureKind.quota,
            )
            .having((error) => error.retryWithNextKey, 'retry', isTrue),
      ),
    );

    final rejectedClient = GeminiProductRecognitionClient(
      client: MockClient((_) async => _utf8Response('{}', 400)),
    );
    await expectLater(
      rejectedClient.recognize(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/png',
      ),
      throwsA(
        isA<GeminiProductRecognitionException>()
            .having(
              (error) => error.kind,
              'kind',
              GeminiProductRecognitionFailureKind.requestRejected,
            )
            .having((error) => error.retryWithNextKey, 'retry', isFalse),
      ),
    );
  });

  test('401 and 503 are classified without exposing raw key', () async {
    for (final entry in <(int, GeminiProductRecognitionFailureKind)>[
      (401, GeminiProductRecognitionFailureKind.authentication),
      (503, GeminiProductRecognitionFailureKind.serviceUnavailable),
    ]) {
      final client = GeminiProductRecognitionClient(
        client: MockClient(
          (_) async => _utf8Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'status': 'ERROR',
                'message': 'Key AIzaSECRET_123 is unavailable',
              },
            }),
            entry.$1,
          ),
        ),
      );

      try {
        await client.recognize(
          apiKey: 'AIzaSECRET_123',
          model: 'gemini-3.6-flash',
          imageBytes: Uint8List.fromList(<int>[1]),
          mimeType: 'image/webp',
        );
        fail('expected recognition exception');
      } on GeminiProductRecognitionException catch (error) {
        expect(error.kind, entry.$2);
        expect(error.message, isNot(contains('AIzaSECRET_123')));
        expect(error.message, contains('API_KEY'));
      }
    }
  });

  test('safety block and malformed success are fail-fast', () async {
    final blocked = GeminiProductRecognitionClient(
      client: MockClient(
        (_) async => _utf8Response(
          jsonEncode(<String, Object?>{
            'promptFeedback': <String, Object?>{'blockReason': 'SAFETY'},
          }),
          200,
        ),
      ),
    );
    await expectLater(
      blocked.recognize(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/jpeg',
      ),
      throwsA(
        isA<GeminiProductRecognitionException>()
            .having(
              (error) => error.kind,
              'kind',
              GeminiProductRecognitionFailureKind.safetyBlocked,
            )
            .having((error) => error.retryWithNextKey, 'retry', isFalse),
      ),
    );

    final malformed = GeminiProductRecognitionClient(
      client: MockClient((_) async => _utf8Response('{}', 200)),
    );
    await expectLater(
      malformed.recognize(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/jpeg',
      ),
      throwsA(
        isA<GeminiProductRecognitionException>().having(
          (error) => error.kind,
          'kind',
          GeminiProductRecognitionFailureKind.malformedResponse,
        ),
      ),
    );
  });

  test('empty candidate is rejected as malformed response', () async {
    final client = GeminiProductRecognitionClient(
      client: MockClient(
        (_) async => _utf8Response(
          _responseBody(
            payload: <String, Object?>{
              'productName': null,
              'quantity': null,
              'unitPrice': null,
              'totalAmount': null,
              'categorySuggestion': null,
              'merchantName': null,
              'recognizedText': '背景文字',
              'confidence': <String, Object?>{},
              'warnings': <String>['no_reliable_product_candidate'],
            },
          ),
          200,
        ),
      ),
    );

    await expectLater(
      client.recognize(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'image/jpeg',
      ),
      throwsA(
        isA<GeminiProductRecognitionException>().having(
          (error) => error.kind,
          'kind',
          GeminiProductRecognitionFailureKind.malformedResponse,
        ),
      ),
    );
  });

  test('invalid input is rejected before any network request', () async {
    var requests = 0;
    final client = GeminiProductRecognitionClient(
      client: MockClient((_) async {
        requests += 1;
        return _utf8Response('{}', 200);
      }),
    );

    await expectLater(
      client.recognize(
        apiKey: 'KEY_1',
        model: 'gemini-3.6-flash',
        imageBytes: Uint8List.fromList(<int>[1]),
        mimeType: 'application/pdf',
      ),
      throwsA(
        isA<GeminiProductRecognitionException>().having(
          (error) => error.kind,
          'kind',
          GeminiProductRecognitionFailureKind.invalidInput,
        ),
      ),
    );
    expect(requests, 0);
  });
}

http.Response _utf8Response(String body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(body),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

String _responseBody({Map<String, Object?>? payload}) {
  final candidate = payload ??
      <String, Object?>{
        'productName': '無糖綠茶',
        'quantity': 2,
        'unitPrice': 35,
        'totalAmount': 70,
        'categorySuggestion': '飲料水果',
        'merchantName': '測試商店',
        'recognizedText': '無糖綠茶 35 元 × 2',
        'confidence': <String, Object?>{
          'productName': 0.98,
          'quantity': 0.95,
          'unitPrice': 0.9,
          'totalAmount': 0.92,
          'categorySuggestion': 0.8,
          'merchantName': 0.75,
        },
        'warnings': <String>[],
      };
  return jsonEncode(<String, Object?>{
    'candidates': <Object?>[
      <String, Object?>{
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': jsonEncode(candidate)},
          ],
        },
      },
    ],
  });
}
