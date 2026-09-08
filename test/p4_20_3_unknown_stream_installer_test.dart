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

  test(
      'P4.20.3 V24 FIA stream installs full details and offline lookup cohort',
      () async {
    final db = await _openV22Database();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'p4_20_3_v24_install_',
    );
    addTearDown(() => _deleteIfPresent(tempDir));

    final repository = BusinessRegistryRepository(database: db);
    final beforeInstall = await repository.lookup('31655572');
    expect(beforeInstall.status, BusinessRegistryLookupStatus.noInstalledRegistry);

    final fixture = await _buildFixture(
      tempDir: tempDir,
      version: '2026-09-08-v24-fixture',
      entities: _fiaEntities,
    );
    final validated = await const BusinessRegistryStreamValidator().validate(
      manifest: fixture.manifest,
      artifact: fixture.downloaded,
    );

    final result = await BusinessRegistryTransactionalStreamInstaller(
      database: db,
      batchSize: 1,
    ).install(
      manifest: fixture.manifest,
      artifact: validated,
    );

    expect(result.status, BusinessRegistryStreamInstallStatus.installed);
    expect(result.entityCount, _fiaEntities.length);

    final detailRows = await db.query('business_registry_official_details');
    expect(detailRows, hasLength(_fiaEntities.length));

    final okMart = await repository.lookup('31655572');
    expect(okMart.status, BusinessRegistryLookupStatus.hit);
    expect(okMart.primaryEntity?.legalName, '富達零售股份有限公司晶技門市');
    expect(okMart.primaryEntity?.parentSellerIdentifier, '22853565');

    final benmi = await repository.lookup('60282181');
    expect(benmi.status, BusinessRegistryLookupStatus.hit);
    expect(benmi.primaryEntity?.legalName, '本米股份有限公司土城中央路營業所');
    expect(benmi.primaryEntity?.parentSellerIdentifier, '60769775');

    final unseen = await repository.lookup('77777777');
    expect(unseen.status, BusinessRegistryLookupStatus.hit);
    expect(unseen.primaryEntity?.entityType, BusinessRegistryEntityType.unknown);
    expect(unseen.primaryEntity?.legalName, '官方稅籍實體');

    final official = await repository.lookupOfficialDetail('31655572');
    expect(official.status, BusinessRegistryOfficialDetailLookupStatus.hit);
    expect(official.fields, hasLength(16));
    expect(official.fields['統一編號'], '31655572');
    expect(official.fields['營業人名稱'], '富達零售股份有限公司晶技門市');
    expect(official.fields['營業地址'], '新北市土城區中央路測試門市');
    expect(official.fields['使用統一發票'], 'Y');
  });

  test('P4.20.3 failed replacement rolls back and retains V24 LKG', () async {
    final db = await _openV22Database();
    addTearDown(db.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'p4_20_3_v24_lkg_',
    );
    addTearDown(() => _deleteIfPresent(tempDir));

    final baseline = await _buildFixture(
      tempDir: tempDir,
      version: '2026-09-08-lkg',
      entities: _fiaEntities,
    );
    final baselineValidated =
        await const BusinessRegistryStreamValidator().validate(
      manifest: baseline.manifest,
      artifact: baseline.downloaded,
    );
    await BusinessRegistryTransactionalStreamInstaller(
      database: db,
      batchSize: 1,
    ).install(
      manifest: baseline.manifest,
      artifact: baselineValidated,
    );

    const replacementEntities = <BusinessRegistryEntity>[
      BusinessRegistryEntity(
        sellerIdentifier: '88888888',
        entityType: BusinessRegistryEntityType.unknown,
        legalName: '不應完成安裝的新資料',
        registrationStatus: 'active_tax_registration',
        sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
        officialFields: _unseenOfficialFields,
      ),
    ];
    final replacement = await _buildFixture(
      tempDir: tempDir,
      version: '2026-09-09-broken',
      entities: replacementEntities,
    );
    final replacementValidated =
        await const BusinessRegistryStreamValidator().validate(
      manifest: replacement.manifest,
      artifact: replacement.downloaded,
    );

    // Simulate corruption after first-pass validation. The installer must
    // independently rebind bytes/hash and roll the whole replacement back.
    await replacement.downloaded.file.writeAsBytes(
      const <int>[0x00],
      mode: FileMode.append,
      flush: true,
    );

    await expectLater(
      BusinessRegistryTransactionalStreamInstaller(
        database: db,
        batchSize: 1,
      ).install(
        manifest: replacement.manifest,
        artifact: replacementValidated,
      ),
      throwsA(anything),
    );

    final repository = BusinessRegistryRepository(database: db);
    final retained = await repository.installedSnapshot();
    expect(retained?.version, '2026-09-08-lkg');

    final retainedLookup = await repository.lookup('31655572');
    expect(retainedLookup.status, BusinessRegistryLookupStatus.hit);
    expect(
      retainedLookup.primaryEntity?.legalName,
      '富達零售股份有限公司晶技門市',
    );

    final rejectedLookup = await repository.lookup('88888888');
    expect(rejectedLookup.status, BusinessRegistryLookupStatus.notFound);

    final rejectedSnapshot = await db.query(
      'business_registry_snapshots',
      where: 'version = ?',
      whereArgs: const <Object?>['2026-09-09-broken'],
    );
    expect(rejectedSnapshot, isEmpty);
  });
}

