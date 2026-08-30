import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service_v8.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('canonical V22 migration rollback leaves legacy merchant data intact', () async {
    final db = await _openLegacyFixture();
    addTearDown(db.close);

    await expectLater(
      db.transaction((txn) async {
        await createCanonicalProductionV22Tables(
          txn,
          stageHook: (stage) async {
            if (stage ==
                ProductionSchemaV22MigrationStage.afterMerchantIdentityTables) {
              throw StateError('synthetic migration interruption');
            }
          },
        );
      }),
      throwsStateError,
    );

    expect(await _tableExists(db, 'merchant_brands'), isFalse);
    final legacy = await db.query('merchants');
    expect(legacy, hasLength(1));
    expect(legacy.single['id'], 'merchant-legacy');
    expect(legacy.single['name'], '測試商家');
    expect(legacy.single['seller_identifier'], '30340553');
  });

  test('canonical V22 migration preserves merchant id and explicit seller binding', () async {
    final db = await _openLegacyFixture();
    addTearDown(db.close);

    await createCanonicalProductionV22Tables(db);

    expect(canonicalProductionSchemaVersion, 22);
    final brand = await db.query(
      'merchant_brands',
      where: 'id = ?',
      whereArgs: <Object?>['merchant-legacy'],
    );
    expect(brand.single['display_name'], '測試商家');

    final legal = await db.query(
      'merchant_legal_entities',
      where: 'seller_identifier = ?',
      whereArgs: <Object?>['30340553'],
    );
    expect(legal, hasLength(1));

    final links = await db.query(
      'merchant_brand_legal_links',
      where: 'merchant_brand_id = ? AND decision = ?',
      whereArgs: <Object?>['merchant-legacy', 'confirmed'],
    );
    expect(links, hasLength(1));
    expect(links.single['evidence_source'], 'p4_19_11_explicit_binding');
  });

  test('backup scope V8 includes user identity but excludes replaceable registry cache', () async {
    final db = await _openV22Fixture();
    addTearDown(db.close);
    await _installRegistryCanary(db, version: 'registry-source-only');

    final coverage = await FullBackupScope.inspect(db);
    expect(coverage.isComplete, isTrue);
    expect(
      FullBackupScope.backupTableNames,
      containsAll(FullBackupScope.merchantIdentityUserTableNames),
    );
    expect(
      coverage.excludedPresentTables,
      containsAll(<String>[
        'business_registry_snapshots',
        'business_registry_entities',
        'business_registry_negative_lookups',
      ]),
    );

    final envelope = await const FullBackupService().buildFullBackupEnvelope(
      db,
      createdAt: DateTime.utc(2026, 8, 30, 12),
      sourcePlatform: 'test',
    );
    final metadata = envelope['metadata']! as Map<String, Object?>;
    final data = envelope['data']! as Map<String, Object?>;
    expect(metadata['backup_scope_version'], 8);
    expect(metadata['database_schema_version'], 22);
    expect(data['merchant_brands'], isA<List>());
    expect(data['merchant_identity_observations'], isA<List>());
    expect(data.containsKey('business_registry_snapshots'), isFalse);
    expect(data.containsKey('business_registry_entities'), isFalse);
  });

  test('V22 full backup restore preserves identity graph and leaves registry cache independent', () async {
    final source = await _openV22Fixture();
    final target = await _openV22Fixture(
      merchantId: 'target-only',
      merchantName: '目標暫存商家',
      sellerIdentifier: '12345675',
    );
    addTearDown(source.close);
    addTearDown(target.close);
    await _installRegistryCanary(target, version: 'target-registry');

    final envelope = await const FullBackupService().buildFullBackupEnvelope(
      source,
      createdAt: DateTime.utc(2026, 8, 30, 13),
      sourcePlatform: 'test',
    );
    await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
      preRestoreBackupCreatedAt: DateTime.utc(2026, 8, 30, 13, 1),
      sourcePlatform: 'test',
    );

    final brands = await target.query('merchant_brands');
    expect(brands.map((row) => row['id']), contains('merchant-legacy'));
    expect(brands.map((row) => row['id']), isNot(contains('target-only')));
    final observations = await target.query('merchant_identity_observations');
    expect(observations, isNotEmpty);
    expect(observations.single['seller_identifier'], '30340553');

    final registry = await target.query('business_registry_snapshots');
    expect(registry.map((row) => row['version']), contains('target-registry'));

    await expectLater(
      target.update(
        'merchant_identity_observations',
        <String, Object?>{'literal_name': '不應可覆寫'},
      ),
      throwsA(anything),
    );
  });

  test('scope V7 backup restores into V22 and deterministically rebuilds identity graph', () async {
    final source = await _openV22Fixture();
    final target = await _openV22Fixture(
      merchantId: 'target-only',
      merchantName: '目標暫存商家',
      sellerIdentifier: '12345675',
    );
    addTearDown(source.close);
    addTearDown(target.close);

    final current = await const FullBackupService().buildFullBackupEnvelope(
      source,
      createdAt: DateTime.utc(2026, 8, 30, 14),
      sourcePlatform: 'test',
    );
    final metadata = Map<String, Object?>.from(
      current['metadata']! as Map<String, Object?>,
    );
    final data = Map<String, Object?>.from(
      current['data']! as Map<String, Object?>,
    );
    metadata['backup_scope_version'] = 7;
    metadata['database_schema_version'] = 21;
    metadata['included_tables'] = FullBackupScope.legacyScopeV7TableNames;
    for (final tableName in FullBackupScope.merchantIdentityUserTableNames) {
      data.remove(tableName);
    }
    final legacyEnvelope = <String, Object?>{
      'metadata': metadata,
      'data': data,
    };

    await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      legacyEnvelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
      preRestoreBackupCreatedAt: DateTime.utc(2026, 8, 30, 14, 1),
      sourcePlatform: 'test',
    );

    final brand = await target.query(
      'merchant_brands',
      where: 'id = ?',
      whereArgs: <Object?>['merchant-legacy'],
    );
    expect(brand, hasLength(1));
    final legal = await target.query(
      'merchant_legal_entities',
      where: 'seller_identifier = ?',
      whereArgs: <Object?>['30340553'],
    );
    expect(legal, hasLength(1));
    final links = await target.query(
      'merchant_brand_legal_links',
      where: 'merchant_brand_id = ? AND decision = ?',
      whereArgs: <Object?>['merchant-legacy', 'confirmed'],
    );
    expect(links, hasLength(1));
    expect(links.single['evidence_source'], 'legacy_backup_explicit_binding');
  });
}

