import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official CSV adapter has no transaction or router dependency', () {
    final source = File(
      'lib/features/invoice/lab/official_cloud_invoice_csv_adapter.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('AccountRepository')));
    expect(source, isNot(contains('GoRouter')));
    expect(source, isNot(contains('app_router.dart')));
  });

  test('official CSV adapter returns no raw payload or credential material', () {
    final source = File(
      'lib/features/invoice/lab/official_cloud_invoice_csv_adapter.dart',
    ).readAsStringSync();

    expect(source, contains('rawPayload: null'));
    expect(source, isNot(contains('password')));
    expect(source, isNot(contains('captcha')));
    expect(source, isNot(contains('authorization')));
    expect(source, isNot(contains('document.cookie')));
    expect(source, isNot(contains('innerHTML')));
    expect(source, isNot(contains('outerHTML')));
  });

  test('public router remains independent from the official CSV lab adapter', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('OfficialCloudInvoiceCsvAdapter')));
    expect(router, isNot(contains('official-cloud-invoice-csv')));
  });
}
