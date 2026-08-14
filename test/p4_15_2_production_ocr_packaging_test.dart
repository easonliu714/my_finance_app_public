import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production OCR bundles Chinese model and enables local adapter', () {
    final appPubspec = File('pubspec.yaml').readAsStringSync();
    final pluginPubspec = File(
      'packages/local_chinese_text_model/pubspec.yaml',
    ).readAsStringSync();
    final modelGradle = File(
      'packages/local_chinese_text_model/android/build.gradle',
    ).readAsStringSync();
    final capturePage = File(
      'lib/features/invoice/invoice_capture_page.dart',
    ).readAsStringSync();

    expect(appPubspec, contains('local_chinese_text_model:'));
    expect(
      appPubspec,
      contains('path: packages/local_chinese_text_model'),
    );
    expect(pluginPubspec, contains('LocalChineseTextModelPlugin'));
    expect(
      modelGradle,
      contains('com.google.mlkit:text-recognition-chinese:16.0.1'),
    );
    expect(
      capturePage,
      contains('GoogleMlKitTraditionalInvoiceRecognizer()'),
    );
    expect(capturePage, isNot(contains('OCR 尚未啟用')));
  });
}
