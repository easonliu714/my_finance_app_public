import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test(
    'Frozen OCR failure preserves only safe Live exact-consensus review evidence',
    () async {
      final coordinator = FieldFirstInvoiceCaptureReviewFlowCoordinator(
        liveResult: _liveResult(),
        recognitionCoordinator: const InvoiceAutomaticRecognitionCoordinator(
          qrRunner: _qrFallback,
          ocrRunner: _failedFrozenOcr,
        ),
      );

      final result = await coordinator.recognize(
        image: _image(),
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      );

      expect(
        result.recognitionResult.status,
        InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
      );
      expect(result.recognitionResult.ocrResult?.candidate, isNotNull);
      expect(
        result.recognitionResult.ocrResult?.candidate?.invoiceNumber,
        'XY17859005',
      );
      expect(
        result.recognitionResult.ocrResult?.candidate?.sellerTaxId,
        isEmpty,
      );
      expect(
        result.recognitionResult.ocrResult?.candidate?.totalAmount,
        isNull,
      );
      expect(
        result.formModel
            .fieldFor(InvoiceReviewFieldKey.invoiceNumber)
            ?.value,
        'XY17859005',
      );
      expect(
        result.formModel.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value,
        '2026-04-18',
      );
      expect(
        result.formModel.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value,
        '14:59:52',
      );
      expect(
        result.formModel
            .fieldFor(InvoiceReviewFieldKey.invoiceTime)
            ?.confidenceLabel,
        'Live exact consensus fallback',
      );
      expect(
        result.formModel.fieldFor(InvoiceReviewFieldKey.invoicePeriod)?.value,
        '115年3-4月份',
      );
      expect(
        result.formModel.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value,
        isEmpty,
      );
      expect(
        result.formModel.fieldFor(InvoiceReviewFieldKey.totalAmount)?.value,
        isEmpty,
      );
      expect(result.formModel.canCreateFormalRecord, isFalse);
      expect(result.recognitionResult.canCreateFormalRecord, isFalse);
    },
  );

  test('conflicting Green dates remain blank instead of choosing last frame', () async {
    final coordinator = FieldFirstInvoiceCaptureReviewFlowCoordinator(
      liveResult: _liveResult(conflictingDate: true),
      recognitionCoordinator: const InvoiceAutomaticRecognitionCoordinator(
        qrRunner: _qrFallback,
        ocrRunner: _failedFrozenOcr,
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value,
      'XY17859005',
    );
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value,
      isEmpty,
    );
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value,
      '14:59:52',
    );
  });

  test('compact Gemini ROC period canonicalizes before comparison', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      const <String, Object?>{
        'invoicePeriod': '11503-11504',
      },
    );

    expect(candidate.invoicePeriod, '115年3-4月份');
    expect(
      normalizeInvoicePeriodForComparison(candidate.invoicePeriod),
      normalizeInvoicePeriodForComparison('115年3-4月份'),
    );
  });
}

Future<InvoiceLocalRecognitionResult> _qrFallback({
  required List<ImageCaptureStagingItem> images,
  required InvoiceLocalRecognitionRequestMode mode,
}) async {
  return const InvoiceLocalRecognitionResult(
    status: InvoiceLocalRecognitionStatus.ocrFallback,
    message: 'No QR candidate',
    failedImageReferences: <String>[],
  );
}

Future<TraditionalInvoiceOcrResult> _failedFrozenOcr(
  String localReference,
) async {
  return const TraditionalInvoiceOcrResult(
    status: TraditionalInvoiceOcrStatus.failed,
    message: '本機 OCR 未辨識到可供覆核的發票欄位。',
    rawRecognition: TraditionalInvoiceOcrRecognition(
      rawText: '中華民國115年3-4月份\nXY夏7859005',
      rawLines: <String>[
        '中華民國115年3-4月份',
        'XY夏7859005',
      ],
    ),
  );
}

ImageCaptureStagingItem _image() => ImageCaptureStagingItem(
      id: 'xy17859005',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.camera,
      localReference: '/tmp/xy17859005.jpg',
      fileName: 'xy17859005.jpg',
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: DateTime.utc(2026, 8, 17),
    );

InvoiceLiveCaptureResult _liveResult({bool conflictingDate = false}) {
  return InvoiceLiveCaptureResult(
    localReference: '/tmp/xy17859005.jpg',
    fileName: 'xy17859005.jpg',
    classification: InvoiceLiveClassification.traditional,
    autoFrozen: true,
    origin: InvoiceCaptureOrigin.liveCamera,
    liveSnapshot: const InvoiceLiveSnapshot(
      classification: InvoiceLiveClassification.traditional,
      invoiceNumber: 'XY17859005',
      invoiceDate: '2026-04-18',
      sellerTaxId: '33740553',
      hasSellerIdentityContext: true,
      totalAmount: 95,
      score: 0.9,
      stableObservations: 2,
      canFreeze: true,
      message: 'ready',
    ),
    liveHistory: <InvoiceLiveFrameEvidence>[
      _frame(date: '2026-04-18'),
      _frame(date: conflictingDate ? '2026-04-19' : '2026-04-18'),
      _frame(date: conflictingDate ? '2026-04-18' : '2026-04-18'),
    ],
  );
}

InvoiceLiveFrameEvidence _frame({required String date}) {
  return InvoiceLiveFrameEvidence(
    timestamp: DateTime.utc(2026, 8, 17, 14, 59, 52),
    snapshot: InvoiceLiveSnapshot(
      classification: InvoiceLiveClassification.traditional,
      invoiceNumber: 'XY17859005',
      invoiceDate: date,
      sellerTaxId: '33740553',
      hasSellerIdentityContext: true,
      totalAmount: 95,
      score: 0.9,
      stableObservations: 2,
      canFreeze: true,
      message: 'ready',
    ),
    rawLines: const <String>[
      'XY17859005',
      '2026/04/18 14:59:52',
    ],
    sellerTaxIdCandidate: '33740553',
    sellerTaxIdSource: 'yellow_capture_only',
    sellerTaxIdChecksumValid: true,
  );
}
