import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_fia_tax_registration_adapter.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_source_authority.dart';

void main() {
  group('P4.20.3 nationwide official source authority', () {
    test('uses exactly one replayable nationwide bulk coverage spine', () {
      expect(BusinessRegistryNationwideSourceAuthority.validate(), isEmpty);

      final spines = BusinessRegistryNationwideSourceAuthority.sources
          .where(
            (source) =>
                source.role ==
                BusinessRegistryNationwideSourceRole.invoiceSellerCoverageSpine,
          )
          .toList(growable: false);
      expect(spines, hasLength(1));
      expect(spines.single.bulkAcquisition, isTrue);
      expect(spines.single.provider, '財政部財政資訊中心');
      expect(
        spines.single.acquisitionUri.toString(),
        'https://eip.fia.gov.tw/data/BGMOPEN1.zip',
      );
      expect(spines.single.updateCadence, 'daily');
    });

    test('GCIS company business branch sources are enrichment, not bulk', () {
      final enrichment = BusinessRegistryNationwideSourceAuthority.sources
          .where(
            (source) =>
                source.role !=
                BusinessRegistryNationwideSourceRole.invoiceSellerCoverageSpine,
          )
          .toList(growable: false);
      expect(enrichment, hasLength(3));
      expect(enrichment.every((source) => !source.bulkAcquisition), isTrue);
      expect(
        enrichment.map((source) => source.role).toSet(),
        <BusinessRegistryNationwideSourceRole>{
          BusinessRegistryNationwideSourceRole.gcisCompanyEnrichment,
          BusinessRegistryNationwideSourceRole.gcisBusinessEnrichment,
          BusinessRegistryNationwideSourceRole.gcisBranchEnrichment,
        },
      );
    });

    test('mobile projections exclude responsible-person fields', () {
      for (final source in BusinessRegistryNationwideSourceAuthority.sources) {
        expect(
          source.mobileProjectionFields.intersection(
            BusinessRegistryNationwideOfficialSource.prohibitedMobileFields,
          ),
          isEmpty,
        );
      }
    });
  });

  group('P4.20.3 FIA nationwide tax-registration adapter', () {
    const adapter = BusinessRegistryFiaTaxRegistrationAdapter();

    test('requires exact official coverage-spine columns', () {
      expect(
        adapter.validateHeader(const <String>[
          '統一編號',
          '總機構統一編號',
          '營業人名稱',
          '組織別名稱',
          '使用統一發票',
          '營業地址',
        ]),
        isEmpty,
      );
      expect(
        adapter.validateHeader(const <String>['統一編號', '營業人名稱']),
        contains('FIA_TAX_REGISTRY_REQUIRED_COLUMN_MISSING:總機構統一編號'),
      );
    });

    test('projects a privacy-reduced invoice seller seed', () {
      final seed = adapter.parseRow(const <String, String>{
        '統一編號': '12345675',
        '總機構統一編號': '87654321',
        '營業人名稱': '測試分支營業所',
        '組織別名稱': '本國公司設立之分公司',
        '使用統一發票': 'Y',
        '營業地址': '不投影到目前 mobile registry entity',
        '負責人姓名': '不得投影',
      });

      expect(seed.sellerIdentifier, '12345675');
      expect(seed.parentSellerIdentifier, '87654321');
      expect(seed.legalName, '測試分支營業所');
      expect(seed.hasParent, isTrue);
      expect(
        seed.sourceDataset,
        BusinessRegistryFiaTaxRegistrationAdapter.sourceDataset,
      );
    });

    test('fails closed on invalid identity and parent self-reference', () {
      expect(
        () => adapter.parseRow(const <String, String>{
          '統一編號': '1234',
          '營業人名稱': 'bad',
        }),
        throwsFormatException,
      );
      expect(
        () => adapter.parseRow(const <String, String>{
          '統一編號': '12345675',
          '總機構統一編號': '12345675',
          '營業人名稱': 'bad parent',
        }),
        throwsFormatException,
      );
    });
  });
}
