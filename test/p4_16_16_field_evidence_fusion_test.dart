import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_live_field_readiness.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_total_evidence.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';
import 'package:my_finance_app/features/invoice/traditional_tax_id_temporal_repair.dart';

void main() {
  test('type-agnostic readiness depends on stable fields, not classification', () {
    const consensus = TraditionalLiveIdentityConsensus(
      invoiceNumber: 'BR90000014',
      invoiceObservations: 2,
      identityContextObservations: 2,
      currentFrameRelevant: true,
    );

    final first = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'BR90000014',
      sellerTaxId: '',
      hasSellerIdentityContext: true,
      previousSignature: '',
      previousConsecutiveObservations: 0,
    );
    final second = resolveInvoiceLiveFieldReadiness(
      consensus: consensus,
      invoiceNumber: 'BR90000014',
      sellerTaxId: '',
      hasSellerIdentityContext: true,
      previousSignature: first.signature,
      previousConsecutiveObservations: first.consecutiveObservations,
    );

    expect(first.canFreeze, isFalse);
    expect(first.stableObservations, 1);
    expect(second.canFreeze, isTrue);
    expect(second.stableObservations, 2);
    expect(second.signature, 'BR90000014||true');
  });

  test('AA physical total evidence prefers reconstructed subtotal over cash tender', () {
    final evidence = resolveInvoiceTotalEvidence(const <String>[
      '小收',
      '計:110元',
      '現:118元',
    ]);

    expect(evidence, isNotNull);
    expect(evidence!.value, 110);
    expect(evidence.source, 'subtotal_label_split_reconstruction');
    expect(evidence.priority, greaterThan(10));
  });

  test('AA effective total is corrected while raw Frozen OCR remains 118', () async {
    final coordinator = _coordinator(
      liveResult: _liveResult(invoiceNumber: 'AA90000001'),
      ocrResult: _ocrResult(
        invoiceNumber: 'AA90000001',
        sellerTaxId: '30340553',
        totalAmount: 118,
        rawLines: const <String>[
          'AA90000001',
          '30340553',
          '小收',
          '計:110元',
          '現:118元',
        ],
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    expect(result.recognitionResult.ocrResult!.candidate!.totalAmount, 110);
    expect(result.recognitionResult.ocrResult!.rawRecognition!.totalAmount, 118);
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.totalAmount)?.value,
      '110.0',
    );
  });

  test('CD fuses one Live candidate with Frozen candidate without new repair rule',
      () async {
    final coordinator = _coordinator(
      liveResult: _liveResult(
        invoiceNumber: 'CD90000017',
        history: <InvoiceLiveFrameEvidence>[
          _frame('CD90000017', '30348553'),
        ],
      ),
      ocrResult: _ocrResult(
        invoiceNumber: 'CD90000017',
        totalAmount: 80,
        rawLines: const <String>[
          'CD90000017',
          '30349553',
          '總計 80',
        ],
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );
    final ocr = result.recognitionResult.ocrResult!;

    expect(ocr.candidate!.sellerTaxId, '30340553');
    expect(
      ocr.candidate!.sellerTaxIdSource,
      positionalTaxIdTemporalRepairSource,
    );
    expect(ocr.rawRecognition!.sellerTaxId, isNull);
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value,
      '30340553',
    );
  });

  test('field-first form exposes seller tax, period and random code as fields',
      () async {
    final coordinator = _coordinator(
      liveResult: _liveResult(invoiceNumber: 'DM90000019'),
      ocrResult: _ocrResult(
        invoiceNumber: 'DM90000019',
        sellerTaxId: '76631800',
        totalAmount: 120,
        rawLines: const <String>[
          '中華民國115年7-8月份',
          'DM90000019',
          '隨機碼：4932',
          '賣方 76631800',
          '總計 120',
        ],
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.invoicePeriod)?.value,
      '115年7-8月份',
    );
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value,
      '76631800',
    );
    expect(
      result.formModel
          .fieldFor(InvoiceReviewFieldKey.sellerTaxId)
          ?.requiredForReview,
      isTrue,
    );
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.randomCode)?.value,
      '4932',
    );
  });

  test('Gemini random code is optional but must be exactly four digits', () {
    final valid = GeminiInvoiceReviewCandidate.fromJson(<String, Object?>{
      'invoiceNumber': 'DM90000019',
      'invoicePeriod': '115年7-8月份',
      'randomCode': '4932',
      'sellerTaxId': null,
      'invoiceDate': null,
      'invoiceTime': null,
      'merchantName': null,
      'totalAmount': null,
      'lineItems': const <Object?>[],
      'confidence': <String, Object?>{'randomCode': 0.95},
      'warnings': const <Object?>[],
    });
    expect(valid.randomCode, '4932');
    expect(valid.confidence[GeminiInvoiceReviewField.randomCode], 0.95);

    final invalid = GeminiInvoiceReviewCandidate.fromJson(<String, Object?>{
      'randomCode': '493',
      'lineItems': const <Object?>[],
      'warnings': const <Object?>[],
    });
    expect(invalid.randomCode, isEmpty);
    expect(invalid.warnings.join('\n'), contains('隨機碼不是完整 4 碼'));
  });
}

