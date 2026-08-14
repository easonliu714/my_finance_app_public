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

  test('unsupported source schema fails closed', () async {
    final dir = await Directory.systemTemp.createTemp('merchant-guard-');
    addTearDown(() => dir.delete(recursive: true));
    final canonical = await openDatabase('${dir.path}/canonical.db');
    addTearDown(canonical.close);
    await createCanonicalProductionV13Tables(canonical);

    final legacyPath = '${dir.path}/merchant_master.db';
    final legacy = await openDatabase(legacyPath);
    await legacy.execute('CREATE TABLE merchants (id TEXT, name TEXT)');
    await legacy.close();
    final before = await File(legacyPath).stat();

    const service = LegacyMerchantMigrationService();
    await expectLater(
      service.migrate(canonical, legacyDatabasePath: legacyPath),
      throwsA(isA<StateError>()),
    );

    expect(await canonical.query('production_migration_markers'), isEmpty);
    expect(await canonical.query('merchants'), isEmpty);
    final after = await File(legacyPath).stat();
    expect(after.size, before.size);
    expect(after.modified, before.modified);
  });

  test('existing canonical row is preserved on ID conflict', () async {
    final dir = await Directory.systemTemp.createTemp('merchant-conflict-');
    addTearDown(() => dir.delete(recursive: true));
    final canonical = await openDatabase('${dir.path}/canonical.db');
    addTearDown(canonical.close);
    await createCanonicalProductionV13Tables(canonical);
    await canonical.insert('merchants', _merchant('Canonical', 'canonical'));

    final legacyPath = '${dir.path}/merchant_master.db';
    final legacy = await openDatabase(legacyPath);
    await _createLegacySchema(legacy);
    await legacy.insert('merchants', _merchant('Legacy', 'legacy'));
    await legacy.close();

    const service = LegacyMerchantMigrationService();
    final report = await service.migrate(
      canonical,
      legacyDatabasePath: legacyPath,
    );

    final row = (await canonical.query('merchants')).single;
    final marker =
        (await canonical.query('production_migration_markers')).single;
    expect(report.copiedRows, 0);
    expect(report.skippedRows, 1);
    expect(row['name'], 'Canonical');
    expect(row['note'], 'canonical');
    expect(marker['details'], contains('canonical conflicts preserved'));
  });
}

Future<void> _createLegacySchema(Database db) async {
  await db.execute('''
    CREATE TABLE merchants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      alias TEXT NOT NULL,
      note TEXT NOT NULL,
      is_archived INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
}

Map<String, Object?> _merchant(String name, String note) => <String, Object?>{
      'id': 'merchant-1',
      'name': name,
      'alias': '',
      'note': note,
      'is_archived': 0,
      'created_at': '2026-05-01T00:00:00.000Z',
      'updated_at': '2026-05-02T00:00:00.000Z',
    };
