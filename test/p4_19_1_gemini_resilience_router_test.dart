import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_client.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_coordinator.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_resilient_review_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';
import 'package:my_finance_app/features/recognition_ai/gemini_flash_model_router.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_contract.dart';

class _SettingsStore implements GeminiInvoiceSettingsStore {
  const _SettingsStore(this.value);
  final GeminiInvoiceSettings value;

  @override
  Future<GeminiInvoiceSettings> load() async => value;
  @override
  Future<void> save(GeminiInvoiceSettings settings) async {}
  @override
  Future<void> clear() async {}
}

class _ImageLoader implements GeminiInvoiceImageLoader {
  _ImageLoader(this.bytes);
  final Uint8List bytes;
  var loadCount = 0;

  @override
  Future<GeminiInvoiceImagePayload> load(String localReference) async {
    loadCount += 1;
    return GeminiInvoiceImagePayload(bytes: bytes, mimeType: 'image/jpeg');
  }
}

class _Catalog extends GeminiModelCatalogClient {
  _Catalog(this.byKey);
  final Map<String, Object> byKey;

  @override
  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    final value = byKey[apiKey];
    if (value is GeminiModelCatalogException) throw value;
    return (value as List<GeminiModelDescriptor>?) ?? const <GeminiModelDescriptor>[];
  }
}

class _ReviewCall {
  const _ReviewCall(this.key, this.model, this.bytes);
  final String key;
  final String model;
  final Uint8List bytes;
}

class _ReviewClient implements GeminiInvoiceReviewPort {
  _ReviewClient(this.handler);
  final Future<GeminiInvoiceReviewCandidate> Function(
    String key,
    String model,
    int ordinal,
  ) handler;
  final calls = <_ReviewCall>[];

  @override
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  }) async {
    calls.add(_ReviewCall(apiKey, model, imageBytes));
    return handler(apiKey, model, calls.length);
  }
}

void main() {
  const preferred = 'preferred-flash';
  const fallback = 'fallback-flash';
  const catalog = <GeminiModelDescriptor>[
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
    GeminiModelDescriptor(
      id: 'embedding-model',
      displayName: 'Embedding',
      supportedGenerationMethods: <String>{'embedContent'},
    ),
  ];

  test('Flash model router never invents unavailable model IDs', () {
    final candidates = const GeminiFlashModelRouter().candidates(
      preferredModel: 'missing-flash',
      catalog: catalog,
    );
    expect(candidates, <String>[preferred, fallback]);
    expect(candidates, isNot(contains('missing-flash')));
  });

  test('quota switches Key Group and retries same model with frozen bytes', () async {
    final frozenBytes = Uint8List.fromList(<int>[9, 8, 7, 6]);
    final imageLoader = _ImageLoader(frozenBytes);
    final client = _ReviewClient((key, model, ordinal) async {
      if (key == 'KEY_A') {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.quota,
          'quota',
          statusCode: 429,
        );
      }
      return _candidate();
    });
    final coordinator = _coordinator(
      client: client,
      imageLoader: imageLoader,
      catalogClient: _Catalog(<String, Object>{
        'KEY_A': catalog,
        'KEY_B': catalog,
      }),
      apiKeys: const <String>['KEY_A', 'KEY_B'],
    );

    final execution = await coordinator.reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    ) as ResilientGeminiInvoiceReviewExecution;

    expect(execution.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(client.calls.map((call) => call.key), <String>['KEY_A', 'KEY_B']);
    expect(client.calls.map((call) => call.model), <String>[preferred, preferred]);
    expect(identical(client.calls[0].bytes, client.calls[1].bytes), isTrue);
    expect(identical(client.calls[0].bytes, frozenBytes), isTrue);
    expect(imageLoader.loadCount, 1);
    expect(execution.sessionContext.logicalInvocationCount, 1);
    expect(execution.sessionContext.physicalAttemptCount, 2);
    expect(execution.sessionContext.keyGroupAttemptCount, 2);
    expect(execution.sessionContext.activeModel, preferred);
    expect(execution.sessionContext.keyGroupAlias, 'GROUP_B');
    expect(
      execution.sessionContext.fallbackReason,
      RecognitionAiFallbackReason.quotaExhausted,
    );
  });

  test('missing configured model selects provider-listed Flash before image call', () async {
    final client = _ReviewClient((key, model, ordinal) async => _candidate());
    final coordinator = _coordinator(
      client: client,
      imageLoader: _ImageLoader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{'KEY_A': catalog}),
      apiKeys: const <String>['KEY_A'],
      model: 'missing-flash',
    );

    final execution = await coordinator.reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    ) as ResilientGeminiInvoiceReviewExecution;

    expect(execution.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(client.calls, hasLength(1));
    expect(client.calls.single.model, preferred);
    expect(execution.sessionContext.physicalAttemptCount, 1);
    expect(execution.sessionContext.modelAttemptCount, 1);
    expect(
      execution.sessionContext.fallbackReason,
      RecognitionAiFallbackReason.modelUnavailable,
    );
  });

  test('404 model rejection advances to next provider-listed Flash model', () async {
    final client = _ReviewClient((key, model, ordinal) async {
      if (model == preferred) {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.requestRejected,
          'not found',
          statusCode: 404,
        );
      }
      return _candidate();
    });
    final coordinator = _coordinator(
      client: client,
      imageLoader: _ImageLoader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{'KEY_A': catalog}),
      apiKeys: const <String>['KEY_A'],
    );

    final execution = await coordinator.reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    ) as ResilientGeminiInvoiceReviewExecution;

    expect(client.calls.map((call) => call.model), <String>[preferred, fallback]);
    expect(execution.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(execution.sessionContext.activeModel, fallback);
    expect(execution.sessionContext.modelAttemptCount, 2);
    expect(execution.sessionContext.physicalAttemptCount, 2);
    expect(
      execution.sessionContext.fallbackReason,
      RecognitionAiFallbackReason.modelUnavailable,
    );
  });

  test('temporary provider failure retries same route once', () async {
    final client = _ReviewClient((key, model, ordinal) async {
      if (ordinal == 1) {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.serviceUnavailable,
          'temporary',
          statusCode: 503,
        );
      }
      return _candidate();
    });
    final coordinator = _coordinator(
      client: client,
      imageLoader: _ImageLoader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{'KEY_A': catalog}),
      apiKeys: const <String>['KEY_A'],
    );

    final execution = await coordinator.reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    ) as ResilientGeminiInvoiceReviewExecution;

    expect(client.calls, hasLength(2));
    expect(client.calls[0].model, client.calls[1].model);
    expect(execution.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(execution.sessionContext.physicalAttemptCount, 2);
    expect(
      execution.sessionContext.fallbackReason,
      RecognitionAiFallbackReason.serviceUnavailable,
    );
  });

  test('malformed/request errors fail fast without blind fallback', () async {
    final client = _ReviewClient((key, model, ordinal) async {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.requestRejected,
        'bad request',
        statusCode: 400,
      );
    });
    final coordinator = _coordinator(
      client: client,
      imageLoader: _ImageLoader(Uint8List.fromList(<int>[1, 2, 3])),
      catalogClient: _Catalog(<String, Object>{
        'KEY_A': catalog,
        'KEY_B': catalog,
      }),
      apiKeys: const <String>['KEY_A', 'KEY_B'],
    );

    final execution = await coordinator.reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    ) as ResilientGeminiInvoiceReviewExecution;

    expect(execution.status, GeminiInvoiceReviewExecutionStatus.failed);
    expect(client.calls, hasLength(1));
    expect(execution.sessionContext.physicalAttemptCount, 1);
    expect(execution.sessionContext.keyGroupAttemptCount, 1);
  });
}

