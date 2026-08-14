import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconciliation core has no WebView or network dependency', () {
    final source = _combinedSource();

    expect(source, isNot(contains('WebViewController')));
    expect(source, isNot(contains('runJavaScript')));
    expect(source, isNot(contains('querySelector')));
    expect(source, isNot(contains('http.')));
    expect(source, isNot(contains('dio')));
  });

  test('reconciliation core has no repository or database write dependency', () {
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

  test('models prohibit automatic formal writes and replacement', () {
    final models = File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_models.dart',
    ).readAsStringSync();

    expect(models, contains('canWriteFormalTransactionAutomatically => false'));
    expect(models, contains('canReplaceAutomatically => false'));
    expect(models, contains('canPersistAutomatically => false'));
    expect(models, contains('canCreateFormalTransaction => false'));
  });

  test('production router remains independent from LAB.4', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('CloudInvoiceReconciliationEngine')));
    expect(router, isNot(contains('cloud-invoice-reconciliation')));
    expect(router, isNot(contains('p4-lab-4')));
  });
}

String _combinedSource() {
  return <String>[
    File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_models.dart',
    ).readAsStringSync(),
    File(
      'lib/features/invoice/lab/cloud_invoice_reconciliation_engine.dart',
    ).readAsStringSync(),
  ].join('\n');
}
