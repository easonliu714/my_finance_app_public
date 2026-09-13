import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_legal_name_history_service.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('official legal-name replacement preserves append-only history', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);

    const seller = '31655572';
    final repository = MerchantIdentityRepository(database: db);
    final history = MerchantLegalNameHistoryService(database: db);
    final merchant = MerchantRecord(
      id: 'brand-okmart',
      name: 'OK mart',
      alias: '',
      note: '',
      isArchived: false,
      createdAt: DateTime.utc(2026, 9, 14),
    );

    await repository.recordConfirmedBinding(
      merchant: merchant,
      sellerIdentifier: seller,
      literalMerchantText: 'OK mart 門市',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'invoice-1',
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
      merchant: merchant,
      sellerIdentifier: seller,
      literalMerchantText: 'OK mart 門市',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'invoice-2',
      officialEntity: const BusinessRegistryEntity(
        sellerIdentifier: seller,
        legalName: '第二版官方登記名稱',
        entityType: BusinessRegistryEntityType.company,
        registrationStatus: 'active',
        sourceDataset: 'gcis-company',
      ),
      registryVersion: 'registry-v2',
    );

    final current = await repository.findConfirmedBySellerIdentifier(seller);
    expect(current, isNotNull);
    expect(current!.legalName, '第二版官方登記名稱');

    final observations = await history.listForSellerIdentifier(seller);
    expect(observations.map((row) => row.legalName).toList(), <String>[
      '第一版官方登記名稱',
      '第二版官方登記名稱',
    ]);
    expect(observations.map((row) => row.sourceReference).toList(), <String>[
      'gcis-company|registry-v1',
      'gcis-company|registry-v2',
    ]);

    final rowsAfterRead = await db.query(
      'merchant_identity_observations',
      where: "seller_identifier = ? AND source = 'official_registry'",
      whereArgs: <Object?>[seller],
    );
    expect(rowsAfterRead, hasLength(2));
  });

  test('invalid seller identifier returns no history without writes', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);

    final history = MerchantLegalNameHistoryService(database: db);
    expect(await history.listForSellerIdentifier('weak-ocr'), isEmpty);
    expect(await db.query('merchant_identity_observations'), isEmpty);
  });
}