import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P4.19.1 resilient UI and evidence contract', () {
    test('settings expose automatic low-confidence flat-key authorization', () {
      final source = File(
        'lib/features/invoice/gemini/gemini_invoice_settings_card.dart',
      ).readAsStringSync();

      expect(source, contains('OCR 信心不足時自動 AI 辨識'));
      expect(source, contains('Key／模型不可用時允許有限次自動切換'));
      expect(source, contains('Gemini API Keys'));
      expect(source, contains('測試 API Keys 並讀取可用模型'));
      expect(source, isNot(contains('新增獨立 Project / Key Group')));
      expect(source, contains('obscureText: _obscureKeys'));
      expect(source, contains('_persistImmediate'));
    });

    test('Frozen Review shows running and completed resilient AI status', () {
      final source = File(
        'lib/features/invoice/invoice_frozen_review_page.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('只有你明確按下按鈕才會送出目前發票影像')));
      expect(source, isNot(contains('Single Image Review')));
      expect(source, contains('AI 覆核'));
      expect(source, contains('已自動 AI 覆核'));
      expect(source, contains('RecognitionAiRunningStatusIndicator'));
      expect(source, contains('RecognitionAiStatusIndicator'));
      expect(source, contains('_geminiElapsedTimer'));
      expect(source, contains('_geminiActiveModel'));
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
