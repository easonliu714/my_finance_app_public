import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('My page exposes secure Gemini settings without formal writes', () {
    final center = File('lib/features/backup/backup_migration_center.dart').readAsStringSync();
    final settings = File('lib/features/invoice/gemini/gemini_invoice_settings.dart').readAsStringSync();
    final repository = File('lib/features/invoice/gemini/gemini_invoice_settings_repository.dart').readAsStringSync();
    final card = File('lib/features/invoice/gemini/gemini_invoice_settings_card.dart').readAsStringSync();
    final catalog = File('lib/features/invoice/gemini/gemini_model_catalog_client.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(center, contains('GeminiInvoiceSettingsCard'));
    expect(settings, contains("defaultModel = 'gemini-3.6-flash'"));
    expect(repository, contains('FlutterSecureStorage'));
    expect(repository, contains('encryptedSharedPreferences: true'));
    expect(card, contains('obscureText: _obscureKeys'));
    expect(card, contains('測試 Key 並讀取可用模型'));
    expect(catalog, contains('/v1beta/models?pageSize=1000'));
    expect(catalog, contains("'x-goog-api-key': key"));
    expect(pubspec, contains('version: 4.18.5+432'));
    expect(repository, isNot(contains('TransactionRepository')));
  });

  test('production capture entry exposes only Live and image import', () {
    final entry = File('lib/features/invoice/invoice_capture_entry_page.dart').readAsStringSync();
    final image = File('lib/features/invoice/invoice_image_import_page.dart').readAsStringSync();
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(entry, contains('Live 即時辨識'));
    expect(entry, contains('從圖片讀取'));
    expect(entry, isNot(contains('拍照／相簿辨識')));
    expect(entry, isNot(contains('Gemini 獨立驗證')));
    expect(image, contains('ImageSource.gallery'));
    expect(image, isNot(contains('ImageSource.camera'));
    expect(router, contains('InvoiceImageImportPage.routeName'));
    expect(router, contains("name: 'invoice-capture-still'"));
    expect(router, contains('AdaptiveInvoiceLiveCapturePage'));
  });

  test('Local-first review auto-escalates weak evidence and keeps force Gemini', () {
    final coordinator = File('lib/features/invoice/gemini/gemini_invoice_review_coordinator.dart').readAsStringSync();
    final frozen = File('lib/features/invoice/invoice_frozen_review_page.dart').readAsStringSync();

    expect(coordinator, contains("if (candidate.sellerTaxId.isEmpty) '賣方統編'"));
    expect(coordinator, contains('TraditionalInvoiceOcrField.sellerTaxId'));
    expect(coordinator, contains('qrReviewCandidate'));
    expect(coordinator, contains('InvoiceLocalCompletenessPolicy().evaluate'));
    expect(coordinator, contains('shouldReview: completeness.requiresGeminiReview'));
    expect(
      frozen,
      contains('forceReview: _geminiDecision?.shouldReview != true'),
    );
    expect(frozen, contains('送出至 Gemini 必要覆核'));
    expect(frozen, contains('強制 Gemini 二次覆核'));
    expect(frozen, contains('只有你明確按下按鈕才會送出目前發票影像'));
    expect(frozen, contains('AI 不會覆寫 Local'));
    expect(frozen, isNot(contains('TransactionRepository')));
  });

  test('Gemini structured review includes random code and remains review-only', () {
    final client = File('lib/features/invoice/gemini/gemini_invoice_review_client.dart').readAsStringSync();
    final candidate = File('lib/features/invoice/gemini/gemini_invoice_review.dart').readAsStringSync();

    expect(client, contains("'responseMimeType': 'application/json'"));
    expect(client, contains("'responseJsonSchema': _responseSchema"));
    expect(client, contains("'randomCode': <String, Object?>"));
    expect(client, contains('randomCode 只有在影像明確出現「隨機碼」標籤'));
    expect(client, contains('不得把任意 NO./No. 號碼直接當成統編'));
    expect(client, contains('「現／收現／現金」屬付款投入證據'));
    expect(candidate, contains('AI 隨機碼不是完整 4 碼'));
    expect(candidate, contains('AI 統一編號校驗未通過，已保持空白。'));
    expect(candidate, contains('requiresUserReview => true'));
    expect(candidate, contains('canCreateFormalRecord => false'));
  });

  test('4.16.16 readiness baseline remains classification-independent and QR-optional', () {
    final live = File('lib/features/invoice/invoice_live_capture_stabilized_page.dart').readAsStringSync();
    final readiness = File('lib/features/invoice/invoice_live_field_readiness.dart').readAsStringSync();

    expect(live, contains('resolveTraditionalLiveIdentityConsensus'));
    expect(live, contains('resolveInvoiceLiveFieldReadiness'));
    expect(live, contains('final canFreeze = readiness.canFreeze'));
    expect(live, contains('classificationAdvisoryOnly'));
    expect(live, contains('左 QR（選填加強）'));
    expect(live, isNot(contains('electronicQrMatches')));
    expect(readiness, contains('consensus.canFreeze && stable >= 2'));
    expect(readiness, isNot(contains('InvoiceLiveClassification'));
    expect(readiness, isNot(contains('hasValidLeftQr')));
  });

  test('4.16.16 preserves Camera 3A and Frozen invoice identity boundary', () {
    final live = File('lib/features/invoice/invoice_live_capture_stabilized_page.dart').readAsStringSync();
    final parser = File('lib/features/invoice/google_mlkit_traditional_invoice_recognizer.dart').readAsStringSync();
    final repair = File('lib/features/invoice/traditional_tax_id_temporal_repair.dart').readAsStringSync();

    expect(live, contains('setFocusMode(FocusMode.locked)'));
    expect(live, contains('setExposureMode(ExposureMode.locked)'));
    expect(live, contains('Duration(milliseconds: 250)'));
    expect(live, contains('IMAGE_STREAM_STOP_START'));
    expect(live, contains('TAKE_PICTURE_START'));
    expect(live, contains('FROZEN_IDENTITY_CHECK'));
    expect(live, contains('CAMERA_INITIALIZE_START'));
    expect(live, contains('CAMERA_INITIALIZE_DONE'));
    expect(live, contains('_cameraInitializing'));
    expect(live, contains('_cameraGeneration'));
    expect(live, contains("'sampleType': 'cameraTelemetry'"));
    expect(live, contains('final accepted = !auto || identityMatches'));
    expect(live, contains('resolveLiveInvoiceClassification'));
    expect(live, contains('CLASSIFICATION_ELECTRONIC_SEMANTIC_FALLBACK'));
    expect(parser, contains('hasStrongElectronicInvoiceSemanticEvidence'));
    expect(parser, contains("source: 'positional_header_8digit'"));
    expect(parser, contains('positionedLines'));

    expect(repair, contains('single_8_to_0_checksum'));
    expect(repair, contains('family.length < 2'));
    expect(repair, contains('targets.length != 1'));
    expect(repair, isNot(contains('9_to_0')));
    expect(repair, isNot(contains('http'));
    expect(repair, isNot(contains('data.gcis.nat.gov.tw'));
    expect(live, isNot(contains('TransactionRepository'));
  });

  test('4.16.16 fuses Frozen tax evidence and uses semantic total precedence', () {
    final flow = File('lib/features/invoice/invoice_field_first_review_flow.dart').readAsStringSync();
    final total = File('lib/features/invoice/invoice_total_evidence.dart').readAsStringSync();

    expect(flow, contains('_resolveLiveFrozenTemporalTaxRepair'));
    expect(flow, contains('frozenRawCandidate'));
    expect(flow, contains('currentRawCandidate: frozenRawCandidate'));
    expect(flow, contains('resolveInvoiceTotalEvidence'));
    expect(flow, contains('rawRecognition: source.rawRecognition'));
    expect(flow, isNot(contains('TransactionRepository'));
    expect(flow, isNot(contains('TaiwanBusinessRegistryService'));

    expect(total, contains("('total_label', 40)"));
    expect(total, contains("('subtotal_label', 35)"));
    expect(total, contains("('payable_label', 30)"));
    expect(total, contains("('cash_tender_label', 10)"));
    expect(total, contains("previous.startsWith('小')"));
  });

  test('4.16.16 core form fields and evidence comparison are first-class', () {
    final presenter = File('lib/features/invoice/invoice_field_first_review_form_presenter.dart').readAsStringSync();
    final form = File('lib/features/invoice/invoice_review_form_view_model.dart').readAsStringSync();
    final evidence = File('lib/features/invoice/invoice_recognition_evidence_exporter.dart').readAsStringSync();

    expect(form, contains('sellerTaxId'));
    expect(form, contains('invoicePeriod'));
    expect(form, contains('randomCode'));
    expect(presenter, contains("label: '賣方統編'"));
    expect(presenter, contains("label: '發票期別'"));
    expect(presenter, contains("label: '隨機碼'"));
    expect(presenter, contains('requiredForReview: true'));

    expect(evidence, contains('InvoiceReviewFieldKey.sellerTaxId'));
    expect(evidence, contains('InvoiceReviewFieldKey.invoicePeriod'));
    expect(evidence, contains('InvoiceReviewFieldKey.randomCode'));
    expect(evidence, contains("'randomCode': candidate.randomCode"));
    expect(evidence, isNot(contains("('invoicePeriod', '', ai.invoicePeriod")));
    expect(evidence, isNot(contains('TransactionRepository'));
  });

  test('4.16.14 registry adapter remains explicit corroboration only', () {
    final registry = File('lib/features/invoice/taiwan_business_registry_validation.dart').readAsStringSync();
    final live = File('lib/features/invoice/invoice_live_capture_stabilized_page.dart').readAsStringSync();
    final frozen = File('lib/features/invoice/invoice_frozen_review_page.dart').readAsStringSync();

    expect(registry, contains('TaiwanBusinessRegistryService'));
    expect(registry, contains('9D17AE0D-09B5-4732-A8F4-81ADED04B679'));
    expect(registry, contains('855A3C87-003A-4930-AA4B-2F4130D713DC'));
    expect(registry, contains('367EE769-4D55-4752-AD6E-29164FA8AAB2'));
    expect(registry, contains('hasValidTaiwanTaxIdChecksum'));
    expect(registry, contains('authorizesTaxIdRepair => false'));
    expect(registry, contains('authorizesFormalWrite => false'));
    expect(registry, contains('source-IP allowlisting'));
    expect(registry, isNot(contains('TransactionRepository'));
    expect(live, isNot(contains('TaiwanBusinessRegistryService'));
    expect(frozen, isNot(contains('TaiwanBusinessRegistryService'));
  });

  test('Traditional date recovery remains calendar-bounded', () {
    final parser = File('lib/features/invoice/google_mlkit_traditional_invoice_recognizer.dart').readAsStringSync();

    expect(parser, contains('_repairYearFromPeriod'));
    expect(parser, contains('_repairMonthFromCalendar'));
    expect(parser, contains('_repairDayFromCalendar'));
    expect(parser, isNot(contains('_repairMonthFromPeriod'));
    expect(parser, contains('_safeDate(year, month, value)'));
  });
}
