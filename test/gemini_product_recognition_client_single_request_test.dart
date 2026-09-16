import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';

void main() {
  test('legacy recognition performs exactly one Gemini HTTP request', () async {
    var requestCount = 0;
    final httpClient = MockClient((http.Request request) async {
      requestCount += 1;
      expect(request.method, 'POST');
      expect(request.url.host, 'generativelanguage.googleapis.com');
      return http.Response(
        jsonEncode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{
                    'text': jsonEncode(<String, Object?>{
                      'productName': '測試商品',
                      'quantity': 1,
                      'unitPrice': 25,
                      'totalAmount': 25,
                      'categorySuggestion': null,
                      'merchantName': null,
                      'recognizedText': '測試商品 25',
                      'confidence': <String, Object?>{},
                      'warnings': <String>[],
                    }),
                  },
                ],
              },
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final client = GeminiProductRecognitionClient(client: httpClient);

    final candidate = await client.recognize(
      apiKey: 'test-key',
      model: 'gemini-test',
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      mimeType: 'image/jpeg',
    );

    expect(requestCount, 1);
    expect(candidate.productName, '測試商品');
    expect(candidate.hasUsefulCandidate, isTrue);
  });
}
