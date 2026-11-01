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
}
