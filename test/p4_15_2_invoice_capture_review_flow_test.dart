import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_capture_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_card.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/production_image_capture.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test('capture review flow maps recognition into safe review form', () async {
    final flow = _reviewFlow();
    final item = ImageCaptureStagingItem(
      id: 'image-1',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.gallery,
      localReference: '/tmp/private-invoice.jpg',
      fileName: 'invoice.jpg',
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: DateTime.utc(2026, 7, 6),
    );

    final result = await flow.recognize(
      image: item,
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    expect(result.canOpenReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.usedNetwork, isFalse);
    expect(
      result.formModel
          .fieldFor(InvoiceReviewFieldKey.invoiceNumber)
          ?.value,
      'AB12345678',
    );
    expect(
      result.toSafeSummary().toString(),
      isNot(contains('/tmp/private-invoice.jpg')),
    );
  });

  testWidgets('capture page reaches review card without formal write',
      (tester) async {
    final captureCoordinator = ProductionImageCaptureCoordinator(
      stagingService: ImageCaptureStagingService(
        gallerySource: const _FakeGallerySource(),
        clock: () => DateTime.utc(2026, 7, 6),
        idFactory: () => 'gallery-1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceCapturePage(
          coordinator: captureCoordinator,
          reviewFlowCoordinator: _reviewFlow(),
        ),
      ),
    );

    await tester.tap(find.byKey(InvoiceCapturePage.galleryActionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(InvoiceCapturePage.stagedItemKey), findsOneWidget);

    await tester.tap(find.byKey(InvoiceCapturePage.recognizeActionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(InvoiceCapturePage.recognitionStatusKey), findsOneWidget);
    expect(find.byKey(InvoiceCapturePage.reviewCardKey), findsOneWidget);

    final continueFinder = find.byKey(InvoiceReviewFormCard.continueKey);
    expect(tester.widget<FilledButton>(continueFinder).onPressed, isNull);

    final acknowledgementFinder =
        find.byKey(InvoiceReviewFormCard.acknowledgementKey);
    await tester.scrollUntilVisible(
      acknowledgementFinder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(acknowledgementFinder);
    await tester.pump();

    expect(tester.widget<FilledButton>(continueFinder).onPressed, isNotNull);
    await tester.scrollUntilVisible(
      continueFinder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(continueFinder);
    await tester.pump();

    expect(
      find.byKey(InvoiceCapturePage.reviewCompleteMessageKey),
      findsOneWidget,
    );
    expect(captureCoordinator.currentItem, isNotNull);
    expect(captureCoordinator.hasPendingReview, isTrue);
  });
}

InvoiceCaptureReviewFlowCoordinator _reviewFlow() {
  return InvoiceCaptureReviewFlowCoordinator(
    recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.ocrFallback,
          message: 'No valid QR; use local OCR.',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (localReference) async {
        return TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.success,
          message: 'OCR review candidate ready.',
          candidate: TraditionalInvoiceOcrReviewCandidate(
            sourceImageReference: localReference,
            invoiceNumber: 'AB12345678',
            invoiceDate: DateTime.utc(2026, 7, 6),
            sellerName: 'Test merchant',
            totalAmount: 120,
            visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
            confidence: const <TraditionalInvoiceOcrField,
                TraditionalInvoiceOcrConfidence>{},
            fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
          ),
        );
      },
    ),
  );
}

class _FakeGallerySource implements GalleryImageSource {
  const _FakeGallerySource();

  @override
  Future<GalleryPickedImage?> pickImage() async {
    return const GalleryPickedImage(
      reference: '/tmp/private-invoice.jpg',
      name: 'invoice.jpg',
    );
  }
}
