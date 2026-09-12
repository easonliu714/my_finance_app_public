import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22_merchant_identity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('candidate migration preserves legacy merchant ids and explicit seller binding', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE merchants (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        alias TEXT NOT NULL DEFAULT '',
        seller_identifier TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert('merchants', <String, Object?>{
      'id': 'merchant-a',
      'name': '全家便利商店',
      'alias': '板橋測試店',
      'seller_identifier': '60744698',
      'note': 'existing user merchant',
      'is_archived': 0,
      'created_at': '2026-08-28T00:00:00.000Z',
      'updated_at': '2026-08-30T00:00:00.000Z',
    });
    await db.insert('merchants', <String, Object?>{
      'id': 'merchant-b',
      'name': '一品現泡茶店',
      'alias': '',
      'seller_identifier': '',
      'note': '',
      'is_archived': 0,
      'created_at': '2026-08-28T00:00:00.000Z',
      'updated_at': '2026-08-30T00:00:00.000Z',
    });

    await createMerchantIdentityV22CandidateTables(db);
    await createMerchantIdentityV22CandidateTables(db);

    final brands = await db.query('merchant_brands', orderBy: 'id');
    expect(brands, hasLength(2));
    expect(brands[0]['id'], 'merchant-a');
    expect(brands[0]['display_name'], '全家便利商店');
    expect(brands[1]['id'], 'merchant-b');

    final aliases = await db.query('merchant_brand_aliases');
    expect(aliases, hasLength(1));
    expect(aliases.single['merchant_brand_id'], 'merchant-a');
    expect(aliases.single['literal_alias'], '板橋測試店');

    final legal = await db.query('merchant_legal_entities');
    expect(legal, hasLength(1));
    expect(legal.single['seller_identifier'], '60744698');
    expect(legal.single['legal_name'], '');

    final links = await db.query('merchant_brand_legal_links');
    expect(links, hasLength(1));
    expect(links.single['merchant_brand_id'], 'merchant-a');
    expect(links.single['decision'], 'confirmed');
    expect(links.single['evidence_source'], 'p4_19_11_explicit_binding');

    final observations = await db.query('merchant_identity_observations');
    expect(observations, hasLength(1));
    expect(observations.single['literal_name'], '全家便利商店');
    expect(observations.single['decision'], 'confirmed');

    final legacyRows = await db.query('merchants', orderBy: 'id');
    expect(legacyRows, hasLength(2));
    expect(legacyRows.first['seller_identifier'], '60744698');
  });

  test('candidate migration formalizes seller_identifier column without deleting legacy rows', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
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
    await db.insert('merchants', <String, Object?>{
      'id': 'legacy-no-tax',
      'name': '既有商家',
      'alias': '',
      'note': '',
      'is_archived': 0,
      'created_at': '2026-08-01T00:00:00.000Z',
      'updated_at': '2026-08-01T00:00:00.000Z',
    });

    await createMerchantIdentityV22CandidateTables(db);

    final columns = await db.rawQuery('PRAGMA table_info(merchants)');
    expect(columns.any((row) => row['name'] == 'seller_identifier'), isTrue);
    final legacy = await db.query('merchants');
    expect(legacy.single['id'], 'legacy-no-tax');
    expect(legacy.single['seller_identifier'], '');
    expect(await db.query('merchant_brands'), hasLength(1));
  });

  test('official registry cache is replaceable and isolated from user merchant identity', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    addTearDown(db.close);
    await createMerchantIdentityV22CandidateTables(db);

    await db.insert('merchant_brands', <String, Object?>{
      'id': 'brand-user',
      'display_name': '全家便利商店',
      'display_override': '',
      'note': '',
      'is_archived': 0,
      'created_at': '2026-08-30T00:00:00.000Z',
      'updated_at': '2026-08-30T00:00:00.000Z',
    });
    await db.insert('business_registry_snapshots', <String, Object?>{
      'version': '2026-08-30-a',
      'source_dataset': 'official-fixture',
      'source_data_date': '2026-08-30',
      'content_sha256': List<String>.filled(64, 'a').join(),
      'status': 'installed',
      'installed_at': '2026-08-30T00:00:00.000Z',
      'created_at': '2026-08-30T00:00:00.000Z',
    });
    await db.insert('business_registry_entities', <String, Object?>{
      'snapshot_version': '2026-08-30-a',
      'jurisdiction': 'TW',
      'seller_identifier': '60744698',
      'entity_type': 'company',
      'legal_name': '官方登記名稱範例',
      'registration_status': 'active',
      'parent_seller_identifier': '',
      'source_dataset': 'official-fixture',
    });

    await db.delete(
      'business_registry_snapshots',
      where: 'version = ?',
      whereArgs: <Object?>['2026-08-30-a'],
    );

    expect(await db.query('business_registry_entities'), isEmpty);
    expect(await db.query('merchant_brands'), hasLength(1));
    expect((await db.query('merchant_brands')).single['id'], 'brand-user');
  });

  test('negative registry lookup cache is version scoped', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    addTearDown(db.close);
    await createMerchantIdentityV22CandidateTables(db);

    for (final version in <String>['v1', 'v2']) {
      await db.insert('business_registry_snapshots', <String, Object?>{
        'version': version,
        'source_dataset': 'official-fixture',
        'source_data_date': '',
        'content_sha256': List<String>.filled(64, 'b').join(),
        'status': 'installed',
        'installed_at': '2026-08-30T00:00:00.000Z',
        'created_at': '2026-08-30T00:00:00.000Z',
      });
      await db.insert('business_registry_negative_lookups', <String, Object?>{
        'seller_identifier': '60744698',
        'snapshot_version': version,
        'checked_at': '2026-08-30T00:00:00.000Z',
      });
    }

    expect(await db.query('business_registry_negative_lookups'), hasLength(2));
    await expectLater(
      db.insert('business_registry_negative_lookups', <String, Object?>{
        'seller_identifier': '60744698',
        'snapshot_version': 'v2',
        'checked_at': '2026-08-30T01:00:00.000Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('merchant identity observations are append-only evidence', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createMerchantIdentityV22CandidateTables(db);
    await db.insert('merchant_identity_observations', <String, Object?>{
      'id': 'obs-1',
      'literal_name': '原始發票文字',
      'normalized_name': normalizeMerchantIdentityName('原始發票文字'),
      'seller_identifier': '',
      'source': 'invoice',
      'source_reference': 'fixture',
      'merchant_brand_id': null,
      'legal_entity_id': null,
      'branch_or_outlet_id': null,
      'decision': 'observed',
      'observed_at': '2026-08-30T00:00:00.000Z',
      'created_at': '2026-08-30T00:00:00.000Z',
    });

    await expectLater(
      db.update(
        'merchant_identity_observations',
        <String, Object?>{'literal_name': '覆寫'},
        where: 'id = ?',
        whereArgs: <Object?>['obs-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'merchant_identity_observations',
        where: 'id = ?',
        whereArgs: <Object?>['obs-1'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });
}
