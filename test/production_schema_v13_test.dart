import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v13.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('creates all canonical v13 tables and indexes idempotently', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await createCanonicalProductionV13Tables(db);
    await createCanonicalProductionV13Tables(db);

    expect(
      await _tableNames(db),
      containsAll(<String>{
        'merchants',
        'production_migration_markers',
        'cloud_invoice_drafts',
        'cloud_invoice_metadata_links',
        'cloud_invoice_operations',
        'cloud_invoice_before_images',
        'cloud_invoice_audits',
      }),
    );
    expect(
      await _indexNames(db),
      containsAll(<String>{
        'idx_merchants_name_alias_unique',
        'idx_merchants_visible_sort',
        'idx_production_migration_markers_status',
        'idx_cloud_invoice_drafts_candidate',
        'idx_cloud_invoice_drafts_account',
        'idx_cloud_invoice_metadata_transaction',
        'idx_cloud_invoice_metadata_candidate',
        'idx_cloud_invoice_operations_status',
        'idx_cloud_invoice_operations_candidate',
        'idx_cloud_invoice_operations_transaction',
        'idx_cloud_invoice_before_images_created',
        'idx_cloud_invoice_audits_operation',
        'idx_cloud_invoice_audits_candidate',
        'idx_cloud_invoice_audits_status',
      }),
    );
  });

  test('draft schema preserves unknown currency and tax as null', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV13Tables(db);

    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'draft-1',
      'operation_key': 'operation-1',
      'candidate_reference': 'candidate-1',
      'account_id': 'account-1',
      'account_name': '現金',
      'amount': 100,
      'invoice_date': '2026-06-18T00:00:00.000',
      'time_precision': 'dateOnly',
      'time_source': 'unknown',
      'currency_code': null,
      'merchant_id': null,
      'invoice_number': 'AB12345678',
      'seller_identifier': '12345678',
      'seller_name': '測試商家',
      'tax_amount': null,
      'line_items_json': '[]',
      'payload_version': 1,
      'created_at': '2026-06-18T12:00:00.000Z',
    });

    final row = (await db.query('cloud_invoice_drafts')).single;
    expect(row['currency_code'], isNull);
    expect(row['tax_amount'], isNull);
    expect(row['time_precision'], 'dateOnly');
  });

  test('operation, draft, link and rollback identities are unique', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV13Tables(db);

    await _insertOperation(db, operationKey: 'op-1');
    expect(
      () => _insertOperation(db, operationKey: 'op-1'),
      throwsA(isA<DatabaseException>()),
    );

    await db.insert('cloud_invoice_before_images', <String, Object?>{
      'rollback_token': 'rollback-1',
      'operation_key': 'op-1',
      'transaction_fingerprint': 'fingerprint',
      'transaction_json': '{}',
      'payload_version': 1,
      'created_at': '2026-06-18T12:00:00.000Z',
    });
    expect(
      () => db.insert('cloud_invoice_before_images', <String, Object?>{
        'rollback_token': 'rollback-1',
        'operation_key': 'op-2',
        'transaction_fingerprint': 'fingerprint-2',
        'transaction_json': '{}',
        'payload_version': 1,
        'created_at': '2026-06-18T12:01:00.000Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<Set<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<void> _insertOperation(
  Database db, {
  required String operationKey,
}) async {
  await db.insert('cloud_invoice_operations', <String, Object?>{
    'operation_key': operationKey,
    'request_fingerprint': 'fingerprint-$operationKey',
    'action': 'keepSeparate',
    'status': 'committed',
    'candidate_reference': 'candidate-$operationKey',
    'created_at': '2026-06-18T12:00:00.000Z',
    'updated_at': '2026-06-18T12:00:00.000Z',
  });
}
