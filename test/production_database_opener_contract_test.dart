import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_database_coordinator.dart';

void main() {
  test('canonical production database contract is v22', () {
    expect(ProductionDatabaseCoordinator.databaseName, 'my_finance_app.db');
    expect(ProductionDatabaseCoordinator.schemaVersion, 22);

    final source = File(
      'lib/features/account/account_repository.dart',
    ).readAsStringSync();
    expect(source, contains('canonicalProductionSchemaVersion'));
    expect(source, contains('createCanonicalProductionV20Tables'));
    expect(source, contains('createCanonicalProductionV21Tables'));
    expect(source, contains('createCanonicalProductionV22Tables'));
    expect(source, contains('if (oldVersion < 20)'));
    expect(source, contains('if (oldVersion < 21)'));
    expect(source, contains('if (oldVersion < 22)'));
  });

  test('transaction repository has no competing direct opener', () {
    final source = File(
      'lib/features/transaction/transaction_repository.dart',
    ).readAsStringSync();
    expect(source, contains('ProductionDatabaseCoordinator'));
    expect(source, isNot(contains('openDatabase(')));
    expect(source, isNot(contains('getApplicationDocumentsDirectory')));
  });

  test('automatic top-up adapter owns active transaction write surfaces', () {
    final provider = File(
      'lib/features/transaction/transaction_providers.dart',
    ).readAsStringSync();
    final manualInvoice = File(
      'lib/features/invoice/manual_invoice_entry_page.dart',
    ).readAsStringSync();
    final adapter = File(
      'lib/features/transaction/auto_top_up_transaction_store.dart',
    ).readAsStringSync();

    expect(provider, contains('AutoTopUpTransactionStore.instance'));
    expect(manualInvoice, contains('AutoTopUpTransactionStore.instance'));
    expect(adapter, contains('StoredValueAutoTopUpService'));
    expect(adapter, contains('WalletTopUpExecutionMutationBlocked'));
  });

  test('canonical merchant repository has no competing direct opener', () {
    final source = File(
      'lib/features/merchant/canonical_merchant_repository.dart',
    ).readAsStringSync();
    expect(source, contains('ProductionDatabaseCoordinator'));
    expect(source, contains('LegacyMerchantMigrationService'));
    expect(source, isNot(contains('openDatabase(')));
    expect(source, isNot(contains('merchant_master.db')));
  });

  test('legacy database singletons remain quarantined', () {
    final references = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('/database/app_database.dart') ||
          path.endsWith('/core/db_helper.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (source.contains('AppDatabase.instance') ||
          source.contains('DBHelper.instance')) {
        references.add(path);
      }
    }
    expect(references, isEmpty);
  });
}
