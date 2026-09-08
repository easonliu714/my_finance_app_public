import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v23.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/business_registry_validation_bootstrap.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('invoice review source has no registry network refresh dependency', () {
    final source = File(
      'lib/features/invoice/invoice_merchant_identity_review_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('BusinessRegistryAuthoritativeLookupService')));
    expect(source, isNot(contains('BusinessRegistryUpdateService')));
    expect(source, isNot(contains('refreshPort')));
    expect(source, contains('registryRepository.lookup(seller)'));
    expect(source, contains('normal invoice review performs local-only'));
  });

  test('OK Mart keeps consumer MerchantBrand separate from FIA legal name',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await createCanonicalProductionV23Tables(db);

    final registry = BusinessRegistryRepository(database: db);
    final identity = MerchantIdentityRepository(database: db);
    final entities = <BusinessRegistryEntity>[
      const BusinessRegistryEntity(
        sellerIdentifier: '31655572',
        entityType: BusinessRegistryEntityType.branch,
        legalName: '富達零售股份有限公司晶技門市',
        registrationStatus: 'active_tax_registration',
        parentSellerIdentifier: '22853565',
        sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      ),
    ];
    final pack = BusinessRegistryPack(
      version: 'fia-local-fixture-v1',
      sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      sourceDataDate: '2026-09-08',
      coverage: BusinessRegistryPack.nationwideCoverage,
      contentSha256: await computeBusinessRegistryPayloadSha256(entities),
      entities: entities,
    );
    expect((await registry.install(pack)).isSuccess, isTrue);

    final service = InvoiceMerchantIdentityReviewService(
      registryRepository: registry,
      identityRepository: identity,
      validationBootstrap: BusinessRegistryValidationBootstrap(
        repository: registry,
      ),
    );

    final beforeBinding = await service.resolve(
      sellerIdentifier: '31655572',
      sellerIdentifierAuthoritative: true,
      literalMerchantText: 'OK Mart 晶技門市',
    );
    expect(
      beforeBinding.decision.officialLegalNameSuggestion,
      '富達零售股份有限公司晶技門市',
    );
    expect(beforeBinding.decision.formalMerchantName, isEmpty);
    expect(beforeBinding.registryRefreshAttempted, isFalse);
    expect(beforeBinding.registryRefreshError, isEmpty);

    await service.confirmBinding(
      merchant: MerchantRecord(id: 'ok-mart', name: 'OK Mart'),
      sellerIdentifier: '31655572',
      literalMerchantText: 'OK Mart 晶技門市',
      evidenceSource: 'owner_confirmed_fixture',
      sourceReference: 'invoice/fixture',
    );

    final afterBinding = await service.resolve(
      sellerIdentifier: '31655572',
      sellerIdentifierAuthoritative: true,
      literalMerchantText: 'OK Mart 晶技門市',
    );
    expect(afterBinding.decision.formalMerchantName, 'OK Mart');
    expect(
      afterBinding.decision.officialLegalNameSuggestion,
      '富達零售股份有限公司晶技門市',
    );
    expect(afterBinding.registryRefreshAttempted, isFalse);
  });

  test('no installed registry remains non-blocking and local-only', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await createCanonicalProductionV23Tables(db);

    final registry = BusinessRegistryRepository(database: db);
    final service = InvoiceMerchantIdentityReviewService(
      registryRepository: registry,
      identityRepository: MerchantIdentityRepository(database: db),
      validationBootstrap: BusinessRegistryValidationBootstrap(
        repository: registry,
      ),
    );

    final result = await service.resolve(
      sellerIdentifier: '60282181',
      sellerIdentifierAuthoritative: true,
      literalMerchantText: '本米',
    );

    expect(result.registryStatus, BusinessRegistryLookupStatus.noInstalledRegistry);
    expect(result.hasOfficialLegalName, isFalse);
    expect(result.registryRefreshAttempted, isFalse);
    expect(result.registryRefreshError, isEmpty);
    expect(result.decision.formalMerchantName, isEmpty);
  });
}