Future<Database> _openV22Database() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
  await createCanonicalProductionV22Tables(db);
  return db;
}

Future<_RegistryFixture> _buildFixture({
  required Directory tempDir,
  required String version,
  required List<BusinessRegistryEntity> entities,
}) async {
  final entityLines = entities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .join();
  final contentSha = await _sha256(utf8.encode(entityLines));
  final headerLine = '${jsonEncode(<String, Object?>{
    'record_type': 'header',
    'registry_version': version,
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
  final file = File('${tempDir.path}/$version.registry.gz');
  await file.writeAsBytes(compressedBytes, flush: true);

  final manifest = BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: version,
    sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
    sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    sourceDataDate: '2026-09-07',
    coverage: 'taiwan_nationwide',
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: entities.length,
    downloadUri: Uri.parse(
      'https://github.com/easonliu714/my_finance_app_public/releases/download/'
      'p4.20.3-registry/$version.registry.gz',
    ),
    downloadSha256: downloadSha,
    registryContentSha256: contentSha,
    compressedSizeBytes: compressedBytes.length,
    uncompressedSizeBytes: uncompressedBytes.length,
    attribution: '財政部財政資訊中心',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
  return _RegistryFixture(
    manifest: manifest,
    downloaded: BusinessRegistryDownloadedArtifact(
      file: file,
      sizeBytes: compressedBytes.length,
      sha256: downloadSha,
    ),
  );
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<void> _deleteIfPresent(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

class _RegistryFixture {
  const _RegistryFixture({
    required this.manifest,
    required this.downloaded,
  });

  final BusinessRegistryDistributionManifest manifest;
  final BusinessRegistryDownloadedArtifact downloaded;
}

const _fiaEntities = <BusinessRegistryEntity>[
  BusinessRegistryEntity(
    sellerIdentifier: '30340553',
    entityType: BusinessRegistryEntityType.business,
    legalName: '一品現泡茶店',
    registrationStatus: 'active_tax_registration',
    sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    officialFields: _teaOfficialFields,
  ),
  BusinessRegistryEntity(
    sellerIdentifier: '31655572',
    entityType: BusinessRegistryEntityType.branch,
    legalName: '富達零售股份有限公司晶技門市',
    registrationStatus: 'active_tax_registration',
    parentSellerIdentifier: '22853565',
    sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    officialFields: _okMartOfficialFields,
  ),
  BusinessRegistryEntity(
    sellerIdentifier: '60282181',
    entityType: BusinessRegistryEntityType.branch,
    legalName: '本米股份有限公司土城中央路營業所',
    registrationStatus: 'active_tax_registration',
    parentSellerIdentifier: '60769775',
    sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    officialFields: _benmiOfficialFields,
  ),
  BusinessRegistryEntity(
    sellerIdentifier: '77777777',
    entityType: BusinessRegistryEntityType.unknown,
    legalName: '官方稅籍實體',
    registrationStatus: 'active_tax_registration',
    sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    officialFields: _unseenOfficialFields,
  ),
];

const _teaOfficialFields = <String, String>{
  '營業地址': '新北市測試區茶店路1號',
  '統一編號': '30340553',
  '總機構統一編號': '',
  '營業人名稱': '一品現泡茶店',
  '資本額': '100000',
  '設立日期': '20100101',
  '組織別名稱': '獨資',
  '使用統一發票': 'N',
  '行業代號': '563115',
  '名稱': '手搖飲店',
  '行業代號1': '',
  '名稱1': '',
  '行業代號2': '',
  '名稱2': '',
  '行業代號3': '',
  '名稱3': '',
};

const _okMartOfficialFields = <String, String>{
  '營業地址': '新北市土城區中央路測試門市',
  '統一編號': '31655572',
  '總機構統一編號': '22853565',
  '營業人名稱': '富達零售股份有限公司晶技門市',
  '資本額': '0',
  '設立日期': '20120301',
  '組織別名稱': '本國公司設立之分公司',
  '使用統一發票': 'Y',
  '行業代號': '471112',
  '名稱': '直營連鎖式便利商店',
  '行業代號1': '',
  '名稱1': '',
  '行業代號2': '',
  '名稱2': '',
  '行業代號3': '',
  '名稱3': '',
};

const _benmiOfficialFields = <String, String>{
  '營業地址': '新北市土城區中央路測試營業所',
  '統一編號': '60282181',
  '總機構統一編號': '60769775',
  '營業人名稱': '本米股份有限公司土城中央路營業所',
  '資本額': '0',
  '設立日期': '20250101',
  '組織別名稱': '本國公司設立之分公司',
  '使用統一發票': 'Y',
  '行業代號': '561115',
  '名稱': '餐廳',
  '行業代號1': '',
  '名稱1': '',
  '行業代號2': '',
  '名稱2': '',
  '行業代號3': '',
  '名稱3': '',
};

const _unseenOfficialFields = <String, String>{
  '營業地址': '台北市測試區未知路7號',
  '統一編號': '77777777',
  '總機構統一編號': '',
  '營業人名稱': '官方稅籍實體',
  '資本額': '0',
  '設立日期': '20260901',
  '組織別名稱': '其他',
  '使用統一發票': 'Y',
  '行業代號': '999999',
  '名稱': '測試產業',
  '行業代號1': '',
  '名稱1': '',
  '行業代號2': '',
  '名稱2': '',
  '行業代號3': '',
  '名稱3': '',
};
