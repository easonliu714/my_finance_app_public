import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_authoritative_lookup_service.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/business_registry_update_service.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P4.20.1-E authoritative unseen seller refresh', () {
    late Database db;
    late BusinessRegistryRepository registry;
    late MerchantIdentityRepository identity;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await createCanonicalProductionV22Tables(db);
      registry = BusinessRegistryRepository(database: db);
      identity = MerchantIdentityRepository(database: db);
    });

    tearDown(() async => db.close());

    test('non-authoritative seller never checks freshness or refreshes', () async {
      final refresh = _FakeRefreshPort(manifest: _manifest('2026-09-01'));
      final result = await BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      ).resolve(
        sellerIdentifier: '12345678',
        authoritative: false,
      );

      expect(result.status, BusinessRegistryAuthoritativeLookupStatus.ineligible);
      expect(refresh.manifestChecks, 0);
      expect(refresh.updateCalls, 0);
    });

    test('known confirmed merchant identity performs zero network work', () async {
      await identity.recordConfirmedBinding(
        merchant: MerchantRecord(id: 'known-brand', name: '已知品牌'),
        sellerIdentifier: '12345678',
        literalMerchantText: '發票文字',
        evidenceSource: 'test',
        sourceReference: 'known-source',
      );
      final refresh = _FakeRefreshPort(manifest: _manifest('2026-09-01'));

      final result = await BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      ).resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );

      expect(
        result.status,
        BusinessRegistryAuthoritativeLookupStatus.knownMerchantIdentity,
      );
      expect(result.confirmedIdentity?.displayName, '已知品牌');
      expect(refresh.manifestChecks, 0);
      expect(refresh.updateCalls, 0);
    });

    test('current installed registry miss is cached and never redownloaded',
        () async {
      final pack = await _pack(
        version: '2026-09-01',
        seller: '87654321',
      );
      await registry.install(pack);
      final refresh = _FakeRefreshPort(
        manifest: _manifest(
          '2026-09-01',
          contentSha256: pack.contentSha256,
        ),
      );
      final service = BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      );

      final first = await service.resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );
      final second = await service.resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );

      expect(
        first.status,
        BusinessRegistryAuthoritativeLookupStatus.notFoundCurrentRegistry,
      );
      expect(
        second.status,
        BusinessRegistryAuthoritativeLookupStatus.notFoundCurrentRegistry,
      );
      expect(second.registryLookup?.negativeCacheHit, isTrue);
      expect(refresh.manifestChecks, 1);
      expect(refresh.updateCalls, 0);
    });

    test('missing registry performs at most one controlled refresh then retries once',
        () async {
      final manifest = _manifest('2026-09-01');
      final refresh = _FakeRefreshPort(
        manifest: manifest,
        onUpdate: () async {
          await registry.install(
            await _pack(
              version: '2026-09-01',
              seller: '12345678',
            ),
          );
        },
      );

      final result = await BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      ).resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );

      expect(
        result.status,
        BusinessRegistryAuthoritativeLookupStatus.refreshedRegistryHit,
      );
      expect(result.refreshAttempted, isTrue);
      expect(result.registryLookup?.primaryEntity?.legalName, '測試官方名稱');
      expect(refresh.manifestChecks, 1);
      expect(refresh.updateCalls, 1);
    });

    test('refresh failure is non-blocking and never retries twice', () async {
      final refresh = _FakeRefreshPort(
        manifest: _manifest('2026-09-01'),
        updateError: StateError('offline'),
      );
      final service = BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      );

      final first = await service.resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );
      final second = await service.resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );

      expect(
        first.status,
        BusinessRegistryAuthoritativeLookupStatus.refreshFailed,
      );
      expect(
        second.status,
        BusinessRegistryAuthoritativeLookupStatus.refreshFailed,
      );
      expect(first.canContinueInvoiceReview, isTrue);
      expect(second.canContinueInvoiceReview, isTrue);
      expect(first.refreshAttempted, isTrue);
      expect(second.refreshAttempted, isTrue);
      expect(refresh.manifestChecks, 1);
      expect(refresh.updateCalls, 1);
    });

    test('concurrent same-seller misses share one in-flight refresh', () async {
      final gate = Completer<void>();
      final manifestStarted = Completer<void>();
      final refresh = _FakeRefreshPort(
        manifest: _manifest('2026-09-01'),
        beforeManifestReturn: () async {
          if (!manifestStarted.isCompleted) manifestStarted.complete();
          await gate.future;
        },
        updateError: StateError('offline'),
      );
      final serviceA = BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      );
      final serviceB = BusinessRegistryAuthoritativeLookupService(
        identityRepository: identity,
        registryRepository: registry,
        refreshPort: refresh,
      );

      final firstFuture = serviceA.resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );
      final secondFuture = serviceB.resolve(
        sellerIdentifier: '12345678',
        authoritative: true,
      );

      await manifestStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(refresh.manifestChecks, 1);

      gate.complete();
      final results = await Future.wait(
        <Future<BusinessRegistryAuthoritativeLookupResult>>[
          firstFuture,
          secondFuture,
        ],
      );

      expect(
        results.map((item) => item.status),
        everyElement(BusinessRegistryAuthoritativeLookupStatus.refreshFailed),
      );
      expect(refresh.manifestChecks, 1);
      expect(refresh.updateCalls, 1);
    });
  });
}

