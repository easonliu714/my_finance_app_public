import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_audit.dart';
import 'package:my_finance_app/database/production_schema_v24.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service_v8.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // B3 #18: instantiate the actual V24 extension in an isolated in-memory
  // database; never open the installed accounting DB or an owner backup.
  Future<Database> openIsolatedV24() => openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
        version: canonicalProductionSchemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          // The V24 extension builds on these production core table names.
          // Their fixture columns are intentionally synthetic, not a claim
          // of a complete installed AccountRepository schema inventory.
          await db.execute(
            'CREATE TABLE accounts ('
            'id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, '
            'is_archived INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE transactions ('
            'id TEXT PRIMARY KEY, note TEXT NOT NULL)',
          );
          await createCanonicalProductionV24Tables(db);
        },
      );

  test('B3 V24 schema metadata, cache exclusion and isolated restore', () async {
    final source = await openIsolatedV24();
    final target = await openIsolatedV24();
    addTearDown(source.close);
    addTearDown(target.close);

    await source.insert('accounts', <String, Object?>{
      'id': 'synthetic-account',
      'name': 'private-account-sentinel',
      'type': 'cash',
    });
    await source.insert('transactions', <String, Object?>{
      'id': 'synthetic-transaction',
      'note': 'private-transaction-sentinel',
    });
    await source.insert('merchant_brands', <String, Object?>{
      'id': 'synthetic-brand',
      'display_name': 'private-brand-sentinel',
      'created_at': '2026-11-01T00:00:00Z',
      'updated_at': '2026-11-01T00:00:00Z',
    });
    await source.insert('business_registry_snapshots', <String, Object?>{
      'version': 'source-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'a').join(),
      'status': 'installed',
      'created_at': '2026-11-01T00:00:00Z',
    });
    await source.insert(
      'business_registry_official_details',
      <String, Object?>{
        'snapshot_version': 'source-cache',
        'jurisdiction': 'TW',
        'seller_identifier': '12345678',
        'official_json': '{"fixture":"source-only"}',
      },
    );
    await target.insert('business_registry_snapshots', <String, Object?>{
      'version': 'target-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'b').join(),
      'status': 'installed',
      'created_at': '2026-11-01T00:00:00Z',
    });
    await target.insert(
      'business_registry_official_details',
      <String, Object?>{
        'snapshot_version': 'target-cache',
        'jurisdiction': 'TW',
        'seller_identifier': '87654321',
        'official_json': '{"fixture":"target-only"}',
      },
    );

    final changesBefore = (await source.rawQuery(
      'SELECT total_changes() AS n',
    )).single['n'];
    const audit = ProductionSchemaAuditService();
    final first = await audit.inspect(source);
    final second = await audit.inspect(source);
    expect(first.userVersion, canonicalProductionSchemaVersion);
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    final detail = first.tables['business_registry_official_details']!;
    expect(
      detail.foreignKeys.single['parent_table'],
      'business_registry_snapshots',
    );
    expect(detail.foreignKeys.single['from_column'], 'snapshot_version');
    final index = detail.indexes.singleWhere(
      (entry) =>
          entry['name'] == 'idx_business_registry_official_detail_lookup',
    );
    expect(
      (index['columns']! as List<Map<String, Object?>>)
          .map((column) => column['name'])
          .toList(),
      <String>['jurisdiction', 'seller_identifier', 'snapshot_version'],
    );
    final schemaJson = jsonEncode(first.toJson());
    expect(schemaJson, isNot(contains('private-account-sentinel')));
    expect(schemaJson, isNot(contains('private-transaction-sentinel')));
    expect(schemaJson, isNot(contains('private-brand-sentinel')));
    expect(
      (await source.rawQuery('SELECT total_changes() AS n')).single['n'],
      changesBefore,
    );

    final coverage = await FullBackupScope.inspect(source);
    expect(coverage.isComplete, isTrue);
    expect(coverage.unknownTables, isEmpty);
    expect(
      coverage.excludedPresentTables,
      containsAll(<String>[
        'business_registry_snapshots',
        'business_registry_entities',
        'business_registry_official_details',
      ]),
    );
    final envelope = await const FullBackupService().buildFullBackupEnvelope(
      source,
      sourcePlatform: 'isolated-test',
    );
    final metadata = envelope['metadata']! as Map<String, Object?>;
    final data = envelope['data']! as Map<String, Object?>;
    expect(metadata['database_schema_version'], 24);
    expect(metadata['backup_scope_version'], 9);
    expect(metadata['coverage_complete'], isTrue);
    expect(data, isNot(contains('business_registry_snapshots')));
    expect(data, isNot(contains('business_registry_official_details')));
    expect(data['accounts'] as List, hasLength(1));
    expect(data['transactions'] as List, hasLength(1));
    expect(data['merchant_brands'] as List, hasLength(1));

    final restored = await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect(restored.audit.passed, isTrue);
    expect(
      (await target.query('accounts')).single['name'],
      'private-account-sentinel',
    );
    expect(
      (await target.query('transactions')).single['note'],
      'private-transaction-sentinel',
    );
    expect(
      (await target.query('merchant_brands')).single['display_name'],
      'private-brand-sentinel',
    );
    // Replaceable Registry cache must remain independent of user backup.
    final targetCache = await target.query('business_registry_official_details');
    expect(targetCache, hasLength(1));
    expect(targetCache.single['snapshot_version'], 'target-cache');
    expect(targetCache.single['seller_identifier'], '87654321');
  });

  // B3 #18 negative: a malformed user-owned row must roll back the complete
  // restore transaction without deleting existing accounting or Registry cache.
  // Both databases are isolated synthetic in-memory fixtures only.
  test('B3 V24 rejected managed restore rolls back user rows and cache', () async {
    final source = await openIsolatedV24();
    final target = await openIsolatedV24();
    addTearDown(source.close);
    addTearDown(target.close);

    await source.insert('accounts', <String, Object?>{
      'id': 'source-account',
      'name': 'source-private-sentinel',
      'type': 'cash',
    });
    await source.insert('merchant_brands', <String, Object?>{
      'id': 'source-brand',
      'display_name': 'source-brand-private-sentinel',
      'created_at': '2026-11-01T00:00:00Z',
      'updated_at': '2026-11-01T00:00:00Z',
    });
    await target.insert('accounts', <String, Object?>{
      'id': 'target-account',
      'name': 'target-private-sentinel',
      'type': 'cash',
    });
    await target.insert('business_registry_snapshots', <String, Object?>{
      'version': 'target-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'b').join(),
      'status': 'installed',
      'created_at': '2026-11-01T00:00:00Z',
    });
    await target.insert('business_registry_official_details', <String, Object?>{
      'snapshot_version': 'target-cache',
      'jurisdiction': 'TW',
      'seller_identifier': '87654321',
      'official_json': '{"fixture":"target-only"}',
    });

    final envelope =
        await const FullBackupService().buildFullBackupEnvelope(source);
    final corruptedData =
        Map<String, Object?>.from(envelope['data']! as Map);
    final brand = Map<String, Object?>.from(
      (corruptedData['merchant_brands']! as List).single as Map,
    );
    brand.remove('display_name'); // Required production column: NOT NULL.
    corruptedData['merchant_brands'] = <Object?>[brand];
    final corruptedEnvelope = <String, Object?>{
      ...envelope,
      'data': corruptedData,
    };

    await expectLater(
      const FullRestoreServiceV8().restoreFromEnvelope(
        target,
        corruptedEnvelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<DatabaseException>()),
    );
    final retainedAccounts = await target.query('accounts');
    expect(retainedAccounts, hasLength(1));
    expect(retainedAccounts.single['id'], 'target-account');
    expect(retainedAccounts.single['name'], 'target-private-sentinel');
    expect(await target.query('merchant_brands'), isEmpty);
    final retainedCache =
        await target.query('business_registry_official_details');
    expect(retainedCache, hasLength(1));
    expect(retainedCache.single['snapshot_version'], 'target-cache');
    expect(retainedCache.single['seller_identifier'], '87654321');
    expect(retainedCache.single['official_json'], '{"fixture":"target-only"}');
  });

  // B3 #18: a forged alias foreign key must fail after managed rows have
  // started restoring, and roll back every user-owned row. The independently
  // replaceable Registry cache and observation immutability triggers survive.
  // Only synthetic isolated in-memory databases are used.
  test('B3 V24 orphan alias restore rolls back and reinstates triggers', () async {
    final source = await openIsolatedV24();
    final target = await openIsolatedV24();
    addTearDown(source.close);
    addTearDown(target.close);

    await source.insert('accounts', <String, Object?>{
      'id': 'source-account',
      'name': 'source-private-sentinel',
      'type': 'cash',
    });
    await source.insert('merchant_brands', <String, Object?>{
      'id': 'source-brand',
      'display_name': 'source-brand-private-sentinel',
      'created_at': '2026-11-01T00:00:00Z',
      'updated_at': '2026-11-01T00:00:00Z',
    });
    await source.insert('merchant_brand_aliases', <String, Object?>{
      'id': 'source-alias',
      'merchant_brand_id': 'source-brand',
      'literal_alias': 'source alias',
      'normalized_alias': 'source alias',
      'source': 'isolated-fixture',
      'created_at': '2026-11-01T00:00:00Z',
    });
    await target.insert('accounts', <String, Object?>{
      'id': 'target-account',
      'name': 'target-private-sentinel',
      'type': 'cash',
    });
    await target.insert('merchant_brands', <String, Object?>{
      'id': 'target-brand',
      'display_name': 'target-brand-private-sentinel',
      'created_at': '2026-11-01T00:00:00Z',
      'updated_at': '2026-11-01T00:00:00Z',
    });
    await target.insert('business_registry_snapshots', <String, Object?>{
      'version': 'target-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'c').join(),
      'status': 'installed',
      'created_at': '2026-11-01T00:00:00Z',
    });
    await target.insert('business_registry_official_details',
        <String, Object?>{
      'snapshot_version': 'target-cache',
      'jurisdiction': 'TW',
      'seller_identifier': '87654321',
      'official_json': '{"fixture":"target-only"}',
    });

    final envelope =
        await const FullBackupService().buildFullBackupEnvelope(source);
    final corruptedData = Map<String, Object?>.from(
      envelope['data']! as Map,
    );
    final alias = Map<String, Object?>.from(
      (corruptedData['merchant_brand_aliases']! as List).single as Map,
    );
    alias['merchant_brand_id'] = 'nonexistent-brand';
    corruptedData['merchant_brand_aliases'] = <Object?>[alias];
    final corruptedEnvelope = <String, Object?>{
      ...envelope,
      'data': corruptedData,
    };

    await expectLater(
      const FullRestoreServiceV8().restoreFromEnvelope(
        target,
        corruptedEnvelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await target.query('accounts')).single['id'], 'target-account');
    expect((await target.query('merchant_brands')).single['id'], 'target-brand');
    expect(await target.query('merchant_brand_aliases'), isEmpty);
    final retainedCache =
        await target.query('business_registry_official_details');
    expect(retainedCache, hasLength(1));
    expect(retainedCache.single['snapshot_version'], 'target-cache');
    expect(retainedCache.single['official_json'], '{"fixture":"target-only"}');
    expect(await target.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final triggers = await target.query(
      'sqlite_master',
      columns: <String>['name'],
      where: 'type = ? AND name LIKE ?',
      whereArgs: <Object?>['trigger', 'trg_merchant_identity_observations_%'],
    );
    expect(triggers, hasLength(2));
  });

  // B3 #18 V24 positive custody: user-owned merchant observations and aliases
  // must round-trip, while replaceable official Registry cache stays local to
  // the target. Restore must re-enable both immutable-observation triggers.
  // No installed database or owner backup is accessed.
  test('B3 V24 observation round-trip retains cache and immutable triggers',
      () async {
    final source = await openIsolatedV24();
    final target = await openIsolatedV24();
    addTearDown(source.close);
    addTearDown(target.close);
    const stamp = '2026-11-01T00:00:00Z';

    await source.insert('accounts', <String, Object?>{
      'id': 'source-account',
      'name': 'source-private-sentinel',
      'type': 'cash',
    });
    await source.insert('merchant_brands', <String, Object?>{
      'id': 'source-brand',
      'display_name': 'source-brand-private-sentinel',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await source.insert('merchant_brand_aliases', <String, Object?>{
      'id': 'source-alias',
      'merchant_brand_id': 'source-brand',
      'literal_alias': 'source alias',
      'normalized_alias': 'sourcealias',
      'source': 'isolated-fixture',
      'created_at': stamp,
    });
    await source.insert('merchant_identity_observations', <String, Object?>{
      'id': 'source-observation',
      'literal_name': 'source observation',
      'normalized_name': 'sourceobservation',
      'source': 'isolated-fixture',
      'merchant_brand_id': 'source-brand',
      'observed_at': stamp,
      'created_at': stamp,
    });
    await source.insert('business_registry_snapshots', <String, Object?>{
      'version': 'source-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'a').join(),
      'status': 'installed',
      'created_at': stamp,
    });

    await target.insert('accounts', <String, Object?>{
      'id': 'target-account',
      'name': 'target-private-sentinel',
      'type': 'cash',
    });
    await target.insert('merchant_brands', <String, Object?>{
      'id': 'target-brand',
      'display_name': 'target-brand-private-sentinel',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await target.insert('merchant_identity_observations', <String, Object?>{
      'id': 'target-observation',
      'literal_name': 'target observation',
      'normalized_name': 'targetobservation',
      'source': 'isolated-fixture',
      'merchant_brand_id': 'target-brand',
      'observed_at': stamp,
      'created_at': stamp,
    });
    await target.insert('business_registry_snapshots', <String, Object?>{
      'version': 'target-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'b').join(),
      'status': 'installed',
      'created_at': stamp,
    });
    await target.insert('business_registry_official_details', <String, Object?>{
      'snapshot_version': 'target-cache',
      'jurisdiction': 'TW',
      'seller_identifier': '87654321',
      'official_json': '{"fixture":"target-only"}',
    });

    final envelope = await const FullBackupService().buildFullBackupEnvelope(source);
    final sourceData = envelope['data']! as Map<String, Object?>;
    expect(sourceData['merchant_identity_observations'] as List, hasLength(1));
    expect(sourceData['merchant_brand_aliases'] as List, hasLength(1));
    expect(sourceData, isNot(contains('business_registry_snapshots')));
    expect(sourceData, isNot(contains('business_registry_official_details')));

    final restored = await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect(restored.audit.passed, isTrue);
    final preRestoreData =
        restored.preRestoreBackupEnvelope['data']! as Map<String, Object?>;
    expect((preRestoreData['merchant_identity_observations']! as List).single,
        containsPair('id', 'target-observation'));
    expect((await target.query('accounts')).single['id'], 'source-account');
    expect((await target.query('merchant_brands')).single['id'], 'source-brand');
    expect((await target.query('merchant_brand_aliases')).single[
        'merchant_brand_id'], 'source-brand');
    final observations = await target.query('merchant_identity_observations');
    expect(observations, hasLength(1));
    expect(observations.single['id'], 'source-observation');
    expect(observations.single['merchant_brand_id'], 'source-brand');
    expect((await target.query('business_registry_official_details')).single[
        'snapshot_version'], 'target-cache');
    expect((await target.query('business_registry_snapshots')).single[
        'version'], 'target-cache');
    expect(await target.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    // These are real SQL write attempts on an isolated synthetic database:
    // the production observation immutability triggers must reject both.
    await expectLater(
      target.update('merchant_identity_observations',
          <String, Object?>{'literal_name': 'forged'},
          where: 'id = ?',
          whereArgs: <Object?>['source-observation']),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      target.delete('merchant_identity_observations',
          where: 'id = ?', whereArgs: <Object?>['source-observation']),
      throwsA(isA<DatabaseException>()),
    );
    expect((await target.query('merchant_identity_observations')).single[
        'literal_name'], 'source observation');
  });

  test('B3 V24 unknown private table blocks complete backup', () async {
    final db = await openIsolatedV24();
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE b3_unreviewed_private_rows (id TEXT PRIMARY KEY)',
    );
    final coverage = await FullBackupScope.inspect(db);
    expect(coverage.unknownTables, contains('b3_unreviewed_private_rows'));
    expect(coverage.isComplete, isFalse);
    await expectLater(
      const FullBackupService().buildFullBackupEnvelope(db),
      throwsA(isA<FullBackupCoverageException>()),
    );
  });

  // B3 #18 V25 negative: if the required pre-restore custody artifact cannot
  // be persisted, the destructive transaction must never start. Verify real
  // user-owned observations, independent public cache, FK and immutability
  // triggers against isolated in-memory V24 databases only.
  test('B3 V25 failed pre-restore custody persistence preserves all rows',
      () async {
    final source = await openIsolatedV24();
    final target = await openIsolatedV24();
    addTearDown(source.close);
    addTearDown(target.close);
    const stamp = '2026-11-02T00:00:00Z';

    await source.insert('accounts', <String, Object?>{
      'id': 'incoming-account',
      'name': 'incoming-private-sentinel',
      'type': 'cash',
    });
    await target.insert('accounts', <String, Object?>{
      'id': 'retained-account',
      'name': 'retained-private-sentinel',
      'type': 'cash',
    });
    await target.insert('merchant_brands', <String, Object?>{
      'id': 'retained-brand',
      'display_name': 'retained-brand-private-sentinel',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await target.insert('merchant_identity_observations',
        <String, Object?>{
      'id': 'retained-observation',
      'literal_name': 'retained private observation',
      'normalized_name': 'retainedprivateobservation',
      'source': 'isolated-fixture',
      'merchant_brand_id': 'retained-brand',
      'observed_at': stamp,
      'created_at': stamp,
    });
    await target.insert('business_registry_snapshots',
        <String, Object?>{
      'version': 'retained-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'd').join(),
      'status': 'installed',
      'created_at': stamp,
    });
    await target.insert('business_registry_official_details',
        <String, Object?>{
      'snapshot_version': 'retained-cache',
      'jurisdiction': 'TW',
      'seller_identifier': '87654321',
      'official_json': '{"fixture":"retained-only"}',
    });

    final envelope =
        await const FullBackupService().buildFullBackupEnvelope(source);
    var persistenceAttempted = false;
    await expectLater(
      const FullRestoreServiceV8().restoreFromEnvelope(
        target,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
        persistPreRestoreBackup: (preRestoreEnvelope) async {
          persistenceAttempted = true;
          final custody = preRestoreEnvelope['data']!
              as Map<String, Object?>;
          expect((custody['accounts']! as List).single,
              containsPair('id', 'retained-account'));
          expect((custody['merchant_identity_observations']! as List).single,
              containsPair('id', 'retained-observation'));
          expect(custody, isNot(contains('business_registry_snapshots')));
          throw StateError('synthetic pre-restore custody persistence failure');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(persistenceAttempted, isTrue);
    expect((await target.query('accounts')).single['id'],
        'retained-account');
    expect((await target.query('merchant_brands')).single['id'],
        'retained-brand');
    expect((await target.query('merchant_identity_observations')).single['id'],
        'retained-observation');
    expect((await target.query('business_registry_official_details')).single[
        'official_json'], '{"fixture":"retained-only"}');
    expect(await target.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    // The failure path must reinstate both production SQL immutability guards.
    await expectLater(
      target.update('merchant_identity_observations',
          <String, Object?>{'literal_name': 'forged'},
          where: 'id = ?',
          whereArgs: <Object?>['retained-observation']),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      target.delete('merchant_identity_observations',
          where: 'id = ?',
          whereArgs: <Object?>['retained-observation']),
      throwsA(isA<DatabaseException>()),
    );
    expect((await target.query('merchant_identity_observations')).single[
        'literal_name'], 'retained private observation');
  });


  // B3 #18 V26 security regression: pre-restore custody may await external
  // persistence, but observation immutability must NEVER be disabled during
  // that window. Only isolated synthetic in-memory V24 databases are used.
  test('B3 V26 custody callback cannot mutate immutable observations',
      () async {
    final source = await openIsolatedV24();
    final target = await openIsolatedV24();
    addTearDown(source.close);
    addTearDown(target.close);
    const stamp = '2026-11-02T00:00:00Z';
    await source.insert('accounts', <String, Object?>{
      'id': 'source-account', 'name': 'source-private', 'type': 'cash',
    });
    await target.insert('accounts', <String, Object?>{
      'id': 'target-account', 'name': 'target-private', 'type': 'cash',
    });
    await target.insert('merchant_brands', <String, Object?>{
      'id': 'target-brand',
      'display_name': 'target-private-brand',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await target.insert('merchant_identity_observations', <String, Object?>{
      'id': 'target-observation',
      'literal_name': 'immutable-private-sentinel',
      'normalized_name': 'immutableprivatesentinel',
      'source': 'isolated-fixture',
      'merchant_brand_id': 'target-brand',
      'observed_at': stamp,
      'created_at': stamp,
    });
    await target.insert('business_registry_snapshots', <String, Object?>{
      'version': 'target-cache',
      'source_dataset': 'synthetic-fixture',
      'content_sha256': List<String>.filled(64, 'e').join(),
      'status': 'installed',
      'created_at': stamp,
    });

    final envelope =
        await const FullBackupService().buildFullBackupEnvelope(source);
    var custodyCalled = false;
    final restored = await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
      persistPreRestoreBackup: (custody) async {
        custodyCalled = true;
        final before = custody['data']! as Map<String, Object?>;
        expect((before['merchant_identity_observations']! as List).single,
            containsPair('id', 'target-observation'));
        // Previously both statements succeeded because V8 dropped triggers
        // before awaiting this callback; neither may modify installed rows.
        await expectLater(
          target.update('merchant_identity_observations',
              <String, Object?>{'literal_name': 'forged-during-custody'},
              where: 'id = ?',
              whereArgs: <Object?>['target-observation']),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          target.delete('merchant_identity_observations',
              where: 'id = ?', whereArgs: <Object?>['target-observation']),
          throwsA(isA<DatabaseException>()),
        );
        expect((await target.query('merchant_identity_observations')).single[
            'literal_name'], 'immutable-private-sentinel');
        return 'isolated-synthetic-custody';
      },
    );
    expect(custodyCalled, isTrue);
    expect(restored.preRestoreBackupPath, 'isolated-synthetic-custody');
    expect(restored.audit.passed, isTrue);
    expect((await target.query('accounts')).single['id'], 'source-account');
    expect(await target.query('merchant_identity_observations'), isEmpty);
    expect((await target.query('business_registry_snapshots')).single[
        'version'], 'target-cache');
    expect(await target.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final triggers = await target.query('sqlite_master',
        columns: <String>['name'],
        where: 'type = ? AND name LIKE ?',
        whereArgs: <Object?>['trigger', 'trg_merchant_identity_observations_%']);
    expect(triggers, hasLength(2));
  });
}
