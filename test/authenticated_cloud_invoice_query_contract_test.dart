import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query orchestrator has no WebView or page-selector dependency', () {
    final source = File(
      'lib/features/invoice/lab/authenticated_cloud_invoice_query_orchestrator.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('WebViewController')));
    expect(source, isNot(contains('runJavaScript')));
    expect(source, isNot(contains('querySelector')));
    expect(source, isNot(contains('innerHTML')));
    expect(source, isNot(contains('outerHTML')));
    expect(source, isNot(contains('document.cookie')));
  });

  test('query orchestrator has no credential or CAPTCHA behavior', () {
    final source = File(
      'lib/features/invoice/lab/authenticated_cloud_invoice_query_orchestrator.dart',
    ).readAsStringSync().toLowerCase();

    expect(source, isNot(contains('password')));
    expect(source, isNot(contains('authorization')));
    expect(source, isNot(contains('captcha')));
    expect(source, isNot(contains('verificationcode')));
    expect(source, isNot(contains('autologin')));
  });

  test('query orchestrator cannot read or modify financial records', () {
    final source = File(
      'lib/features/invoice/lab/authenticated_cloud_invoice_query_orchestrator.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('AccountRepository')));
    expect(source, isNot(contains('CloudInvoiceStagingAdapter')));
    expect(source, isNot(contains('CloudInvoiceCandidate')));
    expect(source, isNot(contains('insert(')));
    expect(source, isNot(contains('update(')));
    expect(source, isNot(contains('delete(')));
  });

  test('production router does not expose LAB.3B', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('AuthenticatedCloudInvoiceQueryPlanner')));
    expect(router, isNot(contains('authenticated-cloud-invoice-query')));
    expect(router, isNot(contains('p4-lab-3b')));
  });
}
