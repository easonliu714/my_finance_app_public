import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.19 preserves explicit standing authorization and manual review', () {
    final frozen = File(
      'lib/features/invoice/invoice_frozen_review_page.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/invoice/gemini/gemini_invoice_settings.dart',
    ).readAsStringSync();
    final card = File(
      'lib/features/invoice/gemini/gemini_invoice_settings_card.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/features/invoice/gemini/gemini_invoice_review_coordinator.dart',
    ).readAsStringSync();
    final evidence = File(
      'lib/features/invoice/invoice_recognition_evidence_exporter.dart',
    ).readAsStringSync();

    expect(settings, contains('this.autoReviewLowConfidenceEnabled = false'));
    expect(card, contains('OCR 信心不足時自動 AI 辨識'));
    expect(card, contains('僅在本機判定需要覆核時自動送出原始發票影像一次'));
    expect(coordinator, contains('automatic && !settings.autoReviewLowConfidenceEnabled'));
    expect(coordinator, contains('final keyCount = automatic ? 1 : settings.apiKeys.length'));
    expect(coordinator, contains('bytes: await file.readAsBytes()'));
    expect(frozen, contains('reviewAutomatically'));
    expect(frozen, contains("label: Text(ai == null ? 'AI 覆核' : '重新 AI 覆核')"));
    expect(frozen, contains('我已核對本機與 AI 結果'));
    expect(evidence, contains('automaticUploadPerformed'));
    expect(evidence, contains('gemini_invocation_mode='));
    expect(evidence, contains('gemini_request_count='));
  });
}
