import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_client.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_coordinator.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  group('P4.19.0 automatic Gemini fallback', () {
    test('legacy settings decode keeps automatic review OFF', () {
      final settings = GeminiInvoiceSettings.decode(
        '{"schemaVersion":1,"apiKeys":["key-1"],'
        '"model":"gemini-3.6-flash",'
        '"experimentalInvoiceVisionEnabled":true,'
        '"debugToolsEnabled":true}',
      );

      expect(settings.experimentalInvoiceVisionEnabled, isTrue);
      expect(settings.autoReviewLowConfidenceEnabled, isFalse);
    });

    test('automatic review setting round-trips explicitly', () {
      const original = GeminiInvoiceSettings(
        apiKeys: <String>['key-1'],
        experimentalInvoiceVisionEnabled: true,
        autoReviewLowConfidenceEnabled: true,
      );

      final decoded = GeminiInvoiceSettings.decode(original.encode());

      expect(decoded.autoReviewLowConfidenceEnabled, isTrue);
      expect(decoded.apiKeys, <String>['key-1']);
    });

    test('setting OFF plus low-confidence Local makes zero AI requests', () async {
      final client = _CountingClient();
      final coordinator = GeminiInvoiceReviewCoordinator(
        settingsStore: _MemorySettingsStore(
          const GeminiInvoiceSettings(
            apiKeys: <String>['key-1'],
            experimentalInvoiceVisionEnabled: true,
          ),
        ),
        client: client,
        imageLoader: const _MemoryImageLoader(),
      );

      final execution = await coordinator.reviewAutomatically(
        localResult: _recognitionFailed(),
        localReference: '/original/frozen.jpg',
      );

      expect(execution.status, GeminiInvoiceReviewExecutionStatus.disabled);
      expect(execution.invocationMode, GeminiInvoiceReviewInvocationMode.automatic);
      expect(execution.automaticReviewSettingEnabled, isFalse);
      expect(execution.requestCount, 0);
      expect(execution.automaticUploadPerformed, isFalse);
      expect(client.calls, 0);
    });

    test('setting ON plus low-confidence Local makes exactly one AI request', () async {
      final client = _CountingClient();
      final coordinator = GeminiInvoiceReviewCoordinator(
        settingsStore: _MemorySettingsStore(
          const GeminiInvoiceSettings(
            apiKeys: <String>['key-1'],
            experimentalInvoiceVisionEnabled: true,
            autoReviewLowConfidenceEnabled: true,
          ),
        ),
        client: client,
        imageLoader: const _MemoryImageLoader(),
      );

      final execution = await coordinator.reviewAutomatically(
        localResult: _recognitionFailed(),
        localReference: '/original/frozen.jpg',
      );

      expect(execution.status, GeminiInvoiceReviewExecutionStatus.success);
      expect(execution.invocationMode, GeminiInvoiceReviewInvocationMode.automatic);
      expect(execution.automaticReviewSettingEnabled, isTrue);
      expect(execution.requestCount, 1);
      expect(execution.automaticUploadPerformed, isTrue);
      expect(client.calls, 1);
      expect(client.lastBytes, Uint8List.fromList(const <int>[1, 2, 3, 4]));
    });

    test('setting ON plus complete high-confidence Local makes zero AI requests', () async {
      final client = _CountingClient();
      final coordinator = GeminiInvoiceReviewCoordinator(
        settingsStore: _MemorySettingsStore(
          const GeminiInvoiceSettings(
            apiKeys: <String>['key-1'],
            experimentalInvoiceVisionEnabled: true,
            autoReviewLowConfidenceEnabled: true,
          ),
        ),
        client: client,
        imageLoader: const _MemoryImageLoader(),
      );

      final execution = await coordinator.reviewAutomatically(
        localResult: _completeHighConfidenceOcr(),
        localReference: '/original/frozen.jpg',
      );

      expect(
        execution.status,
        GeminiInvoiceReviewExecutionStatus.skippedLocalComplete,
      );
      expect(execution.requestCount, 0);
      expect(execution.automaticUploadPerformed, isFalse);
      expect(client.calls, 0);
    });
  });
}

InvoiceAutomaticRecognitionResult _recognitionFailed() {
  return const InvoiceAutomaticRecognitionResult(
    status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
    message: 'failed',
    selectedRouteReason: 'test',
    requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
  );
}

InvoiceAutomaticRecognitionResult _completeHighConfidenceOcr() {
  const confidence = <TraditionalInvoiceOcrField, TraditionalInvoiceOcrConfidence>{
    TraditionalInvoiceOcrField.invoiceNumber: TraditionalInvoiceOcrConfidence.high,
    TraditionalInvoiceOcrField.sellerTaxId: TraditionalInvoiceOcrConfidence.high,
    TraditionalInvoiceOcrField.invoiceDate: TraditionalInvoiceOcrConfidence.high,
    TraditionalInvoiceOcrField.sellerName: TraditionalInvoiceOcrConfidence.high,
    TraditionalInvoiceOcrField.totalAmount: TraditionalInvoiceOcrConfidence.high,
  };
  final candidate = TraditionalInvoiceOcrReviewCandidate(
    sourceImageReference: '/original/frozen.jpg',
    invoiceNumber: 'AA12345678',
    sellerTaxId: '12345675',
    sellerTaxIdSource: 'explicit_label',
    invoiceDate: DateTime(2026, 8, 18),
    sellerName: '測試商家',
    totalAmount: 100,
    visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
    confidence: confidence,
    fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
  );
  return InvoiceAutomaticRecognitionResult(
    status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
    message: 'complete',
    selectedRouteReason: 'test',
    requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    ocrResult: TraditionalInvoiceOcrResult(
      status: TraditionalInvoiceOcrStatus.success,
      message: 'complete',
      candidate: candidate,
    ),
  );
}

class _MemorySettingsStore implements GeminiInvoiceSettingsStore {
  _MemorySettingsStore(this.settings);

  GeminiInvoiceSettings settings;

  @override
  Future<void> clear() async {
    settings = const GeminiInvoiceSettings();
  }

  @override
  Future<GeminiInvoiceSettings> load() async => settings;

  @override
  Future<void> save(GeminiInvoiceSettings value) async {
    settings = value;
  }
}

class _MemoryImageLoader implements GeminiInvoiceImageLoader {
  const _MemoryImageLoader();

  @override
  Future<GeminiInvoiceImagePayload> load(String localReference) async {
    expect(localReference, '/original/frozen.jpg');
    return GeminiInvoiceImagePayload(
      bytes: Uint8List.fromList(const <int>[1, 2, 3, 4]),
      mimeType: 'image/jpeg',
    );
  }
}

class _CountingClient implements GeminiInvoiceReviewPort {
  int calls = 0;
  Uint8List? lastBytes;

  @override
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  }) async {
    calls += 1;
    lastBytes = Uint8List.fromList(imageBytes);
    return const GeminiInvoiceReviewCandidate(
      invoiceNumber: 'AA12345678',
      invoicePeriod: '115年7-8月份',
      sellerTaxId: '',
      invoiceDate: '2026-08-18',
      invoiceTime: '12:34:56',
      merchantName: '測試商家',
      totalAmount: 100,
      lineItems: <GeminiInvoiceReviewLineItem>[],
      confidence: <GeminiInvoiceReviewField, double>{},
      warnings: <String>[],
    );
  }
}
