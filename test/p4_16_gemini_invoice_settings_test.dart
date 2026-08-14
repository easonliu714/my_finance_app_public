import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';

void main() {
  test('parses multiple API keys with supported delimiters and deduplicates', () {
    final keys = GeminiInvoiceSettings.parseApiKeys(
      'KEY_A，KEY_B、KEY_C；KEY_A\nKEY_D, KEY_E;KEY_F',
    );

    expect(
      keys,
      <String>['KEY_A', 'KEY_B', 'KEY_C', 'KEY_D', 'KEY_E', 'KEY_F'],
    );
  });

  test('settings round-trip preserves feature flags and default model', () {
    const settings = GeminiInvoiceSettings(
      apiKeys: <String>['KEY_A', 'KEY_B'],
      experimentalInvoiceVisionEnabled: true,
      debugToolsEnabled: true,
    );

    final decoded = GeminiInvoiceSettings.decode(settings.encode());

    expect(decoded.apiKeys, settings.apiKeys);
    expect(decoded.model, GeminiInvoiceSettings.defaultModel);
    expect(decoded.experimentalInvoiceVisionEnabled, isTrue);
    expect(decoded.debugToolsEnabled, isTrue);
  });

  test('model catalog keeps generateContent models and prefers 3.6 Flash', () async {
    final client = GeminiModelCatalogClient(
      client: MockClient((request) async {
        expect(request.headers['x-goog-api-key'], 'TEST_KEY');
        return http.Response(
          jsonEncode(<String, Object?>{
            'models': <Object?>[
              <String, Object?>{
                'name': 'models/text-embedding-004',
                'displayName': 'Embedding',
                'supportedGenerationMethods': <String>['embedContent'],
              },
              <String, Object?>{
                'name': 'models/gemini-3.5-flash-lite',
                'displayName': 'Gemini 3.5 Flash-Lite',
                'supportedGenerationMethods': <String>['generateContent'],
              },
              <String, Object?>{
                'name': 'models/gemini-3.6-flash',
                'displayName': 'Gemini 3.6 Flash',
                'supportedGenerationMethods': <String>['generateContent'],
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final models = await client.listModels('TEST_KEY');

    expect(models.map((model) => model.id), <String>[
      'gemini-3.6-flash',
      'gemini-3.5-flash-lite',
    ]);
  });

  test('multi-key validation reports each key without exposing full key', () async {
    final client = GeminiModelCatalogClient(
      client: MockClient((request) async {
        final key = request.headers['x-goog-api-key'];
        if (key == 'BAD_KEY_12345678') {
          return http.Response('{"error":"forbidden"}', 403);
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'models': <Object?>[
              <String, Object?>{
                'name': 'models/gemini-3.6-flash',
                'displayName': 'Gemini 3.6 Flash',
                'supportedGenerationMethods': <String>['generateContent'],
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await client.validateKeysAndLoadModels(
      const <String>['BAD_KEY_12345678', 'GOOD_KEY_12345678'],
    );

    expect(result.keyResults, hasLength(2));
    expect(result.keyResults.first.available, isFalse);
    expect(result.keyResults.last.available, isTrue);
    expect(result.keyResults.first.maskedKey, isNot(contains('12345678')));
    expect(result.models.single.id, GeminiInvoiceSettings.defaultModel);
  });
}
