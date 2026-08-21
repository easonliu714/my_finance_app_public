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

    expect(settings, contains("'schemaVersion': 4"));
    expect(settings, contains('effectiveApiKeys'));
    expect(settings, contains('parseApiKeys'));
    expect(settings, contains('alias: _generatedKeyAlias(index)'));
    expect(card, contains('OCR 信心不足時自動 AI 辨識'));
    expect(card, contains('Key／模型不可用時允許有限次自動切換'));
    expect(card, contains('Gemini API Keys'));
    expect(card, contains('測試 API Keys 並讀取可用模型'));
    expect(card, isNot(contains('新增獨立 Project / Key Group')));
    expect(card, isNot(contains('獨立 Google Project / quota boundary')));
    expect(card, contains('obscureText: _obscureKeys'));
    expect(card, contains('_persistImmediate'));
    expect(coordinator, contains('automatic && !settings.autoReviewLowConfidenceEnabled'));
    expect(coordinator, contains('keyGroupRouterFactory(settings.apiKeys)'));
    expect(coordinator, contains('maxPhysicalAttempts = 8'));
    expect(coordinator, contains('logicalInvocationIdFactory'));
    expect(coordinator, contains('physicalAttemptCount'));
    expect(coordinator, contains('bytes: await file.readAsBytes()'));
    expect(coordinator, contains('imageBytes: image.bytes'));
    expect(frozen, contains('reviewAutomatically'));
    expect(frozen, contains('RecognitionAiRunningStatusIndicator'));
    expect(frozen, contains('_geminiElapsedTimer'));
    expect(frozen, contains("label: Text(ai == null ? 'AI 覆核' : '重新 AI 覆核')"));
    expect(frozen, contains('我已核對本機與 AI 結果'));
    expect(evidence, contains('automaticUploadPerformed'));
    expect(evidence, contains('gemini_invocation_mode='));
    expect(evidence, contains('gemini_request_count='));
    expect(evidence, contains('logical_invocation_id='));
    expect(evidence, contains('physical_attempt_count='));
    expect(evidence, contains('key_group_attempt_count='));
  });
}
