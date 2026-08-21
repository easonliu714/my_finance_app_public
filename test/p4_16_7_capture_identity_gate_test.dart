import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/taiwan_tax_id.dart';

void main() {
  test('P4.16.7 seller identity evidence is checksum-gated for Live', () {
    expect(hasValidTaiwanTaxIdChecksum('30340553'), isTrue);
    expect(hasValidTaiwanTaxIdChecksum('30348553'), isFalse);

    final good = extractTraditionalSellerTaxIdEvidence(const <String>[
      'AA90000001',
      '一品現泡茶店',
      'NO.30340553',
    ]);
    final bad = extractTraditionalSellerTaxIdEvidence(const <String>[
      'AA90000001',
      '一品現泡茶店',
      'NO.30348553',
    ]);
    final unrelated = extractTraditionalSellerTaxIdEvidence(const <String>[
      '交易明細',
      'NO.30340553',
    ]);

    expect(good?.value, '30340553');
    expect(good?.acceptedForLive, isTrue);
    expect(bad, isNull);
    expect(unrelated, isNull);
  });

  test('Traditional Live freezes on repeated invoice plus merchant identity context', () {
    final history = <InvoiceLiveFrameEvidence>[
      _frame(
        invoiceNumber: 'XY90000020',
        rawLines: const <String>[
          '中華民國115年3-4月份',
          'XY 90000020',
          '昆現泡茶店',
          'AD.30349553',
        ],
      ),
      _frame(
        invoiceNumber: '',
        rawLines: const <String>[
          '中華民國115年3-4月份',
          'XY』9000002O',
          '一品克泡茶店',
          'HO.38348583',
        ],
      ),
    ];

    final consensus = resolveTraditionalLiveIdentityConsensus(
      history: history,
      currentInvoiceNumber: 'XY90000020',
      currentSellerTaxId: '',
      currentRawLines: const <String>[
        '中華民國115年3-4月份',
        'XY 90000020',
        'HO.38348583',
      ],
    );

    expect(consensus.invoiceNumber, 'XY90000020');
    expect(consensus.invoiceObservations, 2);
    expect(consensus.identityContextObservations, 2);
    expect(consensus.stableObservations, 2);
    expect(consensus.canFreeze, isTrue);
  });

  test('generic detail headers never satisfy Traditional seller identity context', () {
    expect(
      hasStrongTraditionalSellerIdentityContext(
        const <String>['交易明細', 'NO.30340553'],
      ),
      isFalse,
    );

    final consensus = resolveTraditionalLiveIdentityConsensus(
      history: <InvoiceLiveFrameEvidence>[
        _frame(
          invoiceNumber: 'XY90000020',
          rawLines: const <String>['交易明細', 'NO.30340553'],
        ),
      ],
      currentInvoiceNumber: 'XY90000020',
      currentSellerTaxId: '',
      currentRawLines: const <String>['商品明細', 'NO.30340553'],
    );

    expect(consensus.invoiceObservations, 2);
    expect(consensus.identityContextObservations, 0);
    expect(consensus.canFreeze, isFalse);
  });

  test('Live freeze contract keeps QR strict and Traditional temporal', () {
    final live = File('lib/features/invoice/invoice_live_capture_page.dart').readAsStringSync();
    expect(
      live,
      contains('validQr != null && invoiceNumber.isNotEmpty && sellerTaxId.isNotEmpty'),
    );
    expect(
      live,
      contains('InvoiceLiveClassification.traditional => traditionalConsensus.canFreeze'),
    );
    expect(live, contains('invoiceObservations >= 2'));
    expect(live, contains('identityContextObservations >= 2'));
    expect(live, contains('商家／統編 identity（必要）'));
    expect(live, contains('右 QR（選填）'));
    expect(live, contains('manualFreezeKey'));
    expect(live, contains('liveHistory'));
    expect(live, contains('_maxHistory = 10'));
  });

  test('production entry keeps only Live and image import visible', () {
    final entry = File('lib/features/invoice/invoice_capture_entry_page.dart').readAsStringSync();
    expect(entry, contains('Live 即時辨識'));
    expect(entry, contains('從圖片讀取'));
    expect(entry, isNot(contains('拍照／相簿辨識')));
    expect(entry, isNot(contains('Gemini 獨立驗證')));
  });

  test('post-freeze is Local-first with explicit completeness-gated Gemini paths', () {
    final frozen = File('lib/features/invoice/invoice_frozen_review_page.dart').readAsStringSync();
    final policy = File('lib/features/invoice/gemini/gemini_invoice_review_coordinator.dart').readAsStringSync();

    expect(
      frozen,
      contains('forceReview: _geminiDecision?.shouldReview != true'),
    );
    expect(frozen, contains('await _maybeRunAutomaticGemini(local);'));
    expect(
      frozen,
      contains('await _runGemini(local, forceReview: false, automatic: true);'),
    );
    expect(frozen, contains('reviewAutomatically('));
    expect(frozen, contains("label: Text(ai == null ? 'AI 覆核' : '重新 AI 覆核')"));
    expect(frozen, contains('RecognitionAiStatusIndicator('));
    expect(policy, contains('InvoiceLocalCompletenessPolicy().evaluate'));
    expect(policy, contains('shouldReview: completeness.requiresGeminiReview'));
    expect(policy, contains("if (candidate.sellerTaxId.isEmpty) '賣方統編'"));
    expect(policy, contains('TraditionalInvoiceOcrField.sellerTaxId'));
  });

  test('Evidence v6 keeps raw evidence and resilience telemetry key-safe', () {
    final evidence = File('lib/features/invoice/invoice_recognition_evidence_exporter.dart').readAsStringSync();
    expect(evidence, contains('invoice-recognition-evidence-v6'));
    expect(evidence, contains('ocrResult?.rawRecognition'));
    expect(evidence, contains('live_snapshot_history.json'));
    expect(evidence, contains("'apiKeyIncluded': false"));
    expect(evidence, contains("'automaticUploadPerformed': automaticUploadPerformed"));
    expect(evidence, contains('gemini_invocation_mode='));
    expect(evidence, contains('gemini_request_count='));
    expect(evidence, contains('logical_invocation_id='));
    expect(evidence, contains('active_model='));
    expect(evidence, contains('key_group_alias='));
    expect(evidence, contains('physical_attempt_count='));
    expect(evidence, contains('model_attempt_count='));
    expect(evidence, contains('key_group_attempt_count='));
    expect(evidence, contains('fallback_reason='));
    expect(evidence, isNot(contains('x-goog-api-key')));
  });
}

InvoiceLiveFrameEvidence _frame({
  required String invoiceNumber,
  required List<String> rawLines,
}) {
  return InvoiceLiveFrameEvidence(
    timestamp: DateTime.utc(2026, 8, 9),
    snapshot: InvoiceLiveSnapshot(
      classification: InvoiceLiveClassification.traditional,
      invoiceNumber: invoiceNumber,
    ),
    rawLines: rawLines,
    sellerTaxIdCandidate: '',
    sellerTaxIdSource: '',
    sellerTaxIdChecksumValid: null,
  );
}