FieldFirstInvoiceCaptureReviewFlowCoordinator _coordinator({
  required InvoiceLiveCaptureResult liveResult,
  required TraditionalInvoiceOcrResult ocrResult,
}) {
  return FieldFirstInvoiceCaptureReviewFlowCoordinator(
    liveResult: liveResult,
    recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
      qrRunner: ({required images, required mode}) async =>
          const InvoiceLocalRecognitionResult(
        status: InvoiceLocalRecognitionStatus.ocrFallback,
        message: 'no valid qr',
        failedImageReferences: <String>[],
      ),
      ocrRunner: (reference) async => ocrResult,
    ),
  );
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
  required String invoiceNumber,
  List<InvoiceLiveFrameEvidence> history = const <InvoiceLiveFrameEvidence>[],
}) =>
    InvoiceLiveCaptureResult(
      localReference: '/tmp/invoice.jpg',
      fileName: 'invoice.jpg',
      classification: InvoiceLiveClassification.electronic,
      autoFrozen: false,
      liveSnapshot: InvoiceLiveSnapshot(
        classification: InvoiceLiveClassification.electronic,
        invoiceNumber: invoiceNumber,
      ),
      liveHistory: history,
    );

InvoiceLiveFrameEvidence _frame(String invoiceNumber, String rawTaxId) =>
    InvoiceLiveFrameEvidence(
      timestamp: DateTime.utc(2026, 8, 12),
      snapshot: InvoiceLiveSnapshot(
        classification: InvoiceLiveClassification.traditional,
        invoiceNumber: invoiceNumber,
      ),
      rawLines: <String>[invoiceNumber, rawTaxId],
      sellerTaxIdCandidate: rawTaxId,
      sellerTaxIdSource: positionalTaxIdUnverifiedSource,
      sellerTaxIdChecksumValid: false,
    );

TraditionalInvoiceOcrResult _ocrResult({
  required String invoiceNumber,
  String sellerTaxId = '',
  required double totalAmount,
  required List<String> rawLines,
}) {
  final raw = TraditionalInvoiceOcrRecognition(
    invoiceNumber: invoiceNumber,
    sellerTaxId: sellerTaxId.isEmpty ? null : sellerTaxId,
    invoiceDate: DateTime.utc(2026, 8, 1),
    sellerName: '測試商店',
    totalAmount: totalAmount,
    rawText: rawLines.join('\n'),
    rawLines: rawLines,
  );
  return TraditionalInvoiceOcrResult(
    status: TraditionalInvoiceOcrStatus.partial,
    message: 'partial',
    candidate: TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: '/tmp/invoice.jpg',
      invoiceNumber: invoiceNumber,
      sellerTaxId: sellerTaxId,
      sellerTaxIdSource:
          sellerTaxId.isEmpty ? '' : 'positional_header_8digit',
      invoiceDate: raw.invoiceDate,
      sellerName: raw.sellerName!,
      totalAmount: totalAmount,
      visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
      confidence: const <TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>{},
      fieldWarnings: sellerTaxId.isEmpty
          ? const <TraditionalInvoiceOcrField, List<String>>{
              TraditionalInvoiceOcrField.sellerTaxId: <String>['missing'],
            }
          : const <TraditionalInvoiceOcrField, List<String>>{},
      rawText: raw.rawText,
      rawLines: rawLines,
    ),
    rawRecognition: raw,
  );
}