ResilientGeminiInvoiceReviewCoordinator _coordinator({
  required _ReviewClient client,
  required _ImageLoader imageLoader,
  required _Catalog catalogClient,
  required List<String> apiKeys,
  String model = 'preferred-flash',
}) {
  return ResilientGeminiInvoiceReviewCoordinator(
    settingsStore: _SettingsStore(
      GeminiInvoiceSettings(
        apiKeys: apiKeys,
        model: model,
        experimentalInvoiceVisionEnabled: true,
        autoReviewLowConfidenceEnabled: true,
      ),
    ),
    client: client,
    imageLoader: imageLoader,
    catalogClient: catalogClient,
    logicalInvocationIdFactory: () => 'logical-test-1',
  );
}

InvoiceAutomaticRecognitionResult _partialResult() {
  const candidate = TraditionalInvoiceOcrReviewCandidate(
    sourceImageReference: '/frozen/invoice.jpg',
    invoiceNumber: '',
    sellerTaxId: '',
    sellerTaxIdSource: '',
    invoiceDate: null,
    sellerName: '',
    totalAmount: null,
    visibleLineItems: <TraditionalInvoiceOcrLineItem>[],
    confidence: <TraditionalInvoiceOcrField, TraditionalInvoiceOcrConfidence>{},
    fieldWarnings: <TraditionalInvoiceOcrField, List<String>>{},
  );
  return const InvoiceAutomaticRecognitionResult(
    status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
    message: 'partial',
    selectedRouteReason: 'OCR',
    requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    ocrResult: TraditionalInvoiceOcrResult(
      status: TraditionalInvoiceOcrStatus.partial,
      message: 'partial',
      candidate: candidate,
    ),
  );
}

GeminiInvoiceReviewCandidate _candidate() {
  return const GeminiInvoiceReviewCandidate(
    invoiceNumber: 'AB12345678',
    invoicePeriod: '115年03-04月',
    sellerTaxId: '12345678',
    invoiceDate: '2026-04-18',
    invoiceTime: '14:59:52',
    merchantName: '測試商店',
    totalAmount: 120,
    lineItems: <GeminiInvoiceReviewLineItem>[],
    confidence: <GeminiInvoiceReviewField, double>{},
    warnings: <String>[],
  );
}
