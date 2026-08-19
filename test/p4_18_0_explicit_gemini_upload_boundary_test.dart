import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P4.19.1 preserves standing authorization with bounded resilient review', () {
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
    expect(settings, contains('effectiveKeyGroups'));
    expect(settings, contains('legacyGroupAlias'));
    expect(card, contains('OCR 信心不足時自動 AI 辨識'));
    expect(card, contains('每次只建立 1 個 AI logical invocation'));
    expect(card, contains('每行 1 個獨立 Project'));
    expect(coordinator, contains('automatic && !settings.autoReviewLowConfidenceEnabled'));
    expect(coordinator, contains('settings.effectiveKeyGroups'));
    expect(coordinator, contains('GeminiKeyGroupRouter.fromGroups'));
    expect(coordinator, contains('maxPhysicalAttempts = 3'));
    expect(coordinator, contains('logicalInvocationIdFactory'));
    expect(coordinator, contains('physicalAttemptCount'));
    expect(coordinator, contains('bytes: await file.readAsBytes()'));
    expect(coordinator, contains('imageBytes: image.bytes'));
    expect(frozen, contains('reviewAutomatically'));
    expect(frozen, contains("label: Text(ai == null ? 'AI 覆核' : '重新 AI 覆核')"));
    expect(frozen, contains('我已核對本機與 AI 結果'));
    expect(evidence, contains('automaticUploadPerformed'));
    expect(evidence, contains('gemini_invocation_mode='));
    expect(evidence, contains('gemini_request_count='));
    expect(evidence, contains('logical_invocation_id='));
    expect(evidence, contains('physical_attempt_count='));
  });
}
