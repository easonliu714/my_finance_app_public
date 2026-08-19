import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/production_image_capture.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_client.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_coordinator.dart';
import 'package:my_finance_app/features/product/product_capture_page.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';

void main() {
  testWidgets('product page uses product-only camera and gallery flow',
      (tester) async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: 'local-product.jpg',
            name: 'product.jpg',
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductCapturePage(coordinator: coordinator)),
    );

    expect(find.text('拍商品'), findsOneWidget);
    expect(find.byKey(ProductCapturePage.cameraActionKey), findsOneWidget);
    expect(find.byKey(ProductCapturePage.galleryActionKey), findsOneWidget);
    expect(find.text('自動辨識'), findsNothing);
    expect(find.text('傳統發票 OCR'), findsNothing);
    expect(find.text('二維碼發票'), findsNothing);
    expect(find.textContaining('本階段'), findsNothing);

    await tester.tap(find.byKey(ProductCapturePage.helpKey));
    await tester.pumpAndSettle();
    expect(find.text('拍商品使用說明'), findsOneWidget);
    expect(find.text('照片管理'), findsOneWidget);
    expect(find.textContaining('立即丟棄照片'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ProductCapturePage.galleryActionKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ProductCapturePage.stagedItemKey), findsOneWidget);
    expect(find.text('product.jpg'), findsOneWidget);
    expect(find.byKey(ProductCapturePage.aiRecognitionActionKey), findsOneWidget);
    expect(coordinator.currentItem?.intent, DailyCaptureIntent.product);

    final discard = find.byKey(ProductCapturePage.discardActionKey);
    await tester.ensureVisible(discard);
    await tester.tap(discard);
    await tester.pumpAndSettle();
    expect(find.byKey(ProductCapturePage.stagedItemKey), findsNothing);
  });

  testWidgets('staging remains local until explicit AI recognition action',
      (tester) async {
    final capture = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: 'local-product.jpg',
            name: 'product.jpg',
          ),
        ),
      ),
    );
    final client = _RecordingProductClient();
    final recognition = ProductRecognitionCoordinator(
      settingsStore: const _SettingsStore(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A'],
          model: 'gemini-3.6-flash',
        ),
      ),
      client: client,
      imageLoader: _ImageLoader(),
      catalogClient: _CatalogClient(),
      logicalInvocationIdFactory: () => 'product-ui-explicit-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProductCapturePage(
          coordinator: capture,
          recognitionCoordinator: recognition,
        ),
      ),
    );

    await tester.tap(find.byKey(ProductCapturePage.galleryActionKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ProductCapturePage.stagedItemKey), findsOneWidget);
    expect(client.requestCount, 0);
    expect(find.byKey(ProductCapturePage.candidateReviewKey), findsNothing);

    final ai = find.byKey(ProductCapturePage.aiRecognitionActionKey);
    await tester.ensureVisible(ai);
    await tester.tap(ai);
    await tester.pumpAndSettle();

    expect(client.requestCount, 1);
    expect(find.byKey(ProductCapturePage.aiStatusKey), findsOneWidget);
    expect(find.byKey(ProductCapturePage.candidateReviewKey), findsOneWidget);
    expect(find.text('AI 商品候選 · 請人工覆核'), findsOneWidget);
    expect(find.text('無糖綠茶'), findsOneWidget);
    expect(find.text('飲料水果'), findsOneWidget);
    expect(find.text('測試商店'), findsOneWidget);
    expect(find.textContaining('不會自動新增分類、商家或正式交易'), findsOneWidget);
  });
}

class _GallerySource implements GalleryImageSource {
  const _GallerySource(this.image);

  final GalleryPickedImage? image;

  @override
  Future<GalleryPickedImage?> pickImage() async => image;
}

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
  @override
  Future<ProductRecognitionImagePayload> load(String localReference) async {
    return ProductRecognitionImagePayload(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      mimeType: 'image/jpeg',
    );
  }
}

class _CatalogClient extends GeminiModelCatalogClient {
  @override
  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    return const <GeminiModelDescriptor>[
      GeminiModelDescriptor(
        id: 'gemini-3.6-flash',
        displayName: 'Gemini 3.6 Flash',
        supportedGenerationMethods: <String>{'generateContent'},
      ),
    ];
  }
}

class _RecordingProductClient implements GeminiProductRecognitionPort {
  int requestCount = 0;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    requestCount += 1;
    return const ProductRecognitionCandidate(
      productName: '無糖綠茶',
      quantity: 2,
      unitPrice: 35,
      totalAmount: 70,
      categorySuggestion: '飲料水果',
      merchantName: '測試商店',
    );
  }
}
