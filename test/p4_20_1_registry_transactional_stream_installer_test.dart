import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_bounded_downloader.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_stream_validator.dart';
import 'package:my_finance_app/features/merchant/business_registry_transactional_stream_installer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P4.20.1-C transactional stream installer', () {
    late Database db;
    late Directory tempDir;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
        ),
      );
      await createCanonicalProductionV22Tables(db);
      tempDir = await Directory.systemTemp.createTemp('p4_20_1_install_');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('installs validated nationwide stream atomically in bounded batches',
        () async {
      await _insertUserOwnedBrand(db);
      await _insertInstalledSnapshot(db, version: '2026-08-01');
      final fixture = await _writeValidatedFixture(
        tempDir: tempDir,
        version: '2026-09-01',
      );

      final result = await BusinessRegistryTransactionalStreamInstaller(
        database: db,
        batchSize: 1,
      ).install(
        manifest: fixture.manifest,
        artifact: fixture.validatedArtifact,
      );

      expect(result.status, BusinessRegistryStreamInstallStatus.installed);
      expect(result.version, '2026-09-01');
      expect(result.entityCount, 2);
      expect(await fixture.validatedArtifact.file.exists(), isFalse);

      final snapshots = await db.query(
        'business_registry_snapshots',
        orderBy: 'version ASC',
      );
      expect(snapshots, hasLength(2));
      expect(snapshots.first['status'], 'superseded');
      expect(snapshots.last['status'], 'installed');

      final entities = await db.query(
        'business_registry_entities',
        where: 'snapshot_version = ?',
        whereArgs: const <Object?>['2026-09-01'],
        orderBy: 'seller_identifier ASC',
      );
      expect(entities, hasLength(2));
      expect(entities.first['seller_identifier'], '12345678');
      expect(entities.last['seller_identifier'], '87654321');

      final brands = await db.query(
        'merchant_brands',
        where: 'id = ?',
        whereArgs: const <Object?>['user-brand'],
      );
      expect(brands, hasLength(1));
      expect(brands.single['display_name'], '使用者正式商家');
    });

    test('tamper during second pass rolls back and retains last-known-good',
        () async {
      await _insertUserOwnedBrand(db);
      await _insertInstalledSnapshot(db, version: '2026-08-01');
      final fixture = await _writeValidatedFixture(
        tempDir: tempDir,
        version: '2026-09-01',
      );

      await fixture.validatedArtifact.file.writeAsBytes(
        const <int>[31, 139, 8, 0, 0, 0, 0, 0],
        flush: true,
      );

      await expectLater(
        BusinessRegistryTransactionalStreamInstaller(
          database: db,
          batchSize: 1,
        ).install(
          manifest: fixture.manifest,
          artifact: fixture.validatedArtifact,
        ),
        throwsA(anything),
      );
      expect(await fixture.validatedArtifact.file.exists(), isFalse);

      final installed = await db.query(
        'business_registry_snapshots',
        where: 'status = ?',
        whereArgs: const <Object?>['installed'],
      );
      expect(installed, hasLength(1));
      expect(installed.single['version'], '2026-08-01');

      final failedVersion = await db.query(
        'business_registry_snapshots',
        where: 'version = ?',
        whereArgs: const <Object?>['2026-09-01'],
      );
      expect(failedVersion, isEmpty);

      final oldEntities = await db.query(
        'business_registry_entities',
        where: 'snapshot_version = ?',
        whereArgs: const <Object?>['2026-08-01'],
      );
      expect(oldEntities, hasLength(1));
      expect(oldEntities.single['legal_name'], '既有官方資料');

      final brands = await db.query(
        'merchant_brands',
        where: 'id = ?',
        whereArgs: const <Object?>['user-brand'],
      );
      expect(brands, hasLength(1));
      expect(brands.single['display_name'], '使用者正式商家');
    });
  });
}