BusinessRegistryDistributionManifest _manifest(
  String version, {
  String? contentSha256,
}) =>
    BusinessRegistryDistributionManifest(
      schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
      registryVersion: version,
      sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
      sourceDataset: 'nationwide_company_business_branch',
      sourceDataDate: version,
      coverage: BusinessRegistryPack.nationwideCoverage,
      format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
      entityCount: 1,
      downloadUri: Uri.parse(
        'https://github.com/easonliu714/my_finance_app_public/releases/download/registry-v1/registry.gz',
      ),
      downloadSha256: 'a' * 64,
      registryContentSha256: contentSha256 ?? 'b' * 64,
      compressedSizeBytes: 100,
      uncompressedSizeBytes: 200,
      attribution: '經濟部商業發展署 / data.gov.tw',
      licenseUri: Uri.parse('https://data.gov.tw/license'),
    );

Future<BusinessRegistryPack> _pack({
  required String version,
  required String seller,
}) async {
  final entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: seller,
      entityType: BusinessRegistryEntityType.company,
      legalName: '測試官方名稱',
      sourceDataset: 'nationwide_company_business_branch',
    ),
  ];
  final sha = await computeBusinessRegistryPayloadSha256(entities);
  return BusinessRegistryPack(
    version: version,
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'nationwide_company_business_branch',
    sourceDataDate: version,
    coverage: BusinessRegistryPack.nationwideCoverage,
    contentSha256: sha,
    entities: entities,
  );
}

class _FakeRefreshPort implements BusinessRegistryRefreshPort {
  _FakeRefreshPort({
    required this.manifest,
    this.onUpdate,
    this.updateError,
    this.beforeManifestReturn,
  });

  final BusinessRegistryDistributionManifest? manifest;
  final Future<void> Function()? onUpdate;
  final Object? updateError;
  final Future<void> Function()? beforeManifestReturn;
  int manifestChecks = 0;
  int updateCalls = 0;

  @override
  Future<BusinessRegistryDistributionManifest?> fetchAvailableManifest() async {
    manifestChecks += 1;
    await beforeManifestReturn?.call();
    return manifest;
  }

  @override
  Future<BusinessRegistryUpdateResult> update({
    BusinessRegistryDistributionManifest? knownManifest,
  }) async {
    updateCalls += 1;
    final error = updateError;
    if (error != null) throw error;
    await onUpdate?.call();
    return const BusinessRegistryUpdateResult(
      status: BusinessRegistryUpdateStatus.updated,
      snapshot: null,
    );
  }
}
