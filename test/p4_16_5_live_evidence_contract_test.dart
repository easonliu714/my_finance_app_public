import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.17 keeps P4.16.16 safety baseline under adaptive Live guidance', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router = File('lib/routing/app_router.dart').readAsStringSync();
    final entry = File('lib/features/invoice/invoice_capture_entry_page.dart').readAsStringSync();
    final live = File('lib/features/invoice/invoice_live_capture_stabilized_page.dart').readAsStringSync();
    final adaptive = File('lib/features/invoice/invoice_live_capture_adaptive_page.dart').readAsStringSync();
    final readiness = File('lib/features/invoice/invoice_live_field_readiness.dart').readAsStringSync();
    final totalEvidence = File('lib/features/invoice/invoice_total_evidence.dart').readAsStringSync();
    final parser = File('lib/features/invoice/google_mlkit_traditional_invoice_recognizer.dart').readAsStringSync();
    final repair = File('lib/features/invoice/traditional_tax_id_temporal_repair.dart').readAsStringSync();
    final registry = File('lib/features/invoice/taiwan_business_registry_validation.dart').readAsStringSync();
    final frozen = File('lib/features/invoice/invoice_frozen_review_page.dart').readAsStringSync();
    final fieldFirst = File('lib/features/invoice/invoice_field_first_review_flow.dart').readAsStringSync();
    final fieldEvidence = File('lib/features/invoice/invoice_field_first_evidence.dart').readAsStringSync();
    final formPresenter = File('lib/features/invoice/invoice_field_first_review_form_presenter.dart').readAsStringSync();
    final form = File('lib/features/invoice/invoice_review_form_view_model.dart').readAsStringSync();
    final evidenceExporter = File('lib/features/invoice/invoice_recognition_evidence_exporter.dart').readAsStringSync();
    final geminiCandidate = File('lib/features/invoice/gemini/gemini_invoice_review.dart').readAsStringSync();
    final geminiClient = File('lib/features/invoice/gemini/gemini_invoice_review_client.dart').readAsStringSync();

    expect(pubspec, contains('version: 4.17.4+426'));
    expect(pubspec, contains('camera: ^0.12.0+1'));
    expect(pubspec, contains('google_mlkit_barcode_scanning: ^0.14.2'));
    expect(pubspec, contains('archive: ^4.0.9'));

    expect(router, contains('InvoiceCaptureEntryPage'));
    expect(router, contains('InvoiceImageImportPage.routeName'));
    expect(router, contains('InvoiceLiveCapturePage.routeName'));
    expect(router, contains('AdaptiveInvoiceLiveCapturePage'));
    expect(router, contains('InvoiceFrozenReviewPage.routeName'));
    expect(router, contains('FieldFirstInvoiceCaptureReviewFlowCoordinator.production'));
    expect(entry, contains('Live 即時辨識'));
    expect(entry, contains('從圖片讀取'));
    expect(entry, isNot(contains('拍照／相簿辨識')));
    expect(entry, isNot(contains('Gemini 獨立驗證')));

    expect(live, contains('startImageStream'));
    expect(live, contains('Duration(milliseconds: 1200)'));
    expect(live, contains('setFocusMode(FocusMode.locked)'));
    expect(live, contains('setExposureMode(ExposureMode.locked)'));
    expect(live, contains('Duration(milliseconds: 250)'));
    expect(live, contains('THREE_A_SETTLED'));
    expect(live, contains('stopImageStream'));
    expect(live, contains('takePicture()'));
    expect(live, contains('FROZEN_IDENTITY_CHECK'));
    expect(live, contains('isFrozenInvoiceIdentityConsistent'));
    expect(live, contains('_cameraInitializing'));
    expect(live, contains('_cameraGeneration'));

    expect(adaptive, contains('startImageStream'));
    expect(adaptive, contains('Duration(milliseconds: 1200)'));
    expect(adaptive, contains('setFocusMode(FocusMode.locked)'));
    expect(adaptive, contains('setExposureMode(ExposureMode.locked)'));
    expect(adaptive, contains('Duration(milliseconds: 250)'));
    expect(adaptive, contains('THREE_A_SETTLED'));
    expect(adaptive, contains('FROZEN_IDENTITY_CHECK'));
    expect(adaptive, contains('final accepted = !auto || identityMatches'));
    expect(adaptive, contains("'adaptiveGuidanceAffectsAcceptance': false"));

    expect(live, contains('resolveInvoiceLiveFieldReadiness'));
    expect(live, contains('classificationAdvisoryOnly'));
    expect(live, contains('final accepted = !auto || identityMatches'));
    expect(live, isNot(contains('electronicQrMatches')));
    expect(live, contains('左 QR（選填加強）'));
    expect(live, contains('賣方統編／商家 identity（必要）'));
    expect(live, contains('resolveInvoiceTotalEvidence'));
    expect(readiness, contains('consensus.canFreeze && stable >= 2'));
    expect(readiness, isNot(contains('InvoiceLiveClassification')));
    expect(readiness, isNot(contains('hasValidLeftQr')));

    expect(totalEvidence, contains("('total_label', 40)"));
    expect(totalEvidence, contains("('subtotal_label', 35)"));
    expect(totalEvidence, contains("('payable_label', 30)"));
    expect(totalEvidence, contains("('cash_tender_label', 10)"));
    expect(totalEvidence, contains("previous.startsWith('小')"));

    expect(parser, contains('LocalOcrTextLine'));
    expect(parser, contains('positionedLines'));
    expect(parser, contains('hasStrongElectronicInvoiceSemanticEvidence'));
    expect(parser, contains("source: 'positional_header_8digit'"));
    expect(parser, contains('hasValidTaiwanTaxIdChecksum'));

    expect(repair, contains("'positional_header_8digit_temporal_repair'"));
    expect(repair, contains('single_8_to_0_checksum'));
    expect(repair, contains('family.length < 2'));
    expect(repair, contains('targets.length != 1'));
    expect(repair, isNot(contains('9_to_0')));
    expect(repair, isNot(contains('http')));
    expect(repair, isNot(contains('data.gcis.nat.gov.tw')));
    expect(fieldFirst, contains('_resolveLiveFrozenTemporalTaxRepair'));
    expect(fieldFirst, contains('frozenRawCandidate'));
    expect(fieldFirst, contains('currentRawCandidate: frozenRawCandidate'));
    expect(fieldFirst, contains('resolveInvoiceTotalEvidence'));
    expect(fieldFirst, contains('rawRecognition: source.rawRecognition'));
    expect(fieldFirst, isNot(contains('TransactionRepository')));
    expect(fieldFirst, isNot(contains('TaiwanBusinessRegistryService')));

    expect(frozen, contains('positionalTaxIdTemporalRepairSource'));
    expect(frozen, contains('extractUnverifiedPositionalHeaderTaxIdFromLines'));
    expect(frozen, isNot(contains('data.gcis.nat.gov.tw')));

    expect(fieldEvidence, contains('invoicePeriod'));
    expect(fieldEvidence, contains('randomCode'));
    expect(form, contains('sellerTaxId'));
    expect(formPresenter, contains("label: '賣方統編'"));
    expect(formPresenter, contains('requiredForReview: true'));
    expect(formPresenter, contains("label: '發票期別'"));
    expect(formPresenter, contains("label: '隨機碼'"));

    expect(evidenceExporter, contains('InvoiceReviewFieldKey.sellerTaxId'));
    expect(evidenceExporter, contains('InvoiceReviewFieldKey.invoicePeriod'));
    expect(evidenceExporter, contains('InvoiceReviewFieldKey.randomCode'));
    expect(evidenceExporter, contains("'randomCode': candidate.randomCode"));
    expect(evidenceExporter, isNot(contains("('invoicePeriod', '', ai.invoicePeriod")));

    expect(geminiCandidate, contains('randomCode'));
    expect(geminiCandidate, contains('AI 隨機碼不是完整 4 碼'));
    expect(geminiClient, contains("'randomCode': <String, Object?>"));
    expect(geminiClient, contains('randomCode 只有在影像明確出現「隨機碼」標籤'));

    expect(registry, contains('TaiwanBusinessRegistryService'));
    expect(registry, contains('data.gcis.nat.gov.tw'));
    expect(registry, contains('authorizesTaxIdRepair => false'));
    expect(registry, contains('authorizesFormalWrite => false'));
    expect(live, isNot(contains('TaiwanBusinessRegistryService')));
    expect(adaptive, isNot(contains('TaiwanBusinessRegistryService')));
    expect(frozen, isNot(contains('TaiwanBusinessRegistryService')));
  });

  test('single image is the Local and Gemini source', () {
    final frozen = File('lib/features/invoice/invoice_frozen_review_page.dart').readAsStringSync();
    final coordinator = File('lib/features/invoice/gemini/gemini_invoice_review_coordinator.dart').readAsStringSync();
    final client = File('lib/features/invoice/gemini/gemini_invoice_review_client.dart').readAsStringSync();

    expect(frozen, contains('localReference: _item.localReference'));
    expect(frozen, contains('image: _item'));
    expect(coordinator, contains('bytes: await file.readAsBytes()'));
    expect(client, contains('base64Encode(imageBytes)'));
    expect(client, isNot(contains('copyResize')));
    expect(client, isNot(contains('cropImage')));
  });

  test('Evidence v4 keeps provenance and safety boundaries', () {
    final evidence = File('lib/features/invoice/invoice_recognition_evidence_exporter.dart').readAsStringSync();

    expect(evidence, contains('invoice-recognition-evidence-v4'));
    expect(evidence, contains("'capture_image."));
    expect(evidence, contains("'gemini_input."));
    expect(evidence, contains("'local_ocr_raw.txt'"));
    expect(evidence, contains("'live_snapshot_history.json'"));
    expect(evidence, contains('ocrResult?.rawRecognition'));
    expect(evidence, contains('capture_sha256='));
    expect(evidence, contains('gemini_input_matches_capture_sha256='));
    expect(
      evidence,
      contains('String appVersion = PrivateCloudInvoiceLabConfig.validationVersion'),
    );
    expect(evidence, contains("'apiKeyIncluded': false"));
    expect(evidence, contains("'automaticUploadPerformed': false"));
    expect(evidence, contains("'productionDatabaseWritePerformed': false"));
    expect(evidence, isNot(contains('x-goog-api-key')));
    expect(evidence, isNot(contains('TransactionRepository')));
  });
}
