import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/database/production_schema_v24.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest_codec.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/business_registry_update_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
      'P4.20.3-r1 upgrades an installed P4.20.1 validation subset to nationwide',
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
    await createCanonicalProductionV24Tables(db);

    final repository = BusinessRegistryRepository(database: db);
    final legacy = await _legacyValidationSubset();
    expect((await repository.install(legacy)).isSuccess, isTrue);

    final before = await repository.installedSnapshot();
    expect(before?.version, 'p4-20-1-canary-fixture');
    expect(before?.sourceDataDate, '2025-06-02');
    expect(before?.coverage, BusinessRegistryPack.validationSubsetCoverage);
    expect((await repository.lookup('31655572')).isHit, isFalse);

    final tempDir = await Directory.systemTemp.createTemp(
      'p4_20_3_subset_upgrade_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final release = await _nationwideReleaseFixture();
    final manifestUri = Uri.parse(
      BusinessRegistryUpdateConfiguration.productionManifestUrl,
    );
    final client = _RouteClient(<String, List<int>>{
      manifestUri.toString():
          utf8.encode(release.manifest.toCanonicalJsonText()),
      release.manifest.downloadUri.toString(): release.compressedBytes,
    });

    final service = BusinessRegistryUpdateService(
      database: db,
      client: client,
      tempDirectoryProvider: () async => tempDir,
    );

    expect(service.isDistributionConfigured, isTrue);
    final result = await service.update();

    expect(result.status, BusinessRegistryUpdateStatus.updated);
    expect(result.snapshot?.version, '2026-09-07-fia-nationwide');
    expect(result.snapshot?.sourceDataDate, '2026-09-07');
    expect(result.snapshot?.coverage, BusinessRegistryPack.nationwideCoverage);
    expect(client.requestCount(manifestUri), 1);
    expect(client.requestCount(release.manifest.downloadUri), 1);

    final official = await repository.lookup('31655572');
    expect(official.isHit, isTrue);
    expect(official.primaryEntity?.legalName, '富達零售股份有限公司晶技門市');

    final details = await repository.lookupOfficialDetail('31655572');
    expect(details.isHit, isTrue);
    expect(details.fields, hasLength(16));
    expect(details.fields['統一編號'], '31655572');
    expect(details.fields['營業人名稱'], '富達零售股份有限公司晶技門市');

    final removedLegacy = await repository.lookup('99990001');
    expect(removedLegacy.isHit, isFalse);
  });
}

Future<BusinessRegistryPack> _legacyValidationSubset() async {
  const entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: '99990001',
      entityType: BusinessRegistryEntityType.company,
      legalName: 'P4.20.1 validation subset fixture',
      registrationStatus: 'active_tax_registration',
      sourceDataset: 'p4_20_1_signed_canary_subset',
    ),
  ];
  return BusinessRegistryPack(
    version: 'p4-20-1-canary-fixture',
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'p4_20_1_signed_canary_subset',
    sourceDataDate: '2025-06-02',
    coverage: BusinessRegistryPack.validationSubsetCoverage,
    contentSha256: await computeBusinessRegistryPayloadSha256(entities),
    entities: entities,
  );
}

Future<_ReleaseFixture> _nationwideReleaseFixture() async {
  const details = <String, String>{
    '營業地址': '新北市土城區中央路測試門市',
    '統一編號': '31655572',
    '總機構統一編號': '22853565',
    '營業人名稱': '富達零售股份有限公司晶技門市',
    '資本額': '0',
    '設立日期': '20120301',
    '組織別名稱': '其他',
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
  const entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: '31655572',
      entityType: BusinessRegistryEntityType.branch,
      legalName: '富達零售股份有限公司晶技門市',
      registrationStatus: 'active_tax_registration',
      parentSellerIdentifier: '22853565',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      officialFields: details,
    ),
  ];

  final entityLines = entities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .join();
  final contentSha = await _sha256(utf8.encode(entityLines));
  final headerLine = '${jsonEncode(<String, Object?>{
    'record_type': 'header',
    'registry_version': '2026-09-07-fia-nationwide',
    'source_authority': 'MOF_FIA_ACTIVE_TAX_REGISTRY',
    'source_dataset': 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    'source_data_date': '2026-09-07',
    'coverage': BusinessRegistryPack.nationwideCoverage,
    'entity_count': entities.length,
    'registry_content_sha256': contentSha,
  })}\n';
  final uncompressedBytes = utf8.encode('$headerLine$entityLines');
  final compressedBytes = gzip.encode(uncompressedBytes);
  final downloadSha = await _sha256(compressedBytes);
  final manifest = BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: '2026-09-07-fia-nationwide',
    sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
    sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    sourceDataDate: '2026-09-07',
    coverage: BusinessRegistryPack.nationwideCoverage,
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: entities.length,
    downloadUri: Uri.parse(
      'https://github.com/easonliu714/my_finance_app_public/releases/download/'
      'p4.20.3-registry/fixture.registry.gz',
    ),
    downloadSha256: downloadSha,
    registryContentSha256: contentSha,
    compressedSizeBytes: compressedBytes.length,
    uncompressedSizeBytes: uncompressedBytes.length,
    attribution: '財政部財政資訊中心',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
  return _ReleaseFixture(
    manifest: manifest,
    compressedBytes: compressedBytes,
  );
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class _ReleaseFixture {
  const _ReleaseFixture({
    required this.manifest,
    required this.compressedBytes,
  });

  final BusinessRegistryDistributionManifest manifest;
  final List<int> compressedBytes;
}

class _RouteClient extends http.BaseClient {
  _RouteClient(this.routes);

  final Map<String, List<int>> routes;
  final Map<String, int> _counts = <String, int>{};

  int requestCount(Uri uri) => _counts[uri.toString()] ?? 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.toString();
    _counts[key] = (_counts[key] ?? 0) + 1;
    final bytes = routes[key];
    if (bytes == null) {
      throw StateError('UNEXPECTED_HTTP_REQUEST:$key');
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      HttpStatus.ok,
      contentLength: bytes.length,
      request: request,
    );
  }
}
