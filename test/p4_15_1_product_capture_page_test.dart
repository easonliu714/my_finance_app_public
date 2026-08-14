import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/production_image_capture.dart';
import 'package:my_finance_app/features/product/product_capture_page.dart';

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
    expect(coordinator.currentItem?.intent, DailyCaptureIntent.product);

    final discard = find.byKey(ProductCapturePage.discardActionKey);
    await tester.ensureVisible(discard);
    await tester.tap(discard);
    await tester.pumpAndSettle();
    expect(find.byKey(ProductCapturePage.stagedItemKey), findsNothing);
  });
}

class _GallerySource implements GalleryImageSource {
  const _GallerySource(this.image);

  final GalleryPickedImage? image;

  @override
  Future<GalleryPickedImage?> pickImage() async => image;
}
