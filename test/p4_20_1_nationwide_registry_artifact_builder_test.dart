import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_artifact_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';

void main() {
  const entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: '12345678',
      entityType: BusinessRegistryEntityType.company,
      legalName: '範例股份有限公司',
      registrationStatus: '核准設立',
      sourceDataset: 'company_registry',
    ),
    BusinessRegistryEntity(
      sellerIdentifier: '22345678',
      entityType: BusinessRegistryEntityType.business,
      legalName: '範例商號',
      sourceDataset: 'business_registry',
    ),
    BusinessRegistryEntity(
      sellerIdentifier: '32345678',
      entityType: BusinessRegistryEntityType.branch,
      legalName: '範例股份有限公司分公司',
      parentSellerIdentifier: '12345678',
      sourceDataset: 'branch_registry',
    ),
  ];

  const metadata = BusinessRegistryNationwideBuildMetadata(
    registryVersion: 'tw-registry-2026-09-01',
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'company+business+branch',
    sourceDataDate: '2026-09-01',
  );

  test('nationwide builder emits reproducible bounded gzip artifact and manifest',
      () async {
    final directory = await Directory.systemTemp.createTemp('registry-artifact-');
    addTearDown(() => directory.delete(recursive: true));

    Stream<BusinessRegistryEntity> source() => Stream.fromIterable(entities);

    final firstOutput = File('${directory.path}/registry-a.ndjson.gz');
    final secondOutput = File('${directory.path}/registry-b.ndjson.gz');
    const builder = BusinessRegistryNationwideArtifactBuilder();

    final first = await builder.build(
      openSource: source,
      metadata: metadata,
      outputFile: firstOutput,
      downloadUri: Uri.parse(
        'https://github.com/easonliu714/my_finance_app_public/releases/download/p4.20.1/registry.ndjson.gz',
      ),
      attribution: '經濟部商業發展署 / GCIS 政府資料開放資料',
      licenseUri: Uri.parse('https://data.gov.tw/license'),
    );
    final second = await builder.build(
      openSource: source,
      metadata: metadata,
      outputFile: secondOutput,
      downloadUri: first.manifest.downloadUri,
      attribution: first.manifest.attribution,
      licenseUri: first.manifest.licenseUri,
    );

    expect(await firstOutput.readAsBytes(), await secondOutput.readAsBytes());
    expect(first.manifest.downloadSha256, second.manifest.downloadSha256);
    expect(
      first.manifest.registryContentSha256,
      second.manifest.registryContentSha256,
    );
    expect(first.manifest.entityCount, 3);
    expect(first.manifest.coverage, BusinessRegistryPack.nationwideCoverage);
    expect(first.manifest.format, BusinessRegistryDistributionFormat.gzipNdjsonV1);
    expect(first.manifest.validate().isValid, isTrue);

    final decoded = utf8.decode(
      gzip.decode(await firstOutput.readAsBytes()),
    );
    final lines = const LineSplitter().convert(decoded);
    expect(lines, hasLength(4));
    final header = Map<String, Object?>.from(jsonDecode(lines.first) as Map);
    expect(header['record_type'], 'header');
    expect(header['registry_version'], metadata.registryVersion);
    expect(header['entity_count'], 3);
    expect(
      header['registry_content_sha256'],
      first.manifest.registryContentSha256,
    );
    expect(decoded, isNot(contains('responsible_person')));
  });

  test('artifact build deletes partial files when second-pass source drifts',
      () async {
    final directory = await Directory.systemTemp.createTemp('registry-drift-');
    addTearDown(() => directory.delete(recursive: true));
    var pass = 0;
    Stream<BusinessRegistryEntity> source() {
      pass += 1;
      if (pass == 1) return Stream.fromIterable(entities);
      return Stream.fromIterable(<BusinessRegistryEntity>[
        entities[0],
        const BusinessRegistryEntity(
          sellerIdentifier: '22345678',
          entityType: BusinessRegistryEntityType.business,
          legalName: '第二遍被改寫的商號',
          sourceDataset: 'business_registry',
        ),
        entities[2],
      ]);
    }

    final output = File('${directory.path}/registry.ndjson.gz');
    await expectLater(
      const BusinessRegistryNationwideArtifactBuilder().build(
        openSource: source,
        metadata: metadata,
        outputFile: output,
        downloadUri: Uri.parse(
          'https://github.com/easonliu714/my_finance_app_public/releases/download/p4.20.1/registry.ndjson.gz',
        ),
        attribution: '經濟部商業發展署 / GCIS 政府資料開放資料',
        licenseUri: Uri.parse('https://data.gov.tw/license'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'REGISTRY_BUILDER_SECOND_PASS_SHA256_MISMATCH',
        ),
      ),
    );
    expect(await output.exists(), isFalse);
    expect(await File('${output.path}.partial').exists(), isFalse);
    expect(await File('${output.path}.ndjson.partial').exists(), isFalse);
  });
}
