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
        _geminiResponse(<String, Object?>{
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

  test('review recognition performs exactly one Gemini HTTP request', () async {
    var requestCount = 0;
    final httpClient = MockClient((http.Request request) async {
      requestCount += 1;
      expect(request.method, 'POST');
      expect(request.url.host, 'generativelanguage.googleapis.com');
      return http.Response(
        _geminiResponse(<String, Object?>{
          'productName': '測試商品',
          'quantity': 2,
          'unitPrice': 25,
          'totalAmount': 50,
          'categorySuggestion': null,
          'merchantName': null,
          'recognizedText': '測試商品 2 x 25',
          'confidence': <String, Object?>{},
          'warnings': <String>[],
          'lines': <Object?>[
            <String, Object?>{
              'productName': '測試商品',
              'quantity': 2,
              'unitPrice': 25,
              'lineTotal': 50,
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final client = GeminiProductRecognitionClient(client: httpClient);

    final result = await client.recognizeForReview(
      apiKey: 'test-key',
      model: 'gemini-test',
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      mimeType: 'image/jpeg',
    );

    expect(requestCount, 1);
    expect(result.candidate.productName, '測試商品');
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('malformed lines evidence fails closed without a second request', () async {
    var requestCount = 0;
    final httpClient = MockClient((http.Request request) async {
      requestCount += 1;
      return http.Response(
        _geminiResponse(<String, Object?>{
          'productName': '測試商品',
          'quantity': 1,
          'unitPrice': 50,
          'totalAmount': 50,
          'recognizedText': '測試商品 50',
          'confidence': <String, Object?>{},
          'warnings': <String>[],
          'lines': 'not-a-list',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final client = GeminiProductRecognitionClient(client: httpClient);

    final result = await client.recognizeForReview(
      apiKey: 'test-key',
      model: 'gemini-test',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/jpeg',
    );

    expect(requestCount, 1);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.multiItemProposal, isNotNull);
    expect(result.multiItemProposal!.reconciledTotal, isNull);
    expect(result.multiItemProposal!.reconcilesObservedTotal(), isFalse);
  });

  test('conflicting lines total fails closed without a second request', () async {
    var requestCount = 0;
    final httpClient = MockClient((http.Request request) async {
      requestCount += 1;
      return http.Response(
        _geminiResponse(<String, Object?>{
          'productName': '購物籃',
          'totalAmount': 100,
          'recognizedText': 'A 40 B 50 total 100',
          'confidence': <String, Object?>{},
          'warnings': <String>[],
          'lines': <Object?>[
            <String, Object?>{
              'name': 'A',
              'quantity': 1,
              'unitPrice': 40,
              'subtotal': 40,
              'rawEvidence': 'A 40',
            },
            <String, Object?>{
              'name': 'B',
              'quantity': 1,
              'unitPrice': 50,
              'subtotal': 50,
              'rawEvidence': 'B 50',
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final client = GeminiProductRecognitionClient(client: httpClient);

    final result = await client.recognizeForReview(
      apiKey: 'test-key',
      model: 'gemini-test',
      imageBytes: Uint8List.fromList(<int>[1]),
      mimeType: 'image/jpeg',
    );

    expect(requestCount, 1);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.multiItemProposal, isNotNull);
    expect(result.multiItemProposal!.reconciledTotal, 90);
    expect(result.multiItemProposal!.reconcilesObservedTotal(), isFalse);
  });
}

String _geminiResponse(Map<String, Object?> candidateJson) {
  return jsonEncode(<String, Object?>{
    'candidates': <Object?>[
      <String, Object?>{
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': jsonEncode(candidateJson)},
          ],
        },
      },
    ],
  });
}
