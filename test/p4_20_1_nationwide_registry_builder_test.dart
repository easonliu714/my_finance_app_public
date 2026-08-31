import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';

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
}
