import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_coordinator.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_contract.dart';

class _Store implements GeminiInvoiceSettingsStore {
  const _Store(this.value);

  final GeminiInvoiceSettings value;

  @override
  Future<GeminiInvoiceSettings> load() async => value;

  @override
  Future<void> save(GeminiInvoiceSettings settings) async {}

  @override
  Future<void> clear() async {}
}

class _Loader implements ProductRecognitionImageLoader {
  _Loader(this.bytes, {this.shouldFail = false});

  final Uint8List bytes;
  final bool shouldFail;
  var loadCount = 0;

  @override
  Future<ProductRecognitionImagePayload> load(String localReference) async {
    loadCount += 1;
    if (shouldFail) throw StateError('invalid image');
    return ProductRecognitionImagePayload(
      bytes: bytes,
      mimeType: 'image/jpeg',
    );
  }
}

class _Catalog extends GeminiModelCatalogClient {
  _Catalog(this.values);

  final Map<String, Object> values;
  var calls = 0;

  @override
  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    calls += 1;
    final value = values[apiKey];
    if (value is GeminiModelCatalogException) throw value;
    return (value as List<GeminiModelDescriptor>?) ??
        const <GeminiModelDescriptor>[];
  }
}

class _Call {
  const _Call({
    required this.key,
    required this.model,
    required this.bytes,
  });

  final String key;
  final String model;
  final Uint8List bytes;
}

class _Client implements GeminiProductRecognitionPort {
  _Client(this.handler);

  final Future<ProductRecognitionCandidate> Function(
    String key,
    String model,
    int ordinal,
  ) handler;
  final calls = <_Call>[];

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    calls.add(_Call(key: apiKey, model: model, bytes: imageBytes));
    return handler(apiKey, model, calls.length);
  }
}

