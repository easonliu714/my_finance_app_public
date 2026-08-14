import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test('forced OCR bypasses QR and creates review-only candidate', () async {
    var qrCallCount = 0;
    var ocrCallCount = 0;
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        qrCallCount += 1;
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.invalidInput,
          message: 'should not run',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (reference) async {
        ocrCallCount += 1;
        return TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.success,
          message: 'OCR candidate',
          candidate: _ocrCandidate(reference),
        );
      },
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[_image('/tmp/ocr.jpg')],
      requestedRoute:
          InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.ocrReviewCandidate);
    expect(result.requestedRoute,
        InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr);
    expect(result.wasUserOverridden, isTrue);
    expect(result.selectedRouteReason, contains('使用者改用'));
    expect(qrCallCount, 0);
    expect(ocrCallCount, 1);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('forced QR uses qrOnly and never calls OCR', () async {
    var qrMode = InvoiceLocalRecognitionRequestMode.automatic;
    var ocrCallCount = 0;
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        qrMode = mode;
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.manualQrDesignation,
          message: 'Need QR designation',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (reference) async {
        ocrCallCount += 1;
        return const TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.failed,
          message: 'should not run',
        );
      },
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[_image('/tmp/qr.jpg')],
      requestedRoute:
          InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
    );

    expect(qrMode, InvoiceLocalRecognitionRequestMode.qrOnly);
    expect(result.status,
        InvoiceAutomaticRecognitionStatus.manualQrDesignation);
    expect(result.requestedRoute,
        InvoiceRecognitionRequestedRoute.electronicInvoiceQr);
    expect(result.wasUserOverridden, isTrue);
    expect(ocrCallCount, 0);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('forced OCR failure remains fail closed', () async {
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.invalidInput,
          message: 'should not run',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (reference) async {
        return const TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.failed,
          message: 'OCR failed',
        );
      },
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[_image('/tmp/fail.jpg')],
      requestedRoute:
          InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    expect(result.status,
        InvoiceAutomaticRecognitionStatus.recognitionFailed);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.selectedRouteReason, contains('未建立覆核候選'));
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('invalid input preserves requested route without running recognizers',
      () async {
    var qrCallCount = 0;
    var ocrCallCount = 0;
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        qrCallCount += 1;
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.invalidInput,
          message: 'Invalid',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (reference) async {
        ocrCallCount += 1;
        return const TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.invalidInput,
          message: 'Invalid',
        );
      },
    );

    final result = await coordinator.recognize(
      images: const <ImageCaptureStagingItem>[],
      requestedRoute:
          InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.invalidInput);
    expect(result.requestedRoute,
        InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr);
    expect(qrCallCount, 0);
    expect(ocrCallCount, 0);
  });
}

ImageCaptureStagingItem _image(String reference) {
  return ImageCaptureStagingItem(
    id: reference,
    intent: DailyCaptureIntent.invoice,
    source: ImageCaptureStagingSource.gallery,
    localReference: reference,
    fileName: reference.split('/').last,
    status: ImageCaptureStagingStatus.pendingReview,
    createdAt: DateTime.utc(2026, 7, 6),
  );
}

TraditionalInvoiceOcrReviewCandidate _ocrCandidate(String reference) {
  return TraditionalInvoiceOcrReviewCandidate(
    sourceImageReference: reference,
    invoiceNumber: 'AB12345678',
    invoiceDate: DateTime.utc(2026, 7, 6),
    sellerName: '測試商家',
    totalAmount: 100,
    visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
    confidence: const <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{},
    fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
  );
}
