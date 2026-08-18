import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P4.19.0 compact UI and evidence contract', () {
    test('settings expose explicit automatic low-confidence authorization', () {
      final source = File(
        'lib/features/invoice/gemini/gemini_invoice_settings_card.dart',
      ).readAsStringSync();

      expect(source, contains('OCR 信心不足時自動 AI 辨識'));
      expect(source, contains('僅在本機判定需要覆核時自動送出原始發票影像一次'));
    });

    test('Frozen Review no longer shows the old mandatory-upload explanation', () {
      final source = File(
        'lib/features/invoice/invoice_frozen_review_page.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('只有你明確按下按鈕才會送出目前發票影像')));
      expect(source, isNot(contains('Single Image Review')));
      expect(source, contains('AI 覆核'));
      expect(source, contains('已自動 AI 覆核'));
    });

    test('Evidence records automatic invocation instead of hard-coding false', () {
      final source = File(
        'lib/features/invoice/invoice_recognition_evidence_exporter.dart',
      ).readAsStringSync();

      expect(source, contains('gemini_invocation_mode='));
      expect(source, contains('gemini_request_count='));
      expect(source, contains('automatic_review_setting_enabled='));
      expect(source, contains('automatic_upload_performed=$automaticUploadPerformed'));
      expect(source, isNot(contains("'automatic_upload_performed=false'")));
      expect(source, contains("'production_database_write_performed=false'"));
    });
  });
}
