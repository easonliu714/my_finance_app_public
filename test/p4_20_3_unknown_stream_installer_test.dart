import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_bounded_downloader.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/business_registry_stream_validator.dart';
import 'package:my_finance_app/features/merchant/business_registry_transactional_stream_installer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('P4.20.3 installer upgrades V22 cache before installing unknown subtype',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);

    final tempDir =
        await Directory.systemTemp.createTemp('p4_20_3_unknown_install_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const entities = <BusinessRegistryEntity>[
      BusinessRegistryEntity(
        sellerIdentifier: '30340553',
        entityType: BusinessRegistryEntityType.business,
        legalName: '一品現泡茶店',
        registrationStatus: 'active_tax_registration',
        sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      ),
      BusinessRegistryEntity(
        sellerIdentifier: '31655572',
        entityType: BusinessRegistryEntityType.branch,
        legalName: '富達零售股份有限公司晶技門市',
        registrationStatus: 'active_tax_registration',
        parentSellerIdentifier: '22853565',
        sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      ),
      BusinessRegistryEntity(
        sellerIdentifier: '60282181',
        entityType: BusinessRegistryEntityType.branch,
        legalName: '本米股份有限公司土城中央路營業所',
        registrationStatus: 'active_tax_registration',
        parentSellerIdentifier: '60769775',
        sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      ),
      BusinessRegistryEntity(
        sellerIdentifier: '77777777',
        entityType: BusinessRegistryEntityType.unknown,
        legalName: '官方稅籍實體',
        registrationStatus: 'active_tax_registration',
        sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      ),
    ];
    final entityLines = entities
        .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
        .join();
    final contentSha = await _sha256(utf8.encode(entityLines));
    final headerLine = '${jsonEncode(<String, Object?>{
      'record_type': 'header',
      'registry_version': '2026-09-08-unknown-fixture',
      'source_authority': 'MOF_FIA_ACTIVE_TAX_REGISTRY',
      'source_dataset': 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      'source_data_date': '2026-09-07',
      'coverage': 'taiwan_nationwide',
      'entity_count': entities.length,
      'registry_content_sha256': contentSha,
    })}\n';
    final uncompressedBytes = utf8.encode('$headerLine$entityLines');
    final compressedBytes = gzip.encode(uncompressedBytes);
    final downloadSha = await _sha256(compressedBytes);
    final file = File('${tempDir.path}/unknown.registry.gz');
    await file.writeAsBytes(compressedBytes, flush: true);

    final manifest = BusinessRegistryDistributionManifest(
      schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
      registryVersion: '2026-09-08-unknown-fixture',
      sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      sourceDataDate: '2026-09-07',
      coverage: 'taiwan_nationwide',
      format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
      entityCount: entities.length,
      downloadUri: Uri.parse(
        'https://github.com/easonliu714/my_finance_app_public/releases/download/registry-v1/unknown.registry.gz',
      ),
      downloadSha256: downloadSha,
      registryContentSha256: contentSha,
      compressedSizeBytes: compressedBytes.length,
      uncompressedSizeBytes: uncompressedBytes.length,
      attribution: '財政部財政資訊中心',
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

    final result = await BusinessRegistryTransactionalStreamInstaller(
      database: db,
      batchSize: 1,
    ).install(
      manifest: manifest,
      artifact: validated,
    );

    expect(result.status, BusinessRegistryStreamInstallStatus.installed);
    expect(result.entityCount, entities.length);

    final repository = BusinessRegistryRepository(database: db);
    final okMart = await repository.lookup('31655572');
    expect(okMart.status, BusinessRegistryLookupStatus.hit);
    expect(okMart.primaryEntity?.legalName, '富達零售股份有限公司晶技門市');
    expect(okMart.primaryEntity?.parentSellerIdentifier, '22853565');

    final benmi = await repository.lookup('60282181');
    expect(benmi.status, BusinessRegistryLookupStatus.hit);
    expect(benmi.primaryEntity?.legalName, '本米股份有限公司土城中央路營業所');
    expect(benmi.primaryEntity?.parentSellerIdentifier, '60769775');

    final unknown = await repository.lookup('77777777');
    expect(unknown.status, BusinessRegistryLookupStatus.hit);
    expect(unknown.primaryEntity?.entityType, BusinessRegistryEntityType.unknown);
    expect(unknown.primaryEntity?.legalName, '官方稅籍實體');
  });
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
