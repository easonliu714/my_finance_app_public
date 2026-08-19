import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P4.19.1 resilient UI and evidence contract', () {
    test('settings expose explicit automatic low-confidence authorization', () {
      final source = File(
        'lib/features/invoice/gemini/gemini_invoice_settings_card.dart',
      ).readAsStringSync();

      expect(source, contains('OCR 信心不足時自動 AI 辨識'));
      expect(source, contains('每次只建立 1 個 AI logical invocation'));
      expect(source, contains('有限次 fallback / retry'));
      expect(source, contains('每行 1 個獨立 Project'));
    });

    test('Frozen Review no longer shows the old mandatory-upload explanation', () {
      final source = File(
        'lib/features/invoice/invoice_frozen_review_page.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('只有你明確按下按鈕才會送出目前發票影像')));
      expect(source, isNot(contains('Single Image Review')));
      expect(source, contains('AI 覆核'));
      expect(source, contains('已自動 AI 覆核'));
      expect(source, contains('RecognitionAiStatusIndicator'));
    });

    test('Evidence records resilient invocation instead of hard-coding false', () {
      final source = File(
        'lib/features/invoice/invoice_recognition_evidence_exporter.dart',
      ).readAsStringSync();

      expect(source, contains('gemini_invocation_mode='));
      expect(source, contains('gemini_request_count='));
      expect(source, contains('logical_invocation_id='));
      expect(source, contains('physical_attempt_count='));
      expect(source, contains('key_group_attempt_count='));
      expect(source, contains('fallback_reason='));
      expect(source, contains('automatic_review_setting_enabled='));
      expect(
        source,
        contains(r'automatic_upload_performed=$automaticUploadPerformed'),
      );
      expect(source, isNot(contains("'automatic_upload_performed=false'")));
      expect(source, contains("'production_database_write_performed=false'"));
    });
  });
}
