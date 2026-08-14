import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart' as v15;
import 'package:my_finance_app/database/production_schema_v16.dart' as v16;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v15 database upgrades to v16 without losing existing drafts', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await v15.createCanonicalProductionV15Tables(db);
    await db.insert('cloud_invoice_drafts', _draftRow(
      id: 'draft-existing',
      accountId: 'account-1',
      accountName: '現金',
    ));

    await v16.createCanonicalProductionV16Tables(db);
    await v16.createCanonicalProductionV16Tables(db);

    final columns = await db.rawQuery('PRAGMA table_info(cloud_invoice_drafts)');
    expect(
      columns.map((row) => row['name']),
      contains('account_resolution_status'),
    );

    final existing = (await db.query(
      'cloud_invoice_drafts',
      where: 'id = ?',
      whereArgs: const <Object?>['draft-existing'],
    )).single;
    expect(existing['account_id'], 'account-1');
    expect(existing['account_name'], '現金');
    expect(existing['account_resolution_status'], 'selected');

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    expect(
      indexes.map((row) => row['name']),
      contains('idx_cloud_invoice_drafts_account_resolution'),
    );
    expect(v16.canonicalProductionSchemaVersion, 16);
  });

  test('v16 accepts an unresolved draft without a placeholder account', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await v16.createCanonicalProductionV16Tables(db);
    await db.insert('cloud_invoice_drafts', _draftRow(
      id: 'draft-unresolved',
      accountId: '',
      accountName: '',
      accountResolutionStatus: 'unresolved',
    ));

    final row = (await db.query(
      'cloud_invoice_drafts',
      where: 'id = ?',
      whereArgs: const <Object?>['draft-unresolved'],
    )).single;
    expect(row['account_id'], isEmpty);
    expect(row['account_name'], isEmpty);
    expect(row['account_resolution_status'], 'unresolved');
  });
}

Map<String, Object?> _draftRow({
  required String id,
  required String accountId,
  required String accountName,
  String? accountResolutionStatus,
}) {
  return <String, Object?>{
    'id': id,
    'operation_key': 'operation-$id',
    'candidate_reference': 'candidate-$id',
    'account_id': accountId,
    'account_name': accountName,
    if (accountResolutionStatus != null)
      'account_resolution_status': accountResolutionStatus,
    'amount': 100,
    'invoice_date': '2026-06-27T00:00:00.000',
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
    'created_at': '2026-06-27T00:00:00.000Z',
  };
}
