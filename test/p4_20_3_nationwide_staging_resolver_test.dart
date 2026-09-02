import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_fia_tax_registration_adapter.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_staging_resolver.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';

void main() {
  const resolver = BusinessRegistryNationwideStagingResolver();

  BusinessRegistryNationwideInvoiceSellerSeed seed({
    required String seller,
    required String name,
    String parent = '',
    String organization = '',
  }) => BusinessRegistryNationwideInvoiceSellerSeed(
        sellerIdentifier: seller,
        legalName: name,
        parentSellerIdentifier: parent,
        organizationType: organization,
        usesUniformInvoice: 'Y',
        sourceDataset: BusinessRegistryFiaTaxRegistrationAdapter.sourceDataset,
      );

  BusinessRegistryEntity entity({
    required String seller,
    required BusinessRegistryEntityType type,
    required String name,
    String parent = '',
    String source = 'GCIS_TEST',
  }) => BusinessRegistryEntity(
        sellerIdentifier: seller,
        entityType: type,
        legalName: name,
        parentSellerIdentifier: parent,
        sourceDataset: source,
      );

  test('FIA head-office linkage is deterministic branch evidence', () {
    final decision = resolver.stage(
      seed(
        seller: '60282181',
        name: '本米股份有限公司土城中央路營業所',
        parent: '60769775',
        organization: '其他',
      ),
    );
    expect(decision.status, BusinessRegistryNationwideStagingStatus.branchReadyFromFiaParent);
    expect(decision.entity?.entityType, BusinessRegistryEntityType.branch);
    expect(decision.entity?.parentSellerIdentifier, '60769775');
    expect(decision.entity?.legalName, '本米股份有限公司土城中央路營業所');
  });

  test('parentless FIA row is not guessed from organization/display text', () {
    final decision = resolver.stage(seed(seller: '30340553', name: '一品現泡茶店', organization: '獨資'));
    expect(decision.status, BusinessRegistryNationwideStagingStatus.needsLegalTypeEnrichment);
    expect(decision.entity, isNull);
  });

  test('single company/business legal enrichment resolves parentless row', () {
    final source = seed(seller: '30340553', name: '一品現泡茶店', organization: '獨資');
    final decision = resolver.resolveWithLegalEnrichment(seed: source, candidates: <BusinessRegistryEntity>[
      entity(seller: '30340553', type: BusinessRegistryEntityType.business, name: '一品現泡茶店', source: 'GCIS_BUSINESS'),
    ]);
    expect(decision.status, BusinessRegistryNationwideStagingStatus.resolvedWithLegalEnrichment);
    expect(decision.entity?.entityType, BusinessRegistryEntityType.business);
    expect(decision.entity?.sourceDataset, contains('MOF_FIA_BGMOPEN1'));
    expect(decision.entity?.sourceDataset, contains('GCIS_BUSINESS'));
  });

  test('identical duplicate legal enrichment rows collapse deterministically', () {
    final source = seed(seller: '30340553', name: '一品現泡茶店');
    final duplicate = entity(seller: '30340553', type: BusinessRegistryEntityType.business, name: '一品現泡茶店', source: 'GCIS_BUSINESS');
    final decision = resolver.resolveWithLegalEnrichment(seed: source, candidates: <BusinessRegistryEntity>[duplicate, duplicate]);
    expect(decision.status, BusinessRegistryNationwideStagingStatus.resolvedWithLegalEnrichment);
    expect(decision.entity?.entityType, BusinessRegistryEntityType.business);
  });

  test('company/business ambiguity fails closed', () {
    final source = seed(seller: '12345675', name: 'ambiguous');
    final decision = resolver.resolveWithLegalEnrichment(seed: source, candidates: <BusinessRegistryEntity>[
      entity(seller: '12345675', type: BusinessRegistryEntityType.company, name: 'A'),
      entity(seller: '12345675', type: BusinessRegistryEntityType.business, name: 'B'),
    ]);
    expect(decision.status, BusinessRegistryNationwideStagingStatus.holdConflict);
    expect(decision.entity, isNull);
  });

  test('FIA vs GCIS branch parent mismatch fails closed', () {
    final source = seed(seller: '60282181', name: '本米股份有限公司土城中央路營業所', parent: '60769775');
    final decision = resolver.resolveWithLegalEnrichment(seed: source, candidates: <BusinessRegistryEntity>[
      entity(seller: '60282181', type: BusinessRegistryEntityType.branch, name: '本米股份有限公司土城中央路營業所', parent: '11111111'),
    ]);
    expect(decision.status, BusinessRegistryNationwideStagingStatus.holdConflict);
    expect(decision.reason, 'gcis_branch_parent_conflicts_with_fia_parent');
  });

  test('identical duplicate branch enrichment rows collapse deterministically', () {
    final source = seed(seller: '31655572', name: '富達零售股份有限公司晶技門市', parent: '22853565');
    final duplicate = entity(seller: '31655572', type: BusinessRegistryEntityType.branch, name: '富達零售股份有限公司晶技門市', parent: '22853565', source: 'GCIS_BRANCH');
    final decision = resolver.resolveWithLegalEnrichment(seed: source, candidates: <BusinessRegistryEntity>[duplicate, duplicate]);
    expect(decision.isReady, isTrue);
    expect(decision.entity?.parentSellerIdentifier, '22853565');
  });

  test('FIA branch and matching GCIS branch preserve parent and enrich name', () {
    final source = seed(seller: '31655572', name: '富達零售股份有限公司晶技門市', parent: '22853565');
    final decision = resolver.resolveWithLegalEnrichment(seed: source, candidates: <BusinessRegistryEntity>[
      entity(seller: '31655572', type: BusinessRegistryEntityType.branch, name: '富達零售股份有限公司晶技門市', parent: '22853565', source: 'GCIS_BRANCH'),
    ]);
    expect(decision.isReady, isTrue);
    expect(decision.entity?.entityType, BusinessRegistryEntityType.branch);
    expect(decision.entity?.parentSellerIdentifier, '22853565');
    expect(decision.entity?.sourceDataset, contains('GCIS_BRANCH'));
  });
}
