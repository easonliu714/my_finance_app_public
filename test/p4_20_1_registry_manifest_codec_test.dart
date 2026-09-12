import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest_codec.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';

void main() {
  test('nationwide manifest canonical JSON is byte-stable and round-trips', () {
    final manifest = BusinessRegistryDistributionManifest(
      schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
      registryVersion: ' tw-gcis-20260901-v1 ',
      sourceAuthority: ' MOEA_BUSINESS_ADMINISTRATION_GCIS ',
      sourceDataset: ' company+business+branch ',
      sourceDataDate: ' 2026-09-01 ',
      coverage: BusinessRegistryPack.nationwideCoverage,
      format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
      entityCount: 1234567,
      downloadUri: Uri.parse(
        'https://github.com/easonliu714/my_finance_app_public/releases/download/p4.20.1/registry.ndjson.gz',
      ),
      downloadSha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      registryContentSha256:
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      compressedSizeBytes: 64 * 1024 * 1024,
      uncompressedSizeBytes: 256 * 1024 * 1024,
      attribution: ' 經濟部商業發展署 / GCIS ',
      licenseUri: Uri.parse('https://data.gov.tw/license'),
    );

    final first = manifest.toCanonicalJsonText();
    final second = manifest.toCanonicalJsonText();
    expect(first, second);
    expect(first, startsWith('{"schema_version":1,"registry_version":'));
    expect(first, contains('"download_sha256":"aaaaaaaa'));
    expect(first, contains('"registry_content_sha256":"bbbbbbbb'));

    final decoded = BusinessRegistryDistributionManifest.fromJsonText(first);
    expect(decoded.validate().isValid, isTrue);
    expect(decoded.registryVersion, 'tw-gcis-20260901-v1');
    expect(decoded.sourceAuthority, 'MOEA_BUSINESS_ADMINISTRATION_GCIS');
    expect(decoded.sourceDataset, 'company+business+branch');
    expect(decoded.sourceDataDate, '2026-09-01');
    expect(decoded.attribution, '經濟部商業發展署 / GCIS');
    expect(decoded.downloadSha256, 'a' * 64);
    expect(decoded.registryContentSha256, 'b' * 64);
  });
}
