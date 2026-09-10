import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_bounded_downloader.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_stream_validator.dart';

void main() {
  test(
    'SHA stream validation guarantees cooperative cadence with monotonic progress',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'p4_20_4_validation_resume_',
      );
      try {
        final fixture = await _writeLargeFixture(tempDir);
        final progress = <BusinessRegistryValidationProgress>[];
        var cooperativeYieldCalls = 0;
        final validator = BusinessRegistryStreamValidator(
          cooperativeYield: () async {
            cooperativeYieldCalls += 1;
            await Future<void>.delayed(Duration.zero);
          },
        );

        final result = await validator.validate(
          manifest: fixture.manifest,
          artifact: fixture.artifact,
          onProgress: progress.add,
        );

        expect(result.entityCount, 5000);
        expect(result.registryContentSha256, fixture.manifest.registryContentSha256);
        // 5000 entities cross exactly one 4096-entity cooperative-yield boundary.
        expect(cooperativeYieldCalls, 1);
        expect(progress, isNotEmpty);
        for (var index = 1; index < progress.length; index += 1) {
          expect(
            progress[index].processedBytes,
            greaterThanOrEqualTo(progress[index - 1].processedBytes),
          );
          expect(progress[index].eta?.isNegative ?? false, isFalse);
        }
        expect(progress.last.fraction, 1.0);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}

Future<_Fixture> _writeLargeFixture(Directory tempDir) async {
  final entities = List<BusinessRegistryEntity>.generate(
    5000,
    (index) => BusinessRegistryEntity(
      sellerIdentifier: (10000000 + index).toString(),
      entityType: BusinessRegistryEntityType.business,
      legalName: '測試商家 $index',
      registrationStatus: '核准設立',
      parentSellerIdentifier: '',
      sourceDataset: 'nationwide_company_business_branch',
    ),
  );
  final entityPayload = entities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .join();
  final contentSha = await _sha256(utf8.encode(entityPayload));
  final headerLine = '${jsonEncode(<String, Object?>{
    'record_type': 'header',
    'registry_version': 'p4.20.4-resume-fixture',
    'source_authority': 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    'source_dataset': 'nationwide_company_business_branch',
    'source_data_date': '2026-09-10',
    'coverage': 'taiwan_nationwide',
    'entity_count': entities.length,
    'registry_content_sha256': contentSha,
  })}\n';
  final uncompressedBytes = utf8.encode('$headerLine$entityPayload');
  final compressedBytes = gzip.encode(uncompressedBytes);
  final downloadSha = await _sha256(compressedBytes);
  final file = File('${tempDir.path}/registry.gz.partial');
  await file.writeAsBytes(compressedBytes, flush: true);

  final manifest = BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: 'p4.20.4-resume-fixture',
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'nationwide_company_business_branch',
    sourceDataDate: '2026-09-10',
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
    attribution: 'fixture',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );

  return _Fixture(
    manifest: manifest,
    artifact: BusinessRegistryDownloadedArtifact(
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

class _Fixture {
  const _Fixture({required this.manifest, required this.artifact});

  final BusinessRegistryDistributionManifest manifest;
  final BusinessRegistryDownloadedArtifact artifact;
}
