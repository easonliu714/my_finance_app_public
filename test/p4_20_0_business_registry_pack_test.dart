import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('bundled signed-canary validation subset has exact SHA and explicit limited coverage', () async {
    final text = File(
      'assets/seed/business_registry_validation_pack.json',
    ).readAsStringSync();
    final pack = BusinessRegistryPack.fromJsonText(text);
    final validation = await pack.validate();

    expect(validation.isValid, isTrue, reason: validation.errors.join(','));
    expect(pack.isValidationSubset, isTrue);
    expect(pack.isNationwide, isFalse);
    expect(pack.entities, hasLength(2));
    expect(
      pack.entities
          .where((entity) => entity.sellerIdentifier == '30340553')
          .single
          .legalName,
      '一品現泡茶店',
    );
    expect(
      pack.entities
          .where((entity) => entity.sellerIdentifier == '60744698')
          .single
          .legalName,
      '沄鉑國際有限公司',
    );
  });

  test('invalid authority or content hash is rejected before database mutation', () async {
    final db = await _openRegistryDb();
    addTearDown(db.close);
    final repository = BusinessRegistryRepository(database: db);
    final pack = BusinessRegistryPack(
      version: 'bad-pack',
      sourceAuthority: 'UNTRUSTED_SOURCE',
      sourceDataset: 'fixture',
      sourceDataDate: '2026-08-30',
      coverage: BusinessRegistryPack.nationwideCoverage,
      contentSha256: List<String>.filled(64, '0').join(),
      entities: const <BusinessRegistryEntity>[
        BusinessRegistryEntity(
          sellerIdentifier: '30340553',
          entityType: BusinessRegistryEntityType.business,
          legalName: '一品現泡茶店',
          sourceDataset: 'fixture',
        ),
      ],
    );

    final result = await repository.install(pack);
    expect(result.status, BusinessRegistryInstallStatus.rejected);
    expect(result.validationErrors, contains('REGISTRY_SOURCE_AUTHORITY_NOT_ALLOWED'));
    expect(result.validationErrors, contains('REGISTRY_SHA256_MISMATCH'));
    expect(await db.query('business_registry_snapshots'), isEmpty);
  });

  test('atomic install retains last known good snapshot when staged entity write fails', () async {
    final db = await _openRegistryDb();
    addTearDown(db.close);
    final repository = BusinessRegistryRepository(database: db);

    final first = await _pack(
      version: 'registry-v1',
      sellerIdentifier: '30340553',
      legalName: '一品現泡茶店',
      type: BusinessRegistryEntityType.business,
    );
    expect((await repository.install(first)).isSuccess, isTrue);

    await db.execute('''
      CREATE TRIGGER reject_registry_test_row
      BEFORE INSERT ON business_registry_entities
      WHEN NEW.seller_identifier = '87654321'
      BEGIN
        SELECT RAISE(ABORT, 'synthetic registry install failure');
      END
    ''');
    final second = await _pack(
      version: 'registry-v2',
      sellerIdentifier: '87654321',
      legalName: '合成測試公司',
      type: BusinessRegistryEntityType.company,
    );

    await expectLater(repository.install(second), throwsA(anything));
    final installed = await repository.installedSnapshot();
    expect(installed?.version, 'registry-v1');
    final failedRows = await db.query(
      'business_registry_snapshots',
      where: 'version = ?',
      whereArgs: const <Object?>['registry-v2'],
    );
    expect(failedRows, isEmpty);
  });

  test('local lookup hits installed snapshot and version-scopes negative cache', () async {
    final db = await _openRegistryDb();
    addTearDown(db.close);
    final repository = BusinessRegistryRepository(database: db);

    final first = await _pack(
      version: 'registry-v1',
      sellerIdentifier: '30340553',
      legalName: '一品現泡茶店',
      type: BusinessRegistryEntityType.business,
    );
    await repository.install(first);

    final hit = await repository.lookup('30340553');
    expect(hit.status, BusinessRegistryLookupStatus.hit);
    expect(hit.primaryEntity?.legalName, '一品現泡茶店');
    expect(hit.snapshotVersion, 'registry-v1');

    final miss1 = await repository.lookup('60744698');
    expect(miss1.status, BusinessRegistryLookupStatus.notFound);
    expect(miss1.negativeCacheHit, isFalse);
    final miss2 = await repository.lookup('60744698');
    expect(miss2.negativeCacheHit, isTrue);

    final second = await _pack(
      version: 'registry-v2',
      sellerIdentifier: '60744698',
      legalName: '沄鉑國際有限公司',
      type: BusinessRegistryEntityType.company,
    );
    await repository.install(second);
    final newVersionHit = await repository.lookup('60744698');
    expect(newVersionHit.status, BusinessRegistryLookupStatus.hit);
    expect(newVersionHit.snapshotVersion, 'registry-v2');
    expect(newVersionHit.primaryEntity?.legalName, '沄鉑國際有限公司');

    final oldNegative = await db.query(
      'business_registry_negative_lookups',
      where: 'seller_identifier = ? AND snapshot_version = ?',
      whereArgs: const <Object?>['60744698', 'registry-v1'],
    );
    expect(oldNegative, hasLength(1));
  });
}

Future<Database> _openRegistryDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  await createCanonicalProductionV22Tables(db);
  return db;
}

Future<BusinessRegistryPack> _pack({
  required String version,
  required String sellerIdentifier,
  required String legalName,
  required BusinessRegistryEntityType type,
}) async {
  final entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: sellerIdentifier,
      entityType: type,
      legalName: legalName,
      sourceDataset: 'official-fixture-$version',
    ),
  ];
  return BusinessRegistryPack(
    version: version,
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'official-fixture-$version',
    sourceDataDate: '2026-08-30',
    coverage: BusinessRegistryPack.nationwideCoverage,
    contentSha256: await computeBusinessRegistryPayloadSha256(entities),
    entities: entities,
  );
}
