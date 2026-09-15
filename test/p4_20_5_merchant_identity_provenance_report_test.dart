import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_provenance_report_service.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
      'provenance report keeps current brand, effective binding history, and legal-name history separate and read-only',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');
    await createCanonicalProductionV22Tables(db);

    const seller = '31655572';
    final repository = MerchantIdentityRepository(database: db);
    final brandA = MerchantRecord(
      id: 'brand-a',
      name: 'Brand A',
      sellerIdentifier: seller,
      createdAt: DateTime.utc(2026, 9, 14),
      updatedAt: DateTime.utc(2026, 9, 14),
    );
    final brandB = MerchantRecord(
      id: 'brand-b',
      name: 'Brand B',
      sellerIdentifier: seller,
      createdAt: DateTime.utc(2026, 9, 14, 1),
      updatedAt: DateTime.utc(2026, 9, 14, 1),
    );

    await repository.recordConfirmedBinding(
      merchant: brandA,
      sellerIdentifier: seller,
      literalMerchantText: '發票辨識文字 A',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'owner-decision-a',
      officialEntity: const BusinessRegistryEntity(
        sellerIdentifier: seller,
        legalName: '第一版官方登記名稱',
        entityType: BusinessRegistryEntityType.company,
        registrationStatus: 'active',
        sourceDataset: 'gcis-company',
      ),
      registryVersion: 'registry-v1',
    );
    await repository.recordConfirmedBinding(
      merchant: brandB,
      sellerIdentifier: seller,
      literalMerchantText: '發票辨識文字 B',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'owner-decision-b',
      officialEntity: const BusinessRegistryEntity(
        sellerIdentifier: seller,
        legalName: '第二版官方登記名稱',
        entityType: BusinessRegistryEntityType.company,
        registrationStatus: 'active',
        sourceDataset: 'gcis-company',
      ),
      registryVersion: 'registry-v2',
    );

    final linksBefore = await db.query('merchant_brand_legal_links');
    final observationsBefore = await db.query('merchant_identity_observations');

    final report = await MerchantIdentityProvenanceReportService(database: db)
        .buildForSellerIdentifier(seller);

    final linksAfter = await db.query('merchant_brand_legal_links');
    final observationsAfter = await db.query('merchant_identity_observations');

    expect(report.sellerIdentifier, seller);
    expect(report.hasCurrentBinding, isTrue);
    expect(report.currentIdentity!.merchantBrandId, 'brand-b');
    expect(report.currentIdentity!.legalName, '第二版官方登記名稱');

    expect(report.bindingHistory, hasLength(2));
    expect(
      report.bindingHistory.map((period) => period.merchantBrandId).toList(),
      <String>['brand-a', 'brand-b'],
    );
    expect(report.bindingHistory.first.isActive, isFalse);
    expect(report.bindingHistory.last.isActive, isTrue);
    expect(report.bindingHistory.first.effectiveTo,
        report.bindingHistory.last.effectiveFrom);
    expect(
      report.bindingHistory.map((period) => period.evidenceSource).toSet(),
      <String>{'explicit_user_confirmation'},
    );

    expect(
      report.legalNameHistory.map((row) => row.legalName).toList(),
      <String>['第一版官方登記名稱', '第二版官方登記名稱'],
    );
    expect(
      report.legalNameHistory.map((row) => row.sourceReference).toList(),
      <String>['gcis-company|registry-v1', 'gcis-company|registry-v2'],
    );
    expect(report.branchOutletHistory, isEmpty);

    expect(linksAfter, linksBefore);
    expect(observationsAfter, observationsBefore);
  });

  test('invalid seller identifier yields an empty report and cannot write state',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);

    final report = await MerchantIdentityProvenanceReportService(database: db)
        .buildForSellerIdentifier('weak-ocr');

    expect(report.hasCurrentBinding, isFalse);
    expect(report.bindingHistory, isEmpty);
    expect(report.legalNameHistory, isEmpty);
    expect(report.branchOutletHistory, isEmpty);
    expect(await db.query('merchant_brand_legal_links'), isEmpty);
    expect(await db.query('merchant_identity_observations'), isEmpty);
  });
}
