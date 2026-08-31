import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_stream_pack.dart';

void main() {
  test('production manifest accepts bounded nationwide gzip NDJSON release asset', () {
    final manifest = _manifest();
    final validation = manifest.validate();

    expect(validation.isValid, isTrue, reason: validation.errors.join(','));
    expect(manifest.coverage, BusinessRegistryPack.nationwideCoverage);
    expect(
      manifest.format,
      BusinessRegistryDistributionFormat.gzipNdjsonV1,
    );
  });

  test('production distribution rejects validation subset and direct GCIS handset download', () {
    final subset = _manifest(
      coverage: BusinessRegistryPack.validationSubsetCoverage,
    ).validate();
    expect(subset.isValid, isFalse);
    expect(
      subset.errors,
      contains('REGISTRY_DISTRIBUTION_MUST_BE_NATIONWIDE'),
    );

    final directGcis = _manifest(
      downloadUrl: 'https://data.gcis.nat.gov.tw/od/data/api/example',
    ).validate();
    expect(directGcis.isValid, isFalse);
    expect(
      directGcis.errors,
      contains('REGISTRY_DISTRIBUTION_DOWNLOAD_URL_NOT_ALLOWED'),
    );
  });

  test('production distribution rejects unbounded or untrusted release payloads', () {
    final oversized = _manifest(
      compressedSizeBytes:
          BusinessRegistryDistributionManifest.maxCompressedSizeBytes + 1,
    ).validate();
    expect(
      oversized.errors,
      contains('REGISTRY_DISTRIBUTION_COMPRESSED_SIZE_INVALID'),
    );

    final wrongOwner = _manifest(
      downloadUrl:
          'https://github.com/someone/other/releases/download/v1/registry.jsonl.gz',
    ).validate();
    expect(
      wrongOwner.errors,
      contains('REGISTRY_DISTRIBUTION_GITHUB_PATH_NOT_ALLOWED'),
    );
  });

  test('stream header must exactly bind nationwide manifest identity', () {
    final manifest = _manifest();
    const parser = BusinessRegistryStreamPackParser();
    final record = parser.parseLine('''
{"record_type":"header","registry_version":"tw-gcis-20260830-v1","source_authority":"MOEA_BUSINESS_ADMINISTRATION_GCIS","source_dataset":"GCIS company/business/branch canonical pack","source_data_date":"2026-08-30","coverage":"taiwan_nationwide","entity_count":1234567,"registry_content_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
''');

    expect(record, isA<BusinessRegistryStreamHeaderRecord>());
    final header = (record as BusinessRegistryStreamHeaderRecord).header;
    expect(header.validateAgainst(manifest), isEmpty);
  });

  test('stream header mismatch fails closed before installation', () {
    final manifest = _manifest();
    const parser = BusinessRegistryStreamPackParser();
    final record = parser.parseLine('''
{"record_type":"header","registry_version":"tw-gcis-OLD","source_authority":"MOEA_BUSINESS_ADMINISTRATION_GCIS","source_dataset":"GCIS company/business/branch canonical pack","source_data_date":"2026-08-30","coverage":"taiwan_nationwide","entity_count":1234567,"registry_content_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
''') as BusinessRegistryStreamHeaderRecord;

    expect(
      record.header.validateAgainst(manifest),
      contains('REGISTRY_STREAM_VERSION_MISMATCH'),
    );
  });

  test('entity records retain company business branch identity without personal fields', () {
    const parser = BusinessRegistryStreamPackParser();
    final company = parser.parseLine('''
{"record_type":"entity","seller_identifier":"30340553","entity_type":"business","legal_name":"一品現泡茶店","registration_status":"核准設立","parent_seller_identifier":"","source_dataset":"GCIS business registration"}
''');

    expect(company, isA<BusinessRegistryStreamEntityRecord>());
    final entity = (company as BusinessRegistryStreamEntityRecord).entity;
    expect(entity.sellerIdentifier, '30340553');
    expect(entity.entityType, BusinessRegistryEntityType.business);
    expect(entity.legalName, '一品現泡茶店');
    expect(parser.validateEntity(entity), isEmpty);
  });
}

BusinessRegistryDistributionManifest _manifest({
  String coverage = BusinessRegistryPack.nationwideCoverage,
  String downloadUrl =
      'https://github.com/easonliu714/my_finance_app_public/releases/download/business-registry-v1/tw-gcis-20260830-v1.jsonl.gz',
  int compressedSizeBytes = 64 * 1024 * 1024,
}) {
  return BusinessRegistryDistributionManifest(
    schemaVersion: 1,
    registryVersion: 'tw-gcis-20260830-v1',
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'GCIS company/business/branch canonical pack',
    sourceDataDate: '2026-08-30',
    coverage: coverage,
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: 1234567,
    downloadUri: Uri.parse(downloadUrl),
    downloadSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    registryContentSha256:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    compressedSizeBytes: compressedSizeBytes,
    uncompressedSizeBytes: 256 * 1024 * 1024,
    attribution: '資料提供機關／經濟部商業發展署',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
}
