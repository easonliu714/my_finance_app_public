import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_client.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review_coordinator.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

class _FakeSettingsStore implements GeminiInvoiceSettingsStore {
  const _FakeSettingsStore(this.settings);
  final GeminiInvoiceSettings settings;
  @override
  Future<GeminiInvoiceSettings> load() async => settings;
  @override
  Future<void> save(GeminiInvoiceSettings settings) async {}
  @override
  Future<void> clear() async {}
}

class _FakeImageLoader implements GeminiInvoiceImageLoader {
  const _FakeImageLoader();
  @override
  Future<GeminiInvoiceImagePayload> load(String localReference) async {
    return GeminiInvoiceImagePayload(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      mimeType: 'image/jpeg',
    );
  }
}

class _RecordingReviewClient implements GeminiInvoiceReviewPort {
  _RecordingReviewClient(this.handler);
  final Future<GeminiInvoiceReviewCandidate> Function(String key) handler;
  final attemptedKeys = <String>[];

  @override
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  }) async {
    attemptedKeys.add(apiKey);
    expect(model, GeminiInvoiceSettings.defaultModel);
    expect(localSummary, isNot(contains('invoiceNumber')));
    return handler(apiKey);
  }
}

void main() {
  test('feature flag blocks network review', () async {
    final client = _RecordingReviewClient((_) async => _aiCandidate());
    final coordinator = GeminiInvoiceReviewCoordinator(
      settingsStore: const _FakeSettingsStore(
        GeminiInvoiceSettings(apiKeys: <String>['KEY_1']),
      ),
      client: client,
      imageLoader: const _FakeImageLoader(),
    );
    final result = await coordinator.review(
      localResult: _partialOcrResult(),
      localReference: '/tmp/invoice.jpg',
    );
    expect(result.status, GeminiInvoiceReviewExecutionStatus.disabled);
    expect(result.usedNetwork, isFalse);
    expect(client.attemptedKeys, isEmpty);
  });

  test('complete structured QR skips automatic AI review', () async {
    final client = _RecordingReviewClient((_) async => _aiCandidate());
    final coordinator = GeminiInvoiceReviewCoordinator(
      settingsStore: const _FakeSettingsStore(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_1'],
          experimentalInvoiceVisionEnabled: true,
        ),
      ),
      client: client,
      imageLoader: const _FakeImageLoader(),
    );
    final result = await coordinator.review(
      localResult: _qrResult(),
      localReference: '/tmp/invoice.jpg',
    );
    expect(result.status, GeminiInvoiceReviewExecutionStatus.skippedLocalComplete);
    expect(client.attemptedKeys, isEmpty);
  });

  test('partial OCR rotates quota-limited key and succeeds with next key', () async {
    final client = _RecordingReviewClient((key) async {
      if (key == 'KEY_1') {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.quota,
          'quota',
          statusCode: 429,
        );
      }
      return _aiCandidate();
    });
    final coordinator = GeminiInvoiceReviewCoordinator(
      settingsStore: const _FakeSettingsStore(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_1', 'KEY_2'],
          experimentalInvoiceVisionEnabled: true,
        ),
      ),
      client: client,
      imageLoader: const _FakeImageLoader(),
    );
    final result = await coordinator.review(
      localResult: _partialOcrResult(),
      localReference: '/tmp/invoice.jpg',
    );
    expect(result.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(client.attemptedKeys, <String>['KEY_1', 'KEY_2']);
    expect(result.attempts.length, 2);
    expect(result.candidate?.invoiceNumber, 'AB12345678');
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('request error stops rotation to avoid repeating invalid request', () async {
    final client = _RecordingReviewClient((_) async {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.requestRejected,
        'bad request',
        statusCode: 400,
      );
    });
    final coordinator = GeminiInvoiceReviewCoordinator(
      settingsStore: const _FakeSettingsStore(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_1', 'KEY_2'],
          experimentalInvoiceVisionEnabled: true,
        ),
      ),
      client: client,
      imageLoader: const _FakeImageLoader(),
    );
    final result = await coordinator.review(
      localResult: _partialOcrResult(),
      localReference: '/tmp/invoice.jpg',
    );
    expect(result.status, GeminiInvoiceReviewExecutionStatus.failed);
    expect(client.attemptedKeys, <String>['KEY_1']);
  });

  test('force review remains available without replacing QR result', () async {
    final client = _RecordingReviewClient((_) async => _aiCandidate());
    final coordinator = GeminiInvoiceReviewCoordinator(
      settingsStore: const _FakeSettingsStore(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_1'],
          experimentalInvoiceVisionEnabled: true,
        ),
      ),
      client: client,
      imageLoader: const _FakeImageLoader(),
    );
    final result = await coordinator.review(
      localResult: _qrResult(),
      localReference: '/tmp/invoice.jpg',
      forceReview: true,
    );
    expect(result.status, GeminiInvoiceReviewExecutionStatus.success);
    expect(result.message, contains('尚未覆寫本機結果'));
    expect(client.attemptedKeys, <String>['KEY_1']);
  });
}

InvoiceAutomaticRecognitionResult _qrResult() {
  const leftPayload =
      'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';
  final routing = const InvoiceRecognitionRouter().route(
    const <InvoiceRecognitionImageInput>[
      InvoiceRecognitionImageInput(
        localReference: '/tmp/invoice.jpg',
        fileName: 'invoice.jpg',
        payloads: <String>[leftPayload, '**detail'],
      ),
    ],
  );
  return InvoiceAutomaticRecognitionResult(
    status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
    message: 'QR candidate with Local supplemental OCR',
    selectedRouteReason: 'QR identity authority',
    requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    qrResult: InvoiceLocalRecognitionResult(
      status: InvoiceLocalRecognitionStatus.qrCandidate,
      message: 'QR candidate',
      failedImageReferences: const <String>[],
      routingResult: routing,
    ),
    ocrResult: const TraditionalInvoiceOcrResult(
      status: TraditionalInvoiceOcrStatus.success,
      message: 'Supplemental OCR complete',
      candidate: TraditionalInvoiceOcrReviewCandidate(
        sourceImageReference: '/tmp/invoice.jpg',
        invoiceNumber: '',
        invoiceDate: null,
        sellerName: '測試商店',
        totalAmount: null,
        visibleLineItems: <TraditionalInvoiceOcrLineItem>[],
        confidence: <TraditionalInvoiceOcrField,
            TraditionalInvoiceOcrConfidence>{},
        fieldWarnings: <TraditionalInvoiceOcrField, List<String>>{},
        rawText: '測試商店\n14:59:52',
      ),
    ),
  );
}

InvoiceAutomaticRecognitionResult _partialOcrResult() {
  const candidate = TraditionalInvoiceOcrReviewCandidate(
    sourceImageReference: '/tmp/invoice.jpg',
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

GeminiInvoiceReviewCandidate _aiCandidate() {
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
