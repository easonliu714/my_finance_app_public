import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_page.dart';
import 'package:my_finance_app/features/invoice/production_image_capture.dart';

void main() {
  testWidgets('invoice capture exposes production modes and concise help',
      (tester) async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(
          GalleryPickedImage(
            reference: 'local-invoice.jpg',
            name: 'invoice.jpg',
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: InvoiceCapturePage(coordinator: coordinator)),
    );

    expect(find.text('發票辨識'), findsOneWidget);
    expect(find.byKey(InvoiceCapturePage.automaticModeKey), findsOneWidget);
    expect(
      find.byKey(InvoiceCapturePage.traditionalOcrModeKey),
      findsOneWidget,
    );
    expect(find.byKey(InvoiceCapturePage.qrPairModeKey), findsOneWidget);
    expect(find.byKey(InvoiceCapturePage.manualModeKey), findsOneWidget);
    expect(find.text('拍商品'), findsNothing);
    expect(
      find.byKey(InvoiceCapturePage.disclaimerKey),
      findsOneWidget,
    );
    expect(find.textContaining('本階段'), findsNothing);
    expect(find.text('本機優先、人工覆核'), findsNothing);

    await tester.tap(find.byKey(InvoiceCapturePage.helpKey));
    await tester.pumpAndSettle();

    expect(find.text('發票辨識使用說明'), findsOneWidget);
    expect(find.textContaining('左右兩個 QR Code'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(InvoiceCapturePage.galleryActionKey));
    await tester.pumpAndSettle();

    expect(find.byKey(InvoiceCapturePage.stagedItemKey), findsOneWidget);
    expect(find.text('invoice.jpg'), findsOneWidget);
    expect(find.text('辨識方式：自動辨識'), findsOneWidget);

    final discard = find.byKey(InvoiceCapturePage.discardActionKey);
    await tester.ensureVisible(discard);
    await tester.pumpAndSettle();
    await tester.tap(discard);
    await tester.pumpAndSettle();

    expect(find.byKey(InvoiceCapturePage.stagedItemKey), findsNothing);
    expect(coordinator.currentItem, isNull);
  });

  testWidgets('unavailable camera fails closed', (tester) async {
    final coordinator = ProductionImageCaptureCoordinator(
      stagingService: const ImageCaptureStagingService(
        gallerySource: _GallerySource(null),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: InvoiceCapturePage(coordinator: coordinator)),
    );

    await tester.tap(find.byKey(InvoiceCapturePage.cameraActionKey));
    await tester.pumpAndSettle();

    expect(find.byKey(InvoiceCapturePage.statusMessageKey), findsOneWidget);
    expect(find.textContaining('目前無法使用此影像來源'), findsOneWidget);
  });
}

class _GallerySource implements GalleryImageSource {
  const _GallerySource(this.image);

  final GalleryPickedImage? image;

  @override
  Future<GalleryPickedImage?> pickImage() async => image;
}
