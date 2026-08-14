import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/taiwan_business_registry_validation.dart';

void main() {
  test('invalid checksum never reaches the official registry transport', () async {
    var calls = 0;
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async {
        calls += 1;
        return const TaiwanBusinessRegistryHttpPayload(
          statusCode: 200,
          body: '[]',
        );
      },
    );

    final result = await service.lookup('30348553');

    expect(result.status, TaiwanBusinessRegistryLookupStatus.invalidTaxId);
    expect(calls, 0);
  });

  test('official company lookup uses HTTPS GCIS dataset contract', () async {
    final requested = <Uri>[];
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async {
        requested.add(uri);
        if (uri.path.contains(
          TaiwanBusinessRegistryService.companyNameDatasetId,
        )) {
          return const TaiwanBusinessRegistryHttpPayload(
            statusCode: 200,
            body:
                '[{"Business_Accounting_NO":"20828393","Company_Name":"宏碁股份有限公司"}]',
          );
        }
        return const TaiwanBusinessRegistryHttpPayload(
          statusCode: 200,
          body: '[]',
        );
      },
    );

    final result = await service.lookup('20828393');

    expect(result.status, TaiwanBusinessRegistryLookupStatus.found);
    expect(result.records, hasLength(1));
    expect(result.records.single.name, '宏碁股份有限公司');
    expect(
      result.records.single.entityType,
      TaiwanBusinessRegistryEntityType.company,
    );
    expect(requested, hasLength(3));
    expect(requested.every((uri) => uri.scheme == 'https'), isTrue);
    expect(
      requested.every(
        (uri) => uri.host == TaiwanBusinessRegistryService.apiHost,
      ),
      isTrue,
    );
    final companyUri = requested.firstWhere(
      (uri) => uri.path.contains(
        TaiwanBusinessRegistryService.companyNameDatasetId,
      ),
    );
    expect(companyUri.queryParameters[r'$format'], 'json');
    expect(
      companyUri.queryParameters[r'$filter'],
      'Business_Accounting_NO eq 20828393',
    );
    expect(companyUri.queryParameters[r'$top'], '5');
  });

  test('business and branch name payloads are parsed as typed evidence', () async {
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async {
        if (uri.path.contains(
          TaiwanBusinessRegistryService.businessNameDatasetId,
        )) {
          return const TaiwanBusinessRegistryHttpPayload(
            statusCode: 200,
            body: '[{"President_No":"20828393","Business_Name":"測試商行"}]',
          );
        }
        if (uri.path.contains(
          TaiwanBusinessRegistryService.branchNameDatasetId,
        )) {
          return const TaiwanBusinessRegistryHttpPayload(
            statusCode: 200,
            body:
                '{"rows":[{"Branch_Office_Name":"測試股份有限公司台北分公司"}]}',
          );
        }
        return const TaiwanBusinessRegistryHttpPayload(
          statusCode: 200,
          body: '[]',
        );
      },
    );

    final result = await service.lookup('20828393');

    expect(result.status, TaiwanBusinessRegistryLookupStatus.found);
    expect(result.records, hasLength(2));
    expect(
      result.records.any(
        (record) =>
            record.entityType == TaiwanBusinessRegistryEntityType.business &&
            record.name == '測試商行',
      ),
      isTrue,
    );
    expect(
      result.records.any(
        (record) =>
            record.entityType == TaiwanBusinessRegistryEntityType.branch &&
            record.name == '測試股份有限公司台北分公司',
      ),
      isTrue,
    );
  });

  test('GCIS source-IP rejection is fail-closed as unauthorized', () async {
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async => const TaiwanBusinessRegistryHttpPayload(
        statusCode: 200,
        body: '非授權介接之IP(203.0.113.10)，請查明後繼續。',
      ),
    );

    final result = await service.lookup('20828393');

    expect(result.status, TaiwanBusinessRegistryLookupStatus.unauthorized);
    expect(result.records, isEmpty);
    expect(result.diagnostic, contains('白名單'));
  });

  test('invalid JSON is not misreported as official not-found', () async {
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async => const TaiwanBusinessRegistryHttpPayload(
        statusCode: 200,
        body: '<html>unexpected response</html>',
      ),
    );

    final result = await service.lookup('20828393');

    expect(result.status, TaiwanBusinessRegistryLookupStatus.invalidResponse);
    expect(result.records, isEmpty);
  });

  test('merchant-name comparison separates exact partial and conflict', () {
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async => const TaiwanBusinessRegistryHttpPayload(
        statusCode: 200,
        body: '[]',
      ),
    );
    const lookup = TaiwanBusinessRegistryLookupResult(
      status: TaiwanBusinessRegistryLookupStatus.found,
      taxId: '20828393',
      records: <TaiwanBusinessRegistryRecord>[
        TaiwanBusinessRegistryRecord(
          taxId: '20828393',
          name: '宏碁股份有限公司',
          entityType: TaiwanBusinessRegistryEntityType.company,
          sourceUrl: 'https://data.gcis.nat.gov.tw/example',
        ),
      ],
    );

    final exact = service.validateMerchantName(
      observedMerchantName: '宏碁股份有限公司',
      lookupResult: lookup,
    );
    final partial = service.validateMerchantName(
      observedMerchantName: '宏碁',
      lookupResult: lookup,
    );
    final conflict = service.validateMerchantName(
      observedMerchantName: '完全不同商店',
      lookupResult: lookup,
    );

    expect(exact.match, TaiwanBusinessRegistryNameMatch.exact);
    expect(partial.match, TaiwanBusinessRegistryNameMatch.partial);
    expect(conflict.match, TaiwanBusinessRegistryNameMatch.conflict);
    expect(exact.supportsCandidateExistence, isTrue);
    expect(exact.authorizesTaxIdRepair, isFalse);
    expect(exact.authorizesFormalWrite, isFalse);
  });

  test('missing OCR merchant name remains evidence-missing, not a match', () {
    final service = TaiwanBusinessRegistryService(
      fetcher: (uri) async => const TaiwanBusinessRegistryHttpPayload(
        statusCode: 200,
        body: '[]',
      ),
    );
    const lookup = TaiwanBusinessRegistryLookupResult(
      status: TaiwanBusinessRegistryLookupStatus.found,
      taxId: '20828393',
      records: <TaiwanBusinessRegistryRecord>[
        TaiwanBusinessRegistryRecord(
          taxId: '20828393',
          name: '宏碁股份有限公司',
          entityType: TaiwanBusinessRegistryEntityType.company,
          sourceUrl: 'https://data.gcis.nat.gov.tw/example',
        ),
      ],
    );

    final validation = service.validateMerchantName(
      observedMerchantName: '',
      lookupResult: lookup,
    );

    expect(
      validation.match,
      TaiwanBusinessRegistryNameMatch.missingObservedName,
    );
    expect(validation.authorizesTaxIdRepair, isFalse);
  });
}
