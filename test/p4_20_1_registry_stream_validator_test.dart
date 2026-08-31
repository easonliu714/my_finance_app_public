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
  group('P4.20.1-C gzip registry stream validator', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('p4_20_1_validate_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('validates header, canonical entities, sizes, and content SHA', () async {
      final fixture = await _writeFixture(tempDir: tempDir);

      final result = await const BusinessRegistryStreamValidator().validate(
        manifest: fixture.manifest,
        artifact: fixture.artifact,
      );

      expect(result.entityCount, 2);
      expect(result.compressedSizeBytes, fixture.compressedBytes.length);
      expect(result.uncompressedSizeBytes, fixture.uncompressedBytes.length);
      expect(result.downloadSha256, fixture.manifest.downloadSha256);
      expect(
        result.registryContentSha256,
        fixture.manifest.registryContentSha256,
      );
      expect(await result.file.exists(), isTrue);
    });

    test('fails closed on manifest content SHA mismatch and deletes candidate',
        () async {
      final fixture = await _writeFixture(
        tempDir: tempDir,
        manifestContentShaOverride: '0' * 64,
      );

      await expectLater(
        const BusinessRegistryStreamValidator().validate(
          manifest: fixture.manifest,
          artifact: fixture.artifact,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_VALIDATE_CONTENT_SHA256_MISMATCH',
          ),
        ),
      );
      expect(await fixture.artifact.file.exists(), isFalse);
    });

    test('fails closed on entity order drift and deletes candidate', () async {
      final fixture = await _writeFixture(tempDir: tempDir, reverseEntities: true);

      await expectLater(
        const BusinessRegistryStreamValidator().validate(
          manifest: fixture.manifest,
          artifact: fixture.artifact,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_VALIDATE_ENTITY_NOT_SORTED',
          ),
        ),
      );
      expect(await fixture.artifact.file.exists(), isFalse);
    });
  });
}

Future<_Fixture> _writeFixture({
  required Directory tempDir,
  String? manifestContentShaOverride,
  bool reverseEntities = false,
}) async {
  final entities = <BusinessRegistryEntity>[
    const BusinessRegistryEntity(
      sellerIdentifier: '12345678',
      entityType: BusinessRegistryEntityType.company,
      legalName: '甲公司',
      registrationStatus: '核准設立',
      parentSellerIdentifier: '',
      sourceDataset: 'nationwide_company_business_branch',
    ),
    const BusinessRegistryEntity(
      sellerIdentifier: '87654321',
      entityType: BusinessRegistryEntityType.business,
      legalName: '乙商號',
      registrationStatus: '核准設立',
      parentSellerIdentifier: '',
      sourceDataset: 'nationwide_company_business_branch',
    ),
  ];
  final emittedEntities = reverseEntities ? entities.reversed.toList() : entities;
  final canonicalEntityLines = emittedEntities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .toList(growable: false);

  final authorityEntityLines = entities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .join();
  final contentSha = await _sha256(utf8.encode(authorityEntityLines));
  final manifestContentSha = manifestContentShaOverride ?? contentSha;

  final headerLine = '${jsonEncode(<String, Object?>{
    'record_type': 'header',
    'registry_version': '2026-09-01',
    'source_authority': 'MOEA_GCIS',
    'source_dataset': 'nationwide_company_business_branch',
    'source_data_date': '2026-09-01',
    'coverage': 'nationwide',
    'entity_count': entities.length,
    'registry_content_sha256': manifestContentSha,
  })}\n';
  final uncompressedBytes = utf8.encode('$headerLine${canonicalEntityLines.join()}');
  final compressedBytes = gzip.encode(uncompressedBytes);
  final downloadSha = await _sha256(compressedBytes);

  final file = File('${tempDir.path}/registry.gz.partial');
  await file.writeAsBytes(compressedBytes, flush: true);

  final manifest = BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: '2026-09-01',
    sourceAuthority: 'MOEA_GCIS',
    sourceDataset: 'nationwide_company_business_branch',
    sourceDataDate: '2026-09-01',
    coverage: 'nationwide',
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: entities.length,
    downloadUri: Uri.parse(
      'https://github.com/easonliu714/my_finance_app_public/releases/download/registry-v1/registry.gz',
    ),
    downloadSha256: downloadSha,
    registryContentSha256: manifestContentSha,
    compressedSizeBytes: compressedBytes.length,
    uncompressedSizeBytes: uncompressedBytes.length,
    attribution: '經濟部商業發展署 / data.gov.tw',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );

  return _Fixture(
    manifest: manifest,
    artifact: BusinessRegistryDownloadedArtifact(
      file: file,
      sizeBytes: compressedBytes.length,
      sha256: downloadSha,
    ),
    compressedBytes: compressedBytes,
    uncompressedBytes: uncompressedBytes,
  );
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class _Fixture {
  const _Fixture({
    required this.manifest,
    required this.artifact,
    required this.compressedBytes,
    required this.uncompressedBytes,
  });

  final BusinessRegistryDistributionManifest manifest;
  final BusinessRegistryDownloadedArtifact artifact;
  final List<int> compressedBytes;
  final List<int> uncompressedBytes;
}
