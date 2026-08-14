import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production capture and settings pages exclude development headings', () {
    const paths = <String>[
      'lib/features/invoice/invoice_capture_page.dart',
      'lib/features/product/product_capture_page.dart',
      'lib/features/invoice/cloud_invoice_inbox_page.dart',
      'lib/features/backup/backup_migration_center.dart',
    ];
    const prohibited = <String>[
      '資料與安全邊界',
      '目前可用功能',
      '備份與換機移轉中心',
      '本機優先、人工覆核',
      '本階段不會建立任何正式財務紀錄',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      for (final phrase in prohibited) {
        expect(
          source,
          isNot(contains(phrase)),
          reason: '$path must not expose development copy: $phrase',
        );
      }
    }
  });

  test('invoice redemption disclaimer remains explicit', () {
    final source = File(
      'lib/features/invoice/invoice_capture_page.dart',
    ).readAsStringSync();

    expect(source, contains('發票紀錄僅供記帳與對獎，不能作為兌獎憑證。'));
  });
}
