import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_stream_pack.dart';

void main() {
  const company = BusinessRegistryEntity(
    sellerIdentifier: '12345678',
    entityType: BusinessRegistryEntityType.company,
    legalName: '  範例股份有限公司  ',
    registrationStatus: ' 核准設立 ',
    sourceDataset: 'company_registry',
  );
  const business = BusinessRegistryEntity(
    sellerIdentifier: '22345678',
    entityType: BusinessRegistryEntityType.business,
    legalName: '範例商號',
    sourceDataset: 'business_registry',
  );
  const branch = BusinessRegistryEntity(
    sellerIdentifier: '32345678',
    entityType: BusinessRegistryEntityType.branch,
    legalName: '範例股份有限公司分公司',
    parentSellerIdentifier: '12345678',
    sourceDataset: 'branch_registry',
  );

  test('two deterministic streaming passes produce identical payload hash', () async {
    final first = BusinessRegistryNationwideBuildPass();
    final firstLines = <String>[
      first.add(company),
      first.add(business),
      first.add(branch),
    ];
    final firstSummary = await first.close();

    final second = BusinessRegistryNationwideBuildPass();
    final secondLines = <String>[
      second.add(company),
      second.add(business),
      second.add(branch),
    ];
    final secondSummary = await second.close();

    expect(firstLines, secondLines);
    expect(firstSummary.entityCount, 3);
    expect(secondSummary.entityCount, 3);
    expect(
      firstSummary.registryContentSha256,
      secondSummary.registryContentSha256,
    );
    expect(
      firstSummary.registryContentSha256,
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
    expect(firstLines.first, contains('"legal_name":"範例股份有限公司"'));
    expect(firstLines.first, isNot(contains('  範例股份有限公司  ')));
  });

  test('nationwide build rejects unsorted input instead of buffering it', () {
    final builder = BusinessRegistryNationwideBuildPass();
    builder.add(business);
    expect(
      () => builder.add(company),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'REGISTRY_BUILDER_INPUT_NOT_SORTED',
        ),
      ),
    );
  });

  test('nationwide build rejects duplicate seller/type identity', () {
    final builder = BusinessRegistryNationwideBuildPass();
    builder.add(company);
    expect(
      () => builder.add(company),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'REGISTRY_BUILDER_DUPLICATE_ENTITY_KEY',
        ),
      ),
    );
  });

  test('canonical mobile entity line excludes responsible-person fields', () {
    final line = BusinessRegistryNationwideBuildPass.canonicalEntityLine(company);
    expect(line, contains('"record_type":"entity"'));
    expect(line, contains('"entity_type":"company"'));
    expect(line, isNot(contains('responsible_person')));
    expect(line, isNot(contains('representative')));
  });

  test('source evidence is validated fail-closed', () {
    const invalid = BusinessRegistryEntity(
      sellerIdentifier: '123',
      entityType: BusinessRegistryEntityType.company,
      legalName: '',
      sourceDataset: '',
      parentSellerIdentifier: 'abc',
    );
    expect(
      BusinessRegistryNationwideBuildPass.validateEntity(invalid),
      containsAll(<String>[
        'REGISTRY_BUILDER_SELLER_IDENTIFIER_INVALID',
        'REGISTRY_BUILDER_LEGAL_NAME_REQUIRED',
        'REGISTRY_BUILDER_SOURCE_DATASET_REQUIRED',
        'REGISTRY_BUILDER_PARENT_IDENTIFIER_INVALID',
      ]),
    );
  });

  test('second pass emits deterministic nationwide provenance header', () async {
    final first = BusinessRegistryNationwideBuildPass();
    first.add(company);
    first.add(business);
    first.add(branch);
    final summary = await first.close();

    const metadata = BusinessRegistryNationwideBuildMetadata(
      registryVersion: 'tw-registry-2026-08-31',
      sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS_PUBLIC_REPORT',
      sourceDataset: 'company+business+branch',
      sourceDataDate: '2026-08-31',
    );
    final emitter = BusinessRegistryNationwideEmitPass(
      metadata: metadata,
      expectedSummary: summary,
    );
    final headerJson = Map<String, Object?>.from(
      jsonDecode(emitter.headerLine) as Map,
    );

    expect(headerJson['record_type'], 'header');
    expect(headerJson['registry_version'], 'tw-registry-2026-08-31');
    expect(headerJson['coverage'], BusinessRegistryPack.nationwideCoverage);
    expect(headerJson['entity_count'], 3);
    expect(headerJson['registry_content_sha256'], summary.registryContentSha256);

    final parsed = const BusinessRegistryStreamPackParser()
        .parseLine(emitter.headerLine) as BusinessRegistryStreamHeaderRecord;
    expect(parsed.header.entityCount, 3);
    expect(parsed.header.registryContentSha256, summary.registryContentSha256);

    emitter.add(company);
    emitter.add(business);
    emitter.add(branch);
    final emittedSummary = await emitter.close();
    expect(emittedSummary.entityCount, summary.entityCount);
    expect(
      emittedSummary.registryContentSha256,
      summary.registryContentSha256,
    );
  });

  test('second pass fails closed when source changes after first pass', () async {
    final first = BusinessRegistryNationwideBuildPass();
    first.add(company);
    first.add(business);
    final summary = await first.close();

    final emitter = BusinessRegistryNationwideEmitPass(
      metadata: const BusinessRegistryNationwideBuildMetadata(
        registryVersion: 'tw-registry-2026-08-31',
        sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
        sourceDataset: 'company+business',
        sourceDataDate: '2026-08-31',
      ),
      expectedSummary: summary,
    );
    emitter.add(company);
    emitter.add(
      const BusinessRegistryEntity(
        sellerIdentifier: '22345678',
        entityType: BusinessRegistryEntityType.business,
        legalName: '已變更商號',
        sourceDataset: 'business_registry',
      ),
    );

    await expectLater(
      emitter.close(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'REGISTRY_BUILDER_SECOND_PASS_SHA256_MISMATCH',
        ),
      ),
    );
  });

  test('second pass rejects non-nationwide or incomplete provenance', () {
    expect(
      () => BusinessRegistryNationwideEmitPass(
        metadata: const BusinessRegistryNationwideBuildMetadata(
          registryVersion: '',
          sourceAuthority: 'UNKNOWN',
          sourceDataset: '',
          sourceDataDate: 'not-a-date',
          coverage: BusinessRegistryPack.validationSubsetCoverage,
        ),
        expectedSummary: const BusinessRegistryNationwideBuildSummary(
          entityCount: 1,
          registryContentSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
