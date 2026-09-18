import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_coordinator.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_review_port.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';
import 'package:my_finance_app/features/product/product_recognition_review_result.dart';

class _SettingsStore implements GeminiInvoiceSettingsStore {
  const _SettingsStore(this.settings);

  final GeminiInvoiceSettings settings;

  @override
  Future<GeminiInvoiceSettings> load() async => settings;

  @override
  Future<void> save(GeminiInvoiceSettings settings) async {}

  @override
  Future<void> clear() async {}
}

class _ImageLoader implements ProductRecognitionImageLoader {
  const _ImageLoader();

  @override
  Future<ProductRecognitionImagePayload> load(String localReference) async {
    return ProductRecognitionImagePayload(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      mimeType: 'image/jpeg',
    );
  }
}

class _CatalogClient extends GeminiModelCatalogClient {
  _CatalogClient();

  @override
  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    return const <GeminiModelDescriptor>[];
  }
}

class _ReviewClient
    implements GeminiProductRecognitionPort, GeminiProductRecognitionReviewPort {
  int legacyCalls = 0;
  int reviewCalls = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    legacyCalls++;
    throw StateError('review-capable coordinator path must stay single-request');
  }

  @override
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    reviewCalls++;
    return const ProductRecognitionReviewResult(
      candidate: ProductRecognitionCandidate(productName: '同次請求商品'),
    );
  }
}

class _LegacyClient implements GeminiProductRecognitionPort {
  int legacyCalls = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    legacyCalls++;
    return const ProductRecognitionCandidate(productName: '舊版商品');
  }
}

class _FailingReviewClient
    implements GeminiProductRecognitionPort, GeminiProductRecognitionReviewPort {
  int legacyCalls = 0;
  int reviewCalls = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    legacyCalls++;
    throw StateError('failure path must not fall back to a second request');
  }

  @override
  Future<ProductRecognitionReviewResult> recognizeForReview({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    reviewCalls++;
    throw const GeminiProductRecognitionException(
      GeminiProductRecognitionFailureKind.malformedResponse,
      'malformed response fixture',
    );
  }
}

ProductRecognitionCoordinator _coordinator(GeminiProductRecognitionPort client) {
  return ProductRecognitionCoordinator(
    settingsStore: const _SettingsStore(
      GeminiInvoiceSettings(
        apiKeys: <String>['test-key'],
        model: GeminiInvoiceSettings.defaultModel,
      ),
    ),
    client: client,
    imageLoader: const _ImageLoader(),
    catalogClient: _CatalogClient(),
    maxPhysicalAttempts: 1,
    logicalInvocationIdFactory: () => 'issue29-runtime-acceptance',
  );
}

void main() {
  test('review-capable coordinator propagates same-request review evidence', () async {
    final client = _ReviewClient();
    final result = await _coordinator(client).recognize(localReference: 'fixture.jpg');

    expect(client.reviewCalls, 1);
    expect(client.legacyCalls, 0);
    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(result.requestCount, 1);
    expect(result.candidate?.productName, '同次請求商品');
    expect(result.reviewEvidence, isNotNull);
    expect(result.reviewEvidence?.reviewResult.candidate.productName, '同次請求商品');
    expect(result.reviewEvidence?.requiresUserReview, isTrue);
    expect(result.reviewEvidence?.canCreateFormalRecord, isFalse);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('legacy coordinator keeps one request and no synthetic review evidence', () async {
    final client = _LegacyClient();
    final result = await _coordinator(client).recognize(localReference: 'fixture.jpg');

    expect(client.legacyCalls, 1);
    expect(result.status, ProductRecognitionExecutionStatus.success);
    expect(result.requestCount, 1);
    expect(result.candidate?.productName, '舊版商品');
    expect(result.reviewEvidence, isNull);
    expect(result.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('failed coordinator attempt never synthesizes review evidence', () async {
    final client = _FailingReviewClient();
    final result = await _coordinator(client).recognize(localReference: 'fixture.jpg');

    expect(client.reviewCalls, 1);
    expect(client.legacyCalls, 0);
    expect(result.status, ProductRecognitionExecutionStatus.failed);
    expect(result.requestCount, 1);
    expect(result.candidate, isNull);
    expect(result.reviewEvidence, isNull);
    expect(result.canCreateFormalRecord, isFalse);
  });
}