Future<void> _insertUserOwnedBrand(Database db) async {
  await db.insert('merchant_brands', <String, Object?>{
    'id': 'user-brand',
    'display_name': '使用者正式商家',
    'display_override': '',
    'note': 'must survive registry replacement',
    'is_archived': 0,
    'created_at': '2026-08-01T00:00:00.000Z',
    'updated_at': '2026-08-01T00:00:00.000Z',
  });
}

Future<void> _insertInstalledSnapshot(
  Database db, {
  required String version,
}) async {
  await db.insert('business_registry_snapshots', <String, Object?>{
    'version': version,
    'source_dataset': 'MOEA_GCIS|nationwide|previous_dataset',
    'source_data_date': '2026-08-01',
    'content_sha256': 'a' * 64,
    'status': 'installed',
    'installed_at': '2026-08-01T00:00:00.000Z',
    'created_at': '2026-08-01T00:00:00.000Z',
  });
  await db.insert('business_registry_entities', <String, Object?>{
    'snapshot_version': version,
    'jurisdiction': 'TW',
    'seller_identifier': '30340553',
    'entity_type': 'business',
    'legal_name': '既有官方資料',
    'registration_status': '核准設立',
    'parent_seller_identifier': '',
    'source_dataset': 'previous_dataset',
  });
}

Future<_ValidatedFixture> _writeValidatedFixture({
  required Directory tempDir,
  required String version,
}) async {
  const entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: '12345678',
      entityType: BusinessRegistryEntityType.company,
      legalName: '甲公司',
      registrationStatus: '核准設立',
      parentSellerIdentifier: '',
      sourceDataset: 'nationwide_company_business_branch',
    ),
    BusinessRegistryEntity(
      sellerIdentifier: '87654321',
      entityType: BusinessRegistryEntityType.business,
      legalName: '乙商號',
      registrationStatus: '核准設立',
      parentSellerIdentifier: '',
      sourceDataset: 'nationwide_company_business_branch',
    ),
  ];
  final entityLines = entities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .toList(growable: false);
  final contentSha = await _sha256(utf8.encode(entityLines.join()));
  final headerLine = '${jsonEncode(<String, Object?>{
    'record_type': 'header',
    'registry_version': version,
    'source_authority': 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    'source_dataset': 'nationwide_company_business_branch',
    'source_data_date': '2026-09-01',
    'coverage': 'taiwan_nationwide',
    'entity_count': entities.length,
    'registry_content_sha256': contentSha,
  })}\n';
  final uncompressedBytes = utf8.encode('$headerLine${entityLines.join()}');
  final compressedBytes = gzip.encode(uncompressedBytes);
  final downloadSha = await _sha256(compressedBytes);
  final file = File('${tempDir.path}/$version.registry.gz');
  await file.writeAsBytes(compressedBytes, flush: true);

  final manifest = BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: version,
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'nationwide_company_business_branch',
    sourceDataDate: '2026-09-01',
    coverage: 'taiwan_nationwide',
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: entities.length,
    downloadUri: Uri.parse(
      'https://github.com/easonliu714/my_finance_app_public/releases/download/registry-v1/registry.gz',
    ),
    downloadSha256: downloadSha,
    registryContentSha256: contentSha,
    compressedSizeBytes: compressedBytes.length,
    uncompressedSizeBytes: uncompressedBytes.length,
    attribution: '經濟部商業發展署 / data.gov.tw',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
  final downloaded = BusinessRegistryDownloadedArtifact(
    file: file,
    sizeBytes: compressedBytes.length,
    sha256: downloadSha,
  );
  final validated = await const BusinessRegistryStreamValidator().validate(
    manifest: manifest,
    artifact: downloaded,
  );
  return _ValidatedFixture(
    manifest: manifest,
    validatedArtifact: validated,
  );
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class _ValidatedFixture {
  const _ValidatedFixture({
    required this.manifest,
    required this.validatedArtifact,
  });

  final BusinessRegistryDistributionManifest manifest;
  final BusinessRegistryValidatedArtifact validatedArtifact;
}
