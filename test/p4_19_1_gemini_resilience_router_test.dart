import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_client.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_coordinator.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';
import 'package:my_finance_app/features/recognition_ai/gemini_flash_model_router.dart';
import 'package:my_finance_app/features/recognition_ai/gemini_key_group_router.dart';
import 'package:my_finance_app/features/recognition_ai/recognition_ai_contract.dart';

class _Store implements GeminiInvoiceSettingsStore {
  const _Store(this.settings);
  final GeminiInvoiceSettings settings;
  @override
  Future<GeminiInvoiceSettings> load() async => settings;
  @override
  Future<void> save(GeminiInvoiceSettings settings) async {}
  @override
  Future<void> clear() async {}
}

class _Loader implements GeminiInvoiceImageLoader {
  _Loader(this.bytes);
  final Uint8List bytes;
  var loads = 0;
  @override
  Future<GeminiInvoiceImagePayload> load(String localReference) async {
    loads += 1;
    return GeminiInvoiceImagePayload(bytes: bytes, mimeType: 'image/jpeg');
  }
}

class _Catalog extends GeminiModelCatalogClient {
  _Catalog(this.values);
  final Map<String, Object> values;
  @override
  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    final value = values[apiKey];
    if (value is GeminiModelCatalogException) throw value;
    return (value as List<GeminiModelDescriptor>?) ??
        const <GeminiModelDescriptor>[];
  }
}

class _Call {
  const _Call(this.key, this.model, this.bytes);
  final String key;
  final String model;
  final Uint8List bytes;
}

class _Client implements GeminiInvoiceReviewPort {
  _Client(this.handler);
  final Future<GeminiInvoiceReviewCandidate> Function(
    String key,
    String model,
    int ordinal,
  ) handler;
  final calls = <_Call>[];

  @override
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  }) async {
    calls.add(_Call(apiKey, model, imageBytes));
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

  test('dynamic model router never invents missing model IDs', () {
    final result = const GeminiFlashModelRouter().candidates(
      preferredModel: 'missing-flash',
      catalog: models,
    );
    expect(result, <String>[preferred, fallback]);
    expect(result, isNot(contains('missing-flash')));
  });

  test('flat keys become ordered anonymous runtime slots', () {
    final slots = GeminiKeyGroupRouter.fromApiKeys(
      const <String>['KEY_A', 'KEY_B'],
    ).healthyGroups;

    expect(slots, hasLength(2));
    expect(slots[0].alias, 'KEY_1');
    expect(slots[0].apiKeys, <String>['KEY_A']);
    expect(slots[1].alias, 'KEY_2');
    expect(slots[1].apiKeys, <String>['KEY_B']);
  });

  test('quota failure rotates to next key with same model', () async {
    final frozen = Uint8List.fromList(<int>[9, 8, 7, 6]);
    final loader = _Loader(frozen);
    final client = _Client((key, model, ordinal) async {
      if (key == 'KEY_A') {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.quota,
          'quota',
          statusCode: 429,
        );
      }
      return _candidate();
    });
    final result = await _coordinator(
      client: client,
      loader: loader,
      catalog: _Catalog(<String, Object>{
        'KEY_A': models,
        'KEY_B': models,
      }),
      keys: const <String>['KEY_A', 'KEY_B'],
    ).reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    );

    expect(result.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(client.calls.map((call) => call.key), <String>['KEY_A', 'KEY_B']);
    expect(client.calls.map((call) => call.model).toSet(), <String>{preferred});
    expect(identical(client.calls[0].bytes, client.calls[1].bytes), isTrue);
    expect(identical(client.calls[0].bytes, frozen), isTrue);
    expect(loader.loads, 1);
    expect(result.sessionContext!.logicalInvocationCount, 1);
    expect(result.sessionContext!.physicalAttemptCount, 2);
    expect(result.sessionContext!.keyGroupAttemptCount, 2);
    expect(result.sessionContext!.keyGroupAlias, 'KEY_2');
    expect(
      result.sessionContext!.fallbackReason,
      RecognitionAiFallbackReason.quotaExhausted,
    );
  });

  test('legacy grouped adapter is flattened into key slots', () {
    final slots = GeminiKeyGroupRouter.fromGroups(
      const <GeminiKeyGroup>[
        GeminiKeyGroup(alias: 'GROUP_A', apiKeys: <String>['KEY_A']),
        GeminiKeyGroup(alias: 'GROUP_B', apiKeys: <String>['KEY_B']),
      ],
    ).healthyGroups;
    expect(slots, hasLength(2));
    expect(slots[0].alias, 'KEY_1');
    expect(slots[1].alias, 'KEY_2');
  });

  test('unavailable preferred model switches to provider-listed Flash', () async {
    final client = _Client((key, model, ordinal) async => _candidate());
    final result = await _coordinator(
      client: client,
      loader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalog: _Catalog(<String, Object>{'KEY_A': models}),
      keys: const <String>['KEY_A'],
      model: 'missing-flash',
    ).reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    );

    expect(result.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(client.calls.single.model, preferred);
    expect(result.sessionContext!.physicalAttemptCount, 1);
    expect(
      result.sessionContext!.fallbackReason,
      RecognitionAiFallbackReason.modelUnavailable,
    );
  });

  test('transient 503 retries once but rejected 400 fails fast', () async {
    final retryClient = _Client((key, model, ordinal) async {
      if (ordinal == 1) {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.serviceUnavailable,
          'temporary',
          statusCode: 503,
        );
      }
      return _candidate();
    });
    final retryResult = await _coordinator(
      client: retryClient,
      loader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalog: _Catalog(<String, Object>{'KEY_A': models}),
      keys: const <String>['KEY_A'],
    ).reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    );
    expect(retryResult.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(retryClient.calls, hasLength(2));
    expect(retryResult.sessionContext!.physicalAttemptCount, 2);

    final failClient = _Client((key, model, ordinal) async {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.requestRejected,
        'bad request',
        statusCode: 400,
      );
    });
    final failResult = await _coordinator(
      client: failClient,
      loader: _Loader(Uint8List.fromList(<int>[1, 2, 3])),
      catalog: _Catalog(<String, Object>{'KEY_A': models}),
      keys: const <String>['KEY_A'],
    ).reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    );
    expect(failResult.status, GeminiInvoiceReviewExecutionStatus.failed);
    expect(failClient.calls, hasLength(1));
  });
}

GeminiInvoiceReviewCoordinator _coordinator({
  required _Client client,
  required _Loader loader,
  required _Catalog catalog,
  required List<String> keys,
  String model = 'preferred-flash',
}) {
  return GeminiInvoiceReviewCoordinator(
    settingsStore: _Store(
      GeminiInvoiceSettings(
        apiKeys: keys,
        model: model,
        experimentalInvoiceVisionEnabled: true,
        autoReviewLowConfidenceEnabled: true,
      ),
    ),
    client: client,
    imageLoader: loader,
    catalogClient: catalog,
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
