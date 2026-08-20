import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.19.1 keeps Live Local-first and no-formal-write safety baseline', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final router = File(
      'lib/routing/app_router.dart',
    ).readAsStringSync();
    final entry = File(
      'lib/features/invoice/invoice_capture_entry_page.dart',
    ).readAsStringSync();
    final live = File(
      'lib/features/invoice/invoice_live_capture_stabilized_page.dart',
    ).readAsStringSync();
    final adaptive = File(
      'lib/features/invoice/invoice_live_capture_adaptive_page.dart',
    ).readAsStringSync();
    final frozen = File(
      'lib/features/invoice/invoice_frozen_review_page.dart',
    ).readAsStringSync();
    final fieldFirst = File(
      'lib/features/invoice/invoice_field_first_review_flow.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/features/invoice/gemini/gemini_invoice_review_coordinator.dart',
    ).readAsStringSync();
    final client = File(
      'lib/features/invoice/gemini/gemini_invoice_review_client.dart',
    ).readAsStringSync();

    expect(pubspec, contains('version: 4.19.3+440'));
    expect(router, contains('InvoiceFrozenReviewPage.routeName'));
    expect(entry, contains('Live 即時辨識'));
    expect(entry, contains('從圖片讀取'));

    expect(live, contains('startImageStream'));
    expect(live, contains('stopImageStream'));
    expect(live, contains('takePicture()'));
    expect(live, contains('FROZEN_IDENTITY_CHECK'));
    expect(live, contains('final accepted = !auto || identityMatches'));
    expect(adaptive, contains('FROZEN_IDENTITY_CHECK'));
    expect(adaptive, contains('final accepted = !auto || identityMatches'));

    expect(frozen, contains('reviewAutomatically'));
    expect(frozen, contains('localReference: _item.localReference'));
    expect(frozen, contains('RecognitionAiStatusIndicator'));
    expect(fieldFirst, isNot(contains('TransactionRepository')));
    expect(coordinator, isNot(contains('TransactionRepository')));
    expect(client, isNot(contains('TransactionRepository')));
  });

  test('Frozen Original Image remains Local and Gemini request authority', () {
    final frozen = File(
      'lib/features/invoice/invoice_frozen_review_page.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/features/invoice/gemini/gemini_invoice_review_coordinator.dart',
    ).readAsStringSync();
    final client = File(
      'lib/features/invoice/gemini/gemini_invoice_review_client.dart',
    ).readAsStringSync();

    expect(frozen, contains('localReference: _item.localReference'));
    expect(frozen, contains('image: _item'));
    expect(coordinator, contains('bytes: await file.readAsBytes()'));
    expect(coordinator, contains('imageBytes: image.bytes'));
    expect(client, contains('base64Encode(imageBytes)'));
    expect(client, isNot(contains('copyResize')));
    expect(client, isNot(contains('cropImage')));
  });

  test('Evidence v6 preserves provenance resilience audit and key safety', () {
    final evidence = File(
      'lib/features/invoice/invoice_recognition_evidence_exporter.dart',
    ).readAsStringSync();

    expect(evidence, contains('invoice-recognition-evidence-v6'));
    expect(evidence, contains("'capture_image."));
    expect(evidence, contains("'gemini_input."));
    expect(evidence, contains("'local_ocr_raw.txt'"));
    expect(evidence, contains("'local_ocr_variant_votes.json'"));
    expect(evidence, contains("'live_snapshot_history.json'"));
    expect(evidence, contains('capture_sha256='));
    expect(evidence, contains('gemini_input_matches_capture_sha256='));
    expect(evidence, contains('gemini_invocation_mode='));
    expect(evidence, contains('logical_invocation_id='));
    expect(evidence, contains('active_model='));
    expect(evidence, contains('key_group_alias='));
    expect(evidence, contains('physical_attempt_count='));
    expect(evidence, contains('model_attempt_count='));
    expect(evidence, contains('key_group_attempt_count='));
    expect(evidence, contains('fallback_reason='));
    expect(evidence, contains("'apiKeyIncluded': false"));
    expect(evidence, contains("'productionDatabaseWritePerformed': false"));
    expect(evidence, contains("'ocrDerivativeImageBecomesAuthority': false"));
    expect(evidence, isNot(contains('x-goog-api-key')));
    expect(evidence, isNot(contains('TransactionRepository')));
  });
}
