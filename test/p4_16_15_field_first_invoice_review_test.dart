import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_evidence.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';
import 'package:my_finance_app/features/invoice/traditional_tax_id_temporal_repair.dart';

void main() {
  test('field-first evidence extracts printed period and explicit random code', () {
    final evidence = parseInvoiceFieldFirstEvidence(const <String>[
      '中華民國 115年 7-8 月份',
      '隨機碼：12O4',
    ]);

    expect(evidence.invoicePeriod, '115年7-8月份');
    expect(evidence.randomCode, '1204');
    expect(evidence.randomCodeSource, 'explicit_random_code_label');
    expect(evidence.suggestsElectronicInvoice, isTrue);
  });

  test('random code requires explicit label and exactly four normalized digits', () {
    expect(
      parseInvoiceFieldFirstEvidence(const <String>['1234']).randomCode,
      isEmpty,
    );
    expect(
      parseInvoiceFieldFirstEvidence(const <String>['隨機碼：123']).randomCode,
      isEmpty,
    );
    expect(
      parseInvoiceFieldFirstEvidence(const <String>['隨機碼', 'O1I4'])
          .randomCode,
      '0114',
    );
  });

  test('electronic requested route falls back to OCR fields when QR is unusable',
      () async {
    var qrMode = InvoiceLocalRecognitionRequestMode.qrOnly;
    var ocrCalls = 0;
    final coordinator = FieldFirstInvoiceCaptureReviewFlowCoordinator(
      liveResult: _liveResult(),
      recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
        qrRunner: ({required images, required mode}) async {
          qrMode = mode;
          return const InvoiceLocalRecognitionResult(
            status: InvoiceLocalRecognitionStatus.ocrFallback,
            message: 'no valid qr',
            failedImageReferences: <String>[],
          );
        },
        ocrRunner: (reference) async {
          ocrCalls += 1;
          return _ocrResult(
            rawLines: const <String>[
              '中華民國115年7-8月份',
              'DM90000019',
              '隨機碼：5566',
              '總計 100',
            ],
          );
        },
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
    );

    expect(qrMode, InvoiceLocalRecognitionRequestMode.automatic);
    expect(ocrCalls, 1);
    expect(
      result.recognitionResult.status,
      InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
    );
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.invoicePeriod)?.value,
      '115年7-8月份',
    );
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.randomCode)?.value,
      '5566',
    );
    expect(result.formModel.warnings.join('\n'), contains('QR 不可用'));
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('temporal seller tax repair becomes effective local value but raw stays raw',
      () async {
    final coordinator = FieldFirstInvoiceCaptureReviewFlowCoordinator(
      liveResult: _liveResult(
        history: <InvoiceLiveFrameEvidence>[
          _frame('30348553'),
          _frame('38348553'),
        ],
      ),
      recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
        qrRunner: ({required images, required mode}) async =>
            const InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.ocrFallback,
          message: 'no valid qr',
          failedImageReferences: <String>[],
        ),
        ocrRunner: (reference) async => _ocrResult(
          invoiceNumber: 'CD90000017',
          rawLines: const <String>[
            '中華民國115年7-8月份',
            'CD90000017',
            '總計 80',
          ],
        ),
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );
    final ocr = result.recognitionResult.ocrResult!;

    expect(ocr.candidate!.sellerTaxId, '30340553');
    expect(
      ocr.candidate!.sellerTaxIdSource,
      positionalTaxIdTemporalRepairSource,
    );
    expect(ocr.rawRecognition!.sellerTaxId, isNull);
    expect(result.canCreateFormalRecord, isFalse);
  });
}

ImageCaptureStagingItem _image() => ImageCaptureStagingItem(
      id: 'fixture',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.camera,
      localReference: '/tmp/invoice.jpg',
      fileName: 'invoice.jpg',
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: DateTime.utc(2026, 8, 12),
    );

InvoiceLiveCaptureResult _liveResult({
  List<InvoiceLiveFrameEvidence> history = const <InvoiceLiveFrameEvidence>[],
}) =>
    InvoiceLiveCaptureResult(
      localReference: '/tmp/invoice.jpg',
      fileName: 'invoice.jpg',
      classification: InvoiceLiveClassification.electronic,
      autoFrozen: false,
      liveSnapshot: const InvoiceLiveSnapshot(
        classification: InvoiceLiveClassification.electronic,
        invoiceNumber: 'CD90000017',
      ),
      liveHistory: history,
    );

InvoiceLiveFrameEvidence _frame(String rawTaxId) => InvoiceLiveFrameEvidence(
      timestamp: DateTime.utc(2026, 8, 12),
      snapshot: const InvoiceLiveSnapshot(
        classification: InvoiceLiveClassification.traditional,
        invoiceNumber: 'CD90000017',
      ),
      rawLines: <String>['CD90000017', rawTaxId],
      sellerTaxIdCandidate: rawTaxId,
      sellerTaxIdSource: positionalTaxIdUnverifiedSource,
      sellerTaxIdChecksumValid: false,
    );

TraditionalInvoiceOcrResult _ocrResult({
  String invoiceNumber = 'DM90000019',
  required List<String> rawLines,
}) {
  final raw = TraditionalInvoiceOcrRecognition(
    invoiceNumber: invoiceNumber,
    invoiceDate: DateTime.utc(2026, 8, 1),
    sellerName: '測試商店',
    totalAmount: 100,
    rawText: rawLines.join('\n'),
    rawLines: rawLines,
  );
  return TraditionalInvoiceOcrResult(
    status: TraditionalInvoiceOcrStatus.partial,
    message: 'partial',
    candidate: TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: '/tmp/invoice.jpg',
      invoiceNumber: invoiceNumber,
      invoiceDate: raw.invoiceDate,
      sellerName: raw.sellerName!,
      totalAmount: raw.totalAmount,
      visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
      confidence: const <TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>{},
      fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{
        TraditionalInvoiceOcrField.sellerTaxId: <String>['missing'],
      },
      rawText: raw.rawText,
      rawLines: rawLines,
    ),
    rawRecognition: raw,
  );
}
