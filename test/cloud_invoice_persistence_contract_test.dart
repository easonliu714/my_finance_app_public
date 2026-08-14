import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LAB.6 core has no production repository or database dependency', () {
    final source = _combinedSource();

    expect(source, isNot(contains('TransactionRepository')));
    expect(source, isNot(contains('AccountRepository')));
    expect(source, isNot(contains('MerchantRepository')));
    expect(source, isNot(contains('ProductionDatabaseCoordinator')));
    expect(source, isNot(contains('sqflite')));
    expect(source, isNot(contains('Database')));
  });

  test('LAB.6 core has no UI, provider, WebView, or network dependency', () {
    final source = _combinedSource();

    expect(source, isNot(contains('BuildContext')));
    expect(source, isNot(contains('Navigator')));
    expect(source, isNot(contains('Provider')));
    expect(source, isNot(contains('WebViewController')));
    expect(source, isNot(contains("import 'package:http/")));
    expect(source, isNot(contains("import 'package:dio/")));
  });

  test('drafts remain non-formal and replacement requires safeguards', () {
    final models = File(
      'lib/features/invoice/lab/cloud_invoice_persistence_models.dart',
    ).readAsStringSync();
    final executor = File(
      'lib/features/invoice/lab/cloud_invoice_persistence_executor.dart',
    ).readAsStringSync();

    expect(models, contains('isFormalTransaction => false'));
    expect(executor, contains('replacementSecondConfirmationCompleted'));
    expect(executor, contains('saveBeforeImage'));
    expect(executor, contains('restoreTransaction'));
    expect(executor, contains('transactionFingerprint'));
    expect(executor, contains('accountFingerprint'));
  });

  test('ports expose explicit compensation operations', () {
    final ports = File(
      'lib/features/invoice/lab/cloud_invoice_persistence_ports.dart',
    ).readAsStringSync();

    expect(ports, contains('removeDraft'));
    expect(ports, contains('removeLinksForOperation'));
    expect(ports, contains('compensateCreatedMerchant'));
    expect(ports, contains('hasExternalReferences'));
  });

  test('production router remains independent from LAB.6', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();

    expect(router, isNot(contains('CloudInvoicePersistenceExecutor')));
    expect(router, isNot(contains('cloud-invoice-persistence')));
    expect(router, isNot(contains('p4-lab-6')));
  });
}

String _combinedSource() {
  return <String>[
    File(
      'lib/features/invoice/lab/cloud_invoice_persistence_models.dart',
    ).readAsStringSync(),
    File(
      'lib/features/invoice/lab/cloud_invoice_persistence_ports.dart',
    ).readAsStringSync(),
    File(
      'lib/features/invoice/lab/cloud_invoice_persistence_executor.dart',
    ).readAsStringSync(),
  ].join('\n');
}
