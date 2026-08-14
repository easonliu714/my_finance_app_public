import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LAB.5 review layer has no WebView or network dependency', () {
    final source = _combinedSource();

    expect(source, isNot(contains('WebViewController')));
    expect(source, isNot(contains('runJavaScript')));
    expect(source, isNot(contains('querySelector')));
    expect(source, isNot(contains("import 'package:http/")));
    expect(source, isNot(contains("import 'package:dio/")));
  });

  test('LAB.5 review layer has no repository or database dependency', () {
    final source = _combinedSource();

    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('AccountRepository')));
    expect(source, isNot(contains('MerchantRepository')));
    expect(source, isNot(contains('sqflite')));
    expect(source, isNot(contains('Database')));
    expect(source, isNot(contains('.insert(')));
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('.delete(')));
  });

  test('review decision keeps every automatic write flag false', () {
    final source = File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_review_decision.dart',
    ).readAsStringSync();

    expect(source, contains('canWriteFormalTransactionAutomatically => false'));
    expect(source, contains('canPersistMerchantAutomatically => false'));
    expect(source, contains('canPersistAccountAutomatically => false'));
    expect(source, contains('canReplaceAutomatically => false'));
  });

  test('review page uses a scrollable single-column body', () {
    final source = File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_review_page.dart',
    ).readAsStringSync();

    expect(source, contains('ListView('));
    expect(source, isNot(contains('SingleChildScrollView')));
  });

  test('production router remains independent from LAB.5', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('CloudInvoiceReconciliationReviewPage')));
    expect(router, isNot(contains('reconciliation-review')));
    expect(router, isNot(contains('p4-lab-5')));
  });
}

String _combinedSource() {
  return <String>[
    File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_review_decision.dart',
    ).readAsStringSync(),
    File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_review_page.dart',
    ).readAsStringSync(),
  ].join('\n');
}
