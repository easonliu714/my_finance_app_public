import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_review.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/image_capture_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_review_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_total_evidence.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_multi_variant_recognizer.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test('Local parser 110 vs Field-First 118 fails closed end-to-end', () async {
    final coordinator = FieldFirstInvoiceCaptureReviewFlowCoordinator(
      liveResult: _galleryResult(),
      recognitionCoordinator: const InvoiceAutomaticRecognitionCoordinator(
        qrRunner: _qrFallback,
        ocrRunner: _local110WithSemantic118,
      ),
    );

    final result = await coordinator.recognize(
      image: _image(),
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    final candidate = result.recognitionResult.ocrResult?.candidate;
    expect(candidate, isNotNull);
    expect(candidate?.totalAmount, isNull);
    expect(
      result.formModel.fieldFor(InvoiceReviewFieldKey.totalAmount)?.value,
      isEmpty,
    );
    expect(
      candidate?.fieldWarnings[TraditionalInvoiceOcrField.totalAmount]
          ?.join(' '),
      contains('LOCAL_LOCAL_TOTAL_CONFLICT'),
    );
    expect(
      candidate?.rawLines,
      contains('P4_18_6_TOTAL_DECISION_LOCK=CONFLICT'),
    );
    expect(resolveInvoiceTotalEvidence(candidate!.rawLines), isNull);
    expect(
      result.recognitionResult.ocrResult?.rawRecognition?.totalAmount,
      110,
    );
    expect(result.formModel.canCreateFormalRecord, isFalse);
  });

  test('Gemini compact ROC period 1150506 canonicalizes to May-June', () {
    final candidate = GeminiInvoiceReviewCandidate.fromJson(
      const <String, Object?>{'invoicePeriod': '1150506'},
    );

    expect(candidate.invoicePeriod, '115年5-6月份');
  });

  test('separator-free ROC period normalization is strictly bimonthly', () {
    for (final raw in <String>[
      '1150505',
      '1150607',
      '1150512',
      '1151213',
      '0790102',
      '2010102',
    ]) {
      final candidate = GeminiInvoiceReviewCandidate.fromJson(
        <String, Object?>{'invoicePeriod': raw},
      );
      expect(candidate.invoicePeriod, raw, reason: 'must not normalize $raw');
    }

    final priorCompact = GeminiInvoiceReviewCandidate.fromJson(
      const <String, Object?>{'invoicePeriod': '11503-11504'},
    );
    expect(priorCompact.invoicePeriod, '115年3-4月份');
  });

  test('total merge fills only when parser is missing and semantic evidence exists', () {
    final merge = resolveInvoiceTotalMerge(
      parserValue: null,
      rawLines: const <String>['總計 110'],
    );

    expect(merge.decision, InvoiceTotalMergeDecision.fillFromSemanticEvidence);
    expect(merge.value, 110);
    expect(merge.semanticEvidence?.source, 'total_label');
  });

  test('equal parser and semantic total remains unchanged', () {
    final merge = resolveInvoiceTotalMerge(
      parserValue: 110,
      rawLines: const <String>['總計 110'],
    );

    expect(merge.decision, InvoiceTotalMergeDecision.unchanged);
    expect(merge.value, 110);
  });

  test('variant diagnostics record field votes without derivative paths', () async {
    final provider = _P4186VariantProvider();
    final recognizer = GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(
      engine: _MapTextEngine(<String, LocalOcrTextDocument>{
        '/original.jpg': _doc(<String>[
          '收銀機統一發票',
          'XY17859005',
        ]),
        '/gamma.png': _doc(<String>[
          '中華民國115年3-4月份',
          'XY17859005',
          '一品現泡茶店',
          '2026/04/18 14:59:52',
          '總計 95',
        ]),
        '/local.png': _doc(<String>[
          '中華民國115年3-4月份',
          'XY17859005',
          '一品現泡茶店',
          '2026/04/18 14:59:52',
          '總計 95',
        ]),
        '/threshold.png': _doc(<String>[
          '中華民國115年3-4月份',
          'XY17859005',
          '一品現泡菜店',
          '2026/04/18 14:59:52',
          '總計 98',
        ]),
      }),
      variantProvider: provider,
    );

    final result = await recognizer.recognizeLocalImage('/original.jpg');
    final diagnostics = result.variantDiagnostics;

    expect(diagnostics.map((item) => item.label), <String>[
      'original',
      'gamma_dark',
      'local_contrast',
      'adaptive_threshold',
    ]);
    expect(diagnostics[1].invoiceDate, DateTime.utc(2026, 4, 18));
    expect(diagnostics[1].invoiceTime, '14:59:52');
    expect(diagnostics[1].totalAmount, 95);
    expect(diagnostics[1].sellerName, '一品現泡茶店');
    expect(diagnostics[1].toJson().keys, isNot(contains('localReference')));
    expect(diagnostics[1].toJson().keys, isNot(contains('path')));
    expect(provider.cleanedUp, isTrue);
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

Future<TraditionalInvoiceOcrResult> _local110WithSemantic118(
  String localReference,
) async {
  const rawLines = <String>[
    'AA18231313',
    '一品現泡城店',
    '2026/05/23',
    '小',
    '計:118元',
    '現:110元',
  ];
  const raw = TraditionalInvoiceOcrRecognition(
    invoiceNumber: 'AA18231313',
    invoiceDate: null,
    sellerName: '一品現泡城店',
    totalAmount: 110,
    rawText: 'AA18231313\n一品現泡城店\n2026/05/23\n小\n計:118元\n現:110元',
    rawLines: rawLines,
  );
  return TraditionalInvoiceOcrResult(
    status: TraditionalInvoiceOcrStatus.partial,
    message: 'local candidate',
    rawRecognition: raw,
    candidate: TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: localReference,
      invoiceNumber: 'AA18231313',
      invoiceDate: DateTime.utc(2026, 5, 23),
      sellerName: '一品現泡城店',
      totalAmount: 110,
      visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
      confidence: const <TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>{},
      fieldWarnings: const <TraditionalInvoiceOcrField, List<String>>{},
      rawText: raw.rawText,
      rawLines: rawLines,
    ),
  );
}

ImageCaptureStagingItem _image() => ImageCaptureStagingItem(
      id: 'aa18231313',
      intent: DailyCaptureIntent.invoice,
      source: ImageCaptureStagingSource.gallery,
      localReference: '/tmp/aa18231313.jpg',
      fileName: 'aa18231313.jpg',
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: DateTime.utc(2026, 8, 18),
    );

InvoiceLiveCaptureResult _galleryResult() => const InvoiceLiveCaptureResult(
      localReference: '/tmp/aa18231313.jpg',
      fileName: 'aa18231313.jpg',
      classification: InvoiceLiveClassification.traditional,
      autoFrozen: false,
      origin: InvoiceCaptureOrigin.gallery,
      liveSnapshot: InvoiceLiveSnapshot(
        classification: InvoiceLiveClassification.traditional,
      ),
    );

LocalOcrTextDocument _doc(List<String> lines) => LocalOcrTextDocument(
      fullText: lines.join('\n'),
      lines: lines,
    );

class _MapTextEngine implements LocalOcrTextEngine {
  const _MapTextEngine(this.documents);

  final Map<String, LocalOcrTextDocument> documents;

  @override
  Future<LocalOcrTextDocument> recognize(String localReference) async {
    final document = documents[localReference];
    if (document == null) {
      throw StateError('No OCR fixture for $localReference');
    }
    return document;
  }
}

class _P4186VariantProvider implements TraditionalInvoiceImageVariantProvider {
  bool cleanedUp = false;

  @override
  Future<List<TraditionalInvoiceImageVariant>> createEnhancedVariants(
    String originalReference,
  ) async {
    return const <TraditionalInvoiceImageVariant>[
      TraditionalInvoiceImageVariant(
        label: 'gamma_dark',
        localReference: '/gamma.png',
      ),
      TraditionalInvoiceImageVariant(
        label: 'local_contrast',
        localReference: '/local.png',
      ),
      TraditionalInvoiceImageVariant(
        label: 'adaptive_threshold',
        localReference: '/threshold.png',
      ),
    ];
  }

  @override
  Future<void> cleanupVariants(
    List<TraditionalInvoiceImageVariant> variants,
  ) async {
    cleanedUp = true;
  }
}
