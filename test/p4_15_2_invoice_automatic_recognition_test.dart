import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  const leftPayload =
      'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

  test('valid QR review candidate wins and OCR is not called', () async {
    var ocrCallCount = 0;
    final routing = const InvoiceRecognitionRouter().route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/qr.jpg',
          fileName: 'qr.jpg',
          payloads: <String>[leftPayload, '**detail'],
        ),
      ],
    );
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        expect(mode, InvoiceLocalRecognitionRequestMode.automatic);
        return InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.qrCandidate,
          message: 'QR candidate',
          failedImageReferences: const <String>[],
          routingResult: routing,
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
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.qrReviewCandidate);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.selectedRouteReason, contains('優先使用 QR'));
    expect(ocrCallCount, 0);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('no valid QR falls back to local OCR review candidate', () async {
    var ocrReference = '';
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.ocrFallback,
          message: 'No QR',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (reference) async {
        ocrReference = reference;
        return TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.success,
          message: 'OCR candidate',
          candidate: _ocrCandidate(reference),
        );
      },
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[_image('/tmp/ocr.jpg')],
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.ocrReviewCandidate);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.selectedRouteReason, contains('改用本機傳統發票 OCR'));
    expect(ocrReference, '/tmp/ocr.jpg');
    expect(result.ocrResult?.candidate?.requiresUserReview, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('partial OCR candidate remains review-only', () async {
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.ocrFallback,
          message: 'No QR',
          failedImageReferences: <String>[],
        );
      },
      ocrRunner: (reference) async {
        return TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.partial,
          message: 'Partial OCR',
          candidate: TraditionalInvoiceOcrReviewCandidate(
            sourceImageReference: reference,
            invoiceNumber: '',
            invoiceDate: null,
            sellerName: '可見商家',
            totalAmount: null,
            visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
            confidence: const <TraditionalInvoiceOcrField,
                TraditionalInvoiceOcrConfidence>{},
            fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{
              TraditionalInvoiceOcrField.invoiceNumber: <String>[
                '請人工輸入。',
              ],
            },
          ),
        );
      },
    );

    final result = await coordinator.recognize(
      images: <ImageCaptureStagingItem>[_image('/tmp/partial.jpg')],
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.ocrReviewCandidate);
    expect(result.ocrResult?.status, TraditionalInvoiceOcrStatus.partial);
    expect(result.ocrResult?.candidate?.invoiceNumber, isEmpty);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('ambiguous QR remains manual and does not downgrade to OCR', () async {
    var ocrCallCount = 0;
    final routing = const InvoiceRecognitionRouter().route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/right.jpg',
          fileName: 'right.jpg',
          payloads: <String>['**right-only'],
        ),
      ],
    );
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.manualQrDesignation,
          message: 'Manual QR',
          failedImageReferences: const <String>[],
          routingResult: routing,
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
      images: <ImageCaptureStagingItem>[_image('/tmp/right.jpg')],
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.manualQrDesignation);
    expect(result.requiresManualQrDesignation, isTrue);
    expect(result.selectedRouteReason, contains('不降級為 OCR'));
    expect(ocrCallCount, 0);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('QR decoder failure is fail-closed and does not run OCR', () async {
    var ocrCallCount = 0;
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.decoderFailed,
          message: 'Decoder failed',
          failedImageReferences: <String>['/tmp/fail.jpg'],
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
      images: <ImageCaptureStagingItem>[_image('/tmp/fail.jpg')],
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.recognitionFailed);
    expect(result.selectedRouteReason, contains('fail-closed'));
    expect(ocrCallCount, 0);
    expect(result.hasReviewCandidate, isFalse);
  });

  test('OCR failure after no QR returns no review candidate', () async {
    final coordinator = InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async {
        return const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.ocrFallback,
          message: 'No QR',
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
      images: <ImageCaptureStagingItem>[_image('/tmp/none.jpg')],
    );

    expect(result.status, InvoiceAutomaticRecognitionStatus.recognitionFailed);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('invalid image input calls neither recognizer', () async {
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

    final result = await coordinator.recognize(images: const <ImageCaptureStagingItem>[]);

    expect(result.status, InvoiceAutomaticRecognitionStatus.invalidInput);
    expect(qrCallCount, 0);
    expect(ocrCallCount, 0);
    expect(result.canCreateFormalRecord, isFalse);
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
    createdAt: DateTime.utc(2026, 7, 5),
  );
}

TraditionalInvoiceOcrReviewCandidate _ocrCandidate(String reference) {
  return TraditionalInvoiceOcrReviewCandidate(
    sourceImageReference: reference,
    invoiceNumber: 'AB12345678',
    invoiceDate: DateTime.utc(2026, 7, 5),
    sellerName: '測試商家',
    totalAmount: 100,
    visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
    confidence: const <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{},
    fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
  );
}
