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

    const entity = BusinessRegistryEntity(
      sellerIdentifier: '22222222',
      entityType: BusinessRegistryEntityType.unknown,
      legalName: '官方稅籍實體',
      registrationStatus: 'active_tax_registration',
      parentSellerIdentifier: '',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    );
    final entityLine =
        BusinessRegistryNationwideBuildPass.canonicalEntityLine(entity);
    final contentSha = await _sha256(utf8.encode(entityLine));
    final headerLine = '${jsonEncode(<String, Object?>{
      'record_type': 'header',
      'registry_version': '2026-09-08-unknown-fixture',
      'source_authority': 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
      'source_dataset': 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      'source_data_date': '2026-09-07',
      'coverage': 'taiwan_nationwide',
      'entity_count': 1,
      'registry_content_sha256': contentSha,
    })}\n';
    final uncompressedBytes = utf8.encode('$headerLine$entityLine');
    final compressedBytes = gzip.encode(uncompressedBytes);
    final downloadSha = await _sha256(compressedBytes);
    final file = File('${tempDir.path}/unknown.registry.gz');
    await file.writeAsBytes(compressedBytes, flush: true);

    final manifest = BusinessRegistryDistributionManifest(
      schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
      registryVersion: '2026-09-08-unknown-fixture',
      sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      sourceDataDate: '2026-09-07',
      coverage: 'taiwan_nationwide',
      format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
      entityCount: 1,
      downloadUri: Uri.parse(
        'https://github.com/easonliu714/my_finance_app_public/releases/download/registry-v1/unknown.registry.gz',
      ),
      downloadSha256: downloadSha,
      registryContentSha256: contentSha,
      compressedSizeBytes: compressedBytes.length,
      uncompressedSizeBytes: uncompressedBytes.length,
      attribution: '財政部財政資訊中心 / 經濟部商業發展署',
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
    expect(result.entityCount, 1);
    final installed = await db.query(
      'business_registry_entities',
      where: 'seller_identifier = ?',
      whereArgs: const <Object?>['22222222'],
    );
    expect(installed, hasLength(1));
    expect(installed.single['entity_type'], 'unknown');
    expect(installed.single['legal_name'], '官方稅籍實體');
  });
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
