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
import 'package:my_finance_app/features/product/product_manual_review_card.dart';
import 'package:my_finance_app/features/product/product_recognition_candidate.dart';

void main() {
  Future<void> setTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ProductCapturePage page({
    required ProductionImageCaptureCoordinator coordinator,
    ProductRecognitionCoordinator? recognitionCoordinator,
  }) {
    return ProductCapturePage(
      coordinator: coordinator,
      recognitionCoordinator: recognitionCoordinator,
      categoryOptionsOverride: const <String>['飲料水果'],
      merchantOptionsOverride: const <String>[
        '不使用商家',
        '測試商店',
        '全家便利商店',
      ],
      accountOptionsOverride: const <String>['現金'],
    );
  }

  testWidgets('product page uses product-only camera and gallery flow',
      (tester) async {
    await setTallSurface(tester);
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
      MaterialApp(home: page(coordinator: coordinator)),
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
    expect(find.text('AI 辨識'), findsOneWidget);
    expect(find.text('人工覆核'), findsOneWidget);
    expect(find.text('正式記帳'), findsOneWidget);
    expect(find.textContaining('明確按下 AI 辨識'), findsOneWidget);
    expect(find.textContaining('仍需由你在新增記帳頁按下儲存'), findsOneWidget);
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
    await setTallSurface(tester);
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
        home: page(
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
    expect(find.text('AI 商品候選 · 人工覆核'), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.productNameFieldKey), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.quantityFieldKey), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.unitPriceFieldKey), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.totalAmountFieldKey), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.categoryFieldKey), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.merchantFieldKey), findsOneWidget);
    expect(find.byKey(ProductManualReviewCard.accountFieldKey), findsOneWidget);
    expect(find.byKey(ProductCapturePage.reviewedStatusKey), findsNothing);
  });

  testWidgets('manual review uses formal masters and must explicitly confirm',
      (tester) async {
    await setTallSurface(tester);
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
    final recognition = ProductRecognitionCoordinator(
      settingsStore: const _SettingsStore(
        GeminiInvoiceSettings(
          apiKeys: <String>['KEY_A'],
          model: 'gemini-3.6-flash',
        ),
      ),
      client: _RecordingProductClient(),
      imageLoader: _ImageLoader(),
      catalogClient: _CatalogClient(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: page(
          coordinator: capture,
          recognitionCoordinator: recognition,
        ),
      ),
    );
    await tester.tap(find.byKey(ProductCapturePage.galleryActionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProductCapturePage.aiRecognitionActionKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(ProductManualReviewCard.productNameFieldKey),
      '人工修正紅茶',
    );
    await tester.enterText(
      find.byKey(ProductManualReviewCard.quantityFieldKey),
      '0',
    );
    final confirm = find.byKey(ProductManualReviewCard.confirmKey);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(find.text('數量必須大於 0'), findsOneWidget);
    expect(find.text('請選擇消費扣款帳戶'), findsOneWidget);
    expect(find.byKey(ProductCapturePage.reviewedStatusKey), findsNothing);

    await tester.enterText(
      find.byKey(ProductManualReviewCard.quantityFieldKey),
      '3',
    );
    await tester.enterText(
      find.byKey(ProductManualReviewCard.unitPriceFieldKey),
      '25',
    );
    expect(
      (tester.widget<TextFormField>(
        find.byKey(ProductManualReviewCard.totalAmountFieldKey),
      ).controller?.text),
      '75',
    );

    await tester.enterText(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
      '80',
    );
    await tester.pump();
    final totalFieldAfterManual = tester.widget<TextFormField>(
      find.byKey(ProductManualReviewCard.totalAmountFieldKey),
    );
    expect(
      totalFieldAfterManual.decoration.helperText,
      contains('人工修改模式'),
    );

    await tester.tap(find.byKey(ProductManualReviewCard.merchantFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全家便利商店').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ProductManualReviewCard.accountFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('現金').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('已確認人工覆核'), findsOneWidget);
    expect(find.byKey(ProductCapturePage.reviewedStatusKey), findsOneWidget);
    expect(find.textContaining('目前仍未建立正式交易'), findsWidgets);
    expect(find.byKey(ProductCapturePage.transactionHandoffKey), findsOneWidget);
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
