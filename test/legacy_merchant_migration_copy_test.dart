import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v13.dart';
import 'package:my_finance_app/features/merchant/legacy_merchant_migration_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('copies valid rows once and keeps legacy file unchanged', () async {
    final directory = await Directory.systemTemp.createTemp('merchant-copy-');
    addTearDown(() => directory.delete(recursive: true));
    final canonical = await openDatabase('${directory.path}/canonical.db');
    addTearDown(canonical.close);
    await createCanonicalProductionV13Tables(canonical);

    final legacyPath = '${directory.path}/merchant_master.db';
    final legacy = await openDatabase(legacyPath);
    await _createLegacySchema(legacy);
    await legacy.insert('merchants', _row(id: 'merchant-1', name: '測試商家'));
    await legacy.insert('merchants', _row(id: '', name: '缺少識別碼'));
    await legacy.close();
    final before = await File(legacyPath).stat();

    const service = LegacyMerchantMigrationService();
    final first = await service.migrate(
      canonical,
      legacyDatabasePath: legacyPath,
    );
    final second = await service.migrate(
      canonical,
      legacyDatabasePath: legacyPath,
    );
    final after = await File(legacyPath).stat();

    expect(first.sourceRows, 2);
    expect(first.copiedRows, 1);
    expect(first.skippedRows, 1);
    expect(first.alreadyCompleted, isFalse);
    expect(second.alreadyCompleted, isTrue);
    expect(await canonical.query('merchants'), hasLength(1));
    expect(
      (await canonical.query('production_migration_markers')).single['status'],
      'completed',
    );
    expect(await File(legacyPath).exists(), isTrue);
    expect(after.size, before.size);
    expect(after.modified, before.modified);
  });

  test('missing source creates completed zero-row marker', () async {
    final directory = await Directory.systemTemp.createTemp('merchant-none-');
    addTearDown(() => directory.delete(recursive: true));
    final canonical = await openDatabase('${directory.path}/canonical.db');
    addTearDown(canonical.close);

    const service = LegacyMerchantMigrationService();
    final result = await service.migrate(
      canonical,
      legacyDatabasePath: '${directory.path}/merchant_master.db',
    );

    expect(result.sourceRows, 0);
    expect(result.copiedRows, 0);
    final marker =
        (await canonical.query('production_migration_markers')).single;
    expect(marker['status'], 'completed');
    expect(marker['details'], 'legacy database not found');
  });
}

Future<void> _createLegacySchema(Database db) async {
  await db.execute('''
    CREATE TABLE merchants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      alias TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
}

Map<String, Object?> _row({required String id, required String name}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'alias': '',
    'note': '',
    'is_archived': 0,
    'created_at': '2026-05-01T01:02:03.000Z',
    'updated_at': '2026-05-02T04:05:06.000Z',
  };
}