void main() {
  const preferred = 'preferred-flash';
  const fallback = 'fallback-flash';
  const models = <GeminiModelDescriptor>[
    GeminiModelDescriptor(
      id: preferred,
      displayName: 'Preferred Flash',
      supportedGenerationMethods: <String>{'generateContent'},
    ),
    GeminiModelDescriptor(
      id: fallback,
      displayName: 'Fallback Flash',
      supportedGenerationMethods: <String>{'generateContent'},
    ),
  ];

  test('quota rotates four-key pool with one frozen image load', () async {
    final frozen = Uint8List.fromList(<int>[9, 8, 7, 6]);
    final loader = _Loader(frozen);
    final client = _Client((key, model, ordinal) async {
      if (key != 'KEY_D') {
        throw const GeminiProductRecognitionException(
          GeminiProductRecognitionFailureKind.quota,
          'quota exhausted',
          statusCode: 429,
        );
      }
      return _candidate();
    });
    final catalog = _Catalog(<String, Object>{
      'KEY_A': models,
      'KEY_B': models,
      'KEY_C': models,
      'KEY_D': models,
    });
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A', 'KEY_B', 'KEY_C', 'KEY_D'],
          model: preferred,
        ),
      ),
      client: client,
      imageLoader: loader,
      catalogClient: catalog,
      logicalInvocationIdFactory: () => 'product-logical-1',
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(client.calls.map((call) => call.key), <String>[
      'KEY_A',
      'KEY_B',
      'KEY_C',
      'KEY_D',
    ]);
    expect(client.calls.map((call) => call.model).toSet(), <String>{preferred});
    expect(loader.loadCount, 1);
    expect(catalog.calls, 4);
    for (final call in client.calls) {
      expect(identical(call.bytes, frozen), isTrue);
    }

    final session = result.sessionContext!;
    expect(session.logicalInvocationId, 'product-logical-1');
    expect(session.logicalInvocationCount, 1);
    expect(session.physicalAttemptCount, 4);
    expect(session.modelAttemptCount, 1);
    expect(session.keyGroupAttemptCount, 4);
    expect(session.keyGroupAlias, 'KEY_4');
    expect(session.fallbackReason, RecognitionAiFallbackReason.quotaExhausted);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('provider catalog replaces unavailable preferred model', () async {
    final client = _Client((key, model, ordinal) async => _candidate());
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A'],
          model: 'missing-flash',
        ),
      ),
      client: client,
      imageLoader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{'KEY_A': models}),
      logicalInvocationIdFactory: () => 'product-logical-2',
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(client.calls.single.model, preferred);
    expect(result.model, preferred);
    expect(
      result.sessionContext!.fallbackReason,
      RecognitionAiFallbackReason.modelUnavailable,
    );
    expect(result.sessionContext!.modelAttemptCount, 1);
  });

  test('stale 404 model switches to next listed Flash on same key', () async {
    final client = _Client((key, model, ordinal) async {
      if (model == preferred) {
        throw const GeminiProductRecognitionException(
          GeminiProductRecognitionFailureKind.requestRejected,
          'model not found',
          statusCode: 404,
        );
      }
      return _candidate();
    });
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A'],
          model: preferred,
        ),
      ),
      client: client,
      imageLoader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{'KEY_A': models}),
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(client.calls.map((call) => call.model), <String>[preferred, fallback]);
    expect(result.model, fallback);
    expect(result.requestCount, 2);
    expect(result.sessionContext!.modelAttemptCount, 2);
    expect(result.sessionContext!.keyGroupAttemptCount, 1);
    expect(
      result.sessionContext!.fallbackReason,
      RecognitionAiFallbackReason.modelUnavailable,
    );
  });

  test('transient service failure gets one bounded same-key retry', () async {
    final client = _Client((key, model, ordinal) async {
      if (ordinal == 1) {
        throw const GeminiProductRecognitionException(
          GeminiProductRecognitionFailureKind.serviceUnavailable,
          'temporary',
          statusCode: 503,
        );
      }
      return _candidate();
    });
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A'],
          model: preferred,
        ),
      ),
      client: client,
      imageLoader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{'KEY_A': models}),
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(client.calls, hasLength(2));
    expect(client.calls.map((call) => call.key).toSet(), <String>{'KEY_A'});
    expect(client.calls.map((call) => call.model).toSet(), <String>{preferred});
    expect(result.sessionContext!.physicalAttemptCount, 2);
    expect(result.sessionContext!.keyGroupAttemptCount, 1);
    expect(
      result.sessionContext!.fallbackReason,
      RecognitionAiFallbackReason.serviceUnavailable,
    );
  });

  test('request rejection fails fast without trying second key', () async {
    final client = _Client((key, model, ordinal) async {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.requestRejected,
        'bad request',
        statusCode: 400,
      );
    });
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A', 'KEY_B'],
          model: preferred,
        ),
      ),
      client: client,
      imageLoader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{
        'KEY_A': models,
        'KEY_B': models,
      }),
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.failed);
    expect(client.calls, hasLength(1));
    expect(client.calls.single.key, 'KEY_A');
    expect(result.requestCount, 1);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('missing keys fail before image or network access', () async {
    final loader = _Loader(Uint8List.fromList(<int>[1]));
    final client = _Client((key, model, ordinal) async => _candidate());
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(GeminiInvoiceSettings()),
      client: client,
      imageLoader: loader,
      catalogClient: _Catalog(const <String, Object>{}),
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.missingApiKey);
    expect(loader.loadCount, 0);
    expect(client.calls, isEmpty);
    expect(result.usedNetwork, isFalse);
  });

  test('invalid image fails before catalog or Gemini request', () async {
    final loader = _Loader(Uint8List.fromList(<int>[]), shouldFail: true);
    final client = _Client((key, model, ordinal) async => _candidate());
    final catalog = _Catalog(<String, Object>{'KEY_A': models});
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(apiKeys: <String>['KEY_A']),
      ),
      client: client,
      imageLoader: loader,
      catalogClient: catalog,
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );

    expect(result.status, ProductRecognitionExecutionStatus.invalidImage);
    expect(loader.loadCount, 1);
    expect(catalog.calls, 0);
    expect(client.calls, isEmpty);
  });

  test('safe execution summary never includes raw API key', () async {
    const rawKey = 'AIza_LONG_SECRET_KEY_12345678';
    final client = _Client((key, model, ordinal) async => _candidate());
    final coordinator = ProductRecognitionCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>[rawKey],
          model: preferred,
        ),
      ),
      client: client,
      imageLoader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{rawKey: models}),
    );

    final result = await coordinator.recognize(
      localReference: '/frozen/product.jpg',
    );
    final safeText = result.toSafeSummary().toString();

    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(safeText, isNot(contains(rawKey)));
    expect(safeText, contains('KEY_1'));
  });
}

ProductRecognitionCandidate _candidate() {
  return const ProductRecognitionCandidate(
    productName: '無糖綠茶',
    quantity: 2,
    unitPrice: 35,
    totalAmount: 70,
    categorySuggestion: '飲料水果',
    merchantName: '測試商店',
  );
}
