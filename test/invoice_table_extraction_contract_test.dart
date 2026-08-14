import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adapter has no router or transaction repository dependency', () {
    final source = File(
      'lib/features/invoice/lab/invoice_table_extraction_adapter.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('AccountRepository')));
    expect(source, isNot(contains('app_router.dart')));
    expect(source, isNot(contains('GoRouter')));
  });

  test('adapter cannot retain raw page or credential material', () {
    final source = File(
      'lib/features/invoice/lab/invoice_table_extraction_adapter.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('rawHtml')));
    expect(source, isNot(contains('outerHTML')));
    expect(source, isNot(contains('innerHTML')));
    expect(source, isNot(contains('document.cookie')));
    expect(source, isNot(contains('authorization')));
    expect(source, isNot(contains('password')));
    expect(source, isNot(contains('captcha')));
    expect(source, contains('rawPayload: null'));
  });

  test('production router still does not expose the lab feature', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('InvoiceTableExtractionAdapter')));
    expect(router, isNot(contains('invoice-table-extraction')));
    expect(router, isNot(contains('p4-lab-3')));
  });
}