Future<Database> _openLegacyFixture() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      occurred_at TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute('''
    CREATE TABLE merchants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      alias TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      seller_identifier TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.insert('merchants', <String, Object?>{
    'id': 'merchant-legacy',
    'name': '測試商家',
    'alias': '測試門市',
    'note': 'P4.19.11 fixture',
    'is_archived': 0,
    'created_at': '2026-08-30T00:00:00.000Z',
    'updated_at': '2026-08-30T01:00:00.000Z',
    'seller_identifier': '30340553',
  });
  return db;
}

Future<Database> _openV22Fixture({
  String merchantId = 'merchant-legacy',
  String merchantName = '測試商家',
  String sellerIdentifier = '30340553',
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      occurred_at TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute('''
    CREATE TABLE merchants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      alias TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      seller_identifier TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.insert('merchants', <String, Object?>{
    'id': merchantId,
    'name': merchantName,
    'alias': '',
    'note': 'fixture',
    'is_archived': 0,
    'created_at': '2026-08-30T00:00:00.000Z',
    'updated_at': '2026-08-30T01:00:00.000Z',
    'seller_identifier': sellerIdentifier,
  });
  await createCanonicalProductionV22Tables(db);
  return db;
}

Future<void> _installRegistryCanary(
  Database db, {
  required String version,
}) async {
  await db.insert('business_registry_snapshots', <String, Object?>{
    'version': version,
    'source_dataset': 'official-canary-fixture',
    'source_data_date': '2026-08-30',
    'content_sha256': List<String>.filled(64, 'a').join(),
    'status': 'installed',
    'installed_at': '2026-08-30T00:00:00.000Z',
    'created_at': '2026-08-30T00:00:00.000Z',
  });
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.query(
    'sqlite_master',
    columns: const <String>['name'],
    where: 'type = ? AND name = ?',
    whereArgs: <Object?>['table', tableName],
  );
  return rows.isNotEmpty;
}
