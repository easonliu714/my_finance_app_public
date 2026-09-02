import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_identity_review_service.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_master_binding_service.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/merchant/merchant_seller_identity_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('confirmed binding keeps brand, invoice literal, and official legal name as separate evidence', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);
    final repository = MerchantIdentityRepository(database: db);
    final merchant = MerchantRecord(
      id: 'merchant-7eleven',
      name: '7-ELEVEN',
      sellerIdentifier: '60744698',
    );
    const official = BusinessRegistryEntity(
      sellerIdentifier: '60744698',
      entityType: BusinessRegistryEntityType.company,
      legalName: '沄鉑國際有限公司',
      sourceDataset: 'GCIS_official_fixture',
    );

    final confirmed = await repository.recordConfirmedBinding(
      merchant: merchant,
      sellerIdentifier: '60744698',
      literalMerchantText: '統一超商測試門市',
      evidenceSource: 'invoice_qr_explicit_binding',
      sourceReference: 'invoice/AB12345678',
      officialEntity: official,
      registryVersion: 'official-v1',
    );

    expect(confirmed.displayName, '7-ELEVEN');
    expect(confirmed.legalName, '沄鉑國際有限公司');
    final observations = await db.query(
      'merchant_identity_observations',
      orderBy: 'source ASC',
    );
    expect(
      observations.map((row) => row['literal_name']),
      containsAll(<String>['統一超商測試門市', '沄鉑國際有限公司']),
    );
    expect(
      observations
          .where((row) => row['source'] == 'invoice_qr_explicit_binding')
          .single['merchant_brand_id'],
      'merchant-7eleven',
    );
  });

  test('same authoritative seller cannot silently acquire a second confirmed brand', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);
    final repository = MerchantIdentityRepository(database: db);

    await repository.recordConfirmedBinding(
      merchant: MerchantRecord(id: 'brand-a', name: '商家 A'),
      sellerIdentifier: '30340553',
      literalMerchantText: '商家 A',
      evidenceSource: 'invoice_review_explicit_binding',
      sourceReference: 'invoice/A',
    );
    await expectLater(
      repository.recordConfirmedBinding(
        merchant: MerchantRecord(id: 'brand-b', name: '商家 B'),
        sellerIdentifier: '30340553',
        literalMerchantText: '商家 B',
        evidenceSource: 'invoice_review_explicit_binding',
        sourceReference: 'invoice/B',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'MERCHANT_IDENTITY_CONFIRMED_BRAND_CONFLICT',
        ),
      ),
    );
  });

  test('explicit merchant binding reports official legal name without replacing formal brand', () async {
    final store = _FakeMerchantSellerIdentityStore();
    final identity = _FakeIdentityReviewPort();
    final service = InvoiceMerchantMasterBindingService(
      store: store,
      identityReviewService: identity,
    );

    final result = await service.bind(
      merchantName: '7-ELEVEN',
      sellerTaxId: '60744698',
      trustedQrSellerIdentifier: true,
      sourceReference: 'invoice/AB12345678',
    );

    expect(result.isSuccess, isTrue);
    expect(result.merchant?.name, '7-ELEVEN');
    expect(result.officialLegalName, '沄鉑國際有限公司');
    expect(result.message, contains('官方登記名稱：沄鉑國際有限公司'));
    expect(result.message, contains('僅供佐證，不覆寫發票商家文字'));
    expect(result.message, contains('實機驗證子集'));
    expect(identity.lastLiteralMerchantText, '7-ELEVEN');
    expect(identity.lastSourceReference, 'invoice/AB12345678');
  });
}

class _FakeMerchantSellerIdentityStore implements MerchantSellerIdentityStore {
  final List<MerchantRecord> rows = <MerchantRecord>[];

  @override
  Future<MerchantRecord?> findBySellerIdentifier(
    String sellerIdentifier, {
    bool includeArchived = false,
  }) async {
    for (final row in rows) {
      if (row.sellerIdentifier == sellerIdentifier &&
          (includeArchived || !row.isArchived)) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<List<MerchantRecord>> listMerchants({
    bool includeArchived = false,
  }) async {
    return rows
        .where((row) => includeArchived || !row.isArchived)
        .toList(growable: false);
  }

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    final index = rows.indexWhere((row) => row.id == merchant.id);
    if (index < 0) {
      rows.add(merchant);
    } else {
      rows[index] = merchant;
    }
  }
}

class _FakeIdentityReviewPort implements InvoiceMerchantIdentityReviewPort {
  String lastLiteralMerchantText = '';
  String lastSourceReference = '';

  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    return _context(literalMerchantText, sellerIdentifier);
  }

  @override
  Future<InvoiceMerchantIdentityReviewContext> confirmBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
  }) async {
    lastLiteralMerchantText = literalMerchantText;
    lastSourceReference = sourceReference;
    return _context(literalMerchantText, sellerIdentifier);
  }

  InvoiceMerchantIdentityReviewContext _context(
    String literalMerchantText,
    String sellerIdentifier,
  ) {
    return InvoiceMerchantIdentityReviewContext(
      decision: const MerchantIdentityResolutionPolicy().evaluate(
        sellerIdentifier: sellerIdentifier,
        sellerIdentifierAuthoritative: true,
        literalMerchantText: literalMerchantText,
        officialRegistryLegalName: '沄鉑國際有限公司',
        existingConfirmedBrandName: '7-ELEVEN',
      ),
      registryStatus: BusinessRegistryLookupStatus.hit,
      registryVersion: 'canary-v1',
      registryCoverage: BusinessRegistryPack.validationSubsetCoverage,
      registrySourceDataDate: '2025-06-02',
    );
  }
}
