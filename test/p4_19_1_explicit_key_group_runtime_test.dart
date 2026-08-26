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

class _Loader implements GeminiInvoiceImageLoader {
  _Loader(this.bytes);
  final Uint8List bytes;
  var loadCount = 0;

  @override
  Future<GeminiInvoiceImagePayload> load(String localReference) async {
    loadCount += 1;
    return GeminiInvoiceImagePayload(bytes: bytes, mimeType: 'image/jpeg');
  }
}

class _Catalog extends GeminiModelCatalogClient {
  @override
  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    return const <GeminiModelDescriptor>[
      GeminiModelDescriptor(
        id: GeminiInvoiceSettings.defaultModel,
        displayName: 'Configured Flash',
        supportedGenerationMethods: <String>{'generateContent'},
      ),
    ];
  }
}

class _Call {
  const _Call(this.apiKey, this.model, this.bytes);
  final String apiKey;
  final String model;
  final Uint8List bytes;
}

class _Client implements GeminiInvoiceReviewPort {
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
    if (apiKey != 'KEY_4') {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.quota,
        'quota exhausted',
        statusCode: 429,
      );
    }
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
}

void main() {
  test('flat key pool rotates through four keys with same model and frozen bytes', () async {
    final frozen = Uint8List.fromList(const <int>[7, 6, 5, 4]);
    final loader = _Loader(frozen);
    final client = _Client();
    final coordinator = GeminiInvoiceReviewCoordinator(
      settingsStore: const _Store(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_1', 'KEY_2', 'KEY_3', 'KEY_4'],
          experimentalInvoiceVisionEnabled: true,
          autoReviewLowConfidenceEnabled: true,
        ),
      ),
      client: client,
      imageLoader: loader,
      catalogClient: _Catalog(),
      maxPhysicalAttempts: 8,
      logicalInvocationIdFactory: () => 'logical-flat-key-pool-test',
    );

    final result = await coordinator.reviewAutomatically(
      localResult: _partialResult(),
      localReference: '/frozen/invoice.jpg',
    );

    expect(result.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(client.calls.map((call) => call.apiKey), <String>[
      'KEY_1',
      'KEY_2',
      'KEY_3',
      'KEY_4',
    ]);
    expect(client.calls.map((call) => call.model).toSet(), <String>{
      GeminiInvoiceSettings.defaultModel,
    });
    for (final call in client.calls) {
      expect(identical(call.bytes, frozen), isTrue);
    }
    expect(loader.loadCount, 1);

    final session = result.sessionContext!;
    expect(session.logicalInvocationId, 'logical-flat-key-pool-test');
    expect(session.logicalInvocationCount, 1);
    expect(session.physicalAttemptCount, 4);
    expect(session.modelAttemptCount, 1);
    expect(session.keyGroupAttemptCount, 4);
    expect(session.keyGroupAlias, 'KEY_4');
    expect(session.activeModel, GeminiInvoiceSettings.defaultModel);
    expect(session.fallbackReason, RecognitionAiFallbackReason.quotaExhausted);
  });
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
