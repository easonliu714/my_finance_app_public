import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/merchant_branch_outlet_history_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('branch/outlet history preserves explicit provenance and is read-only',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');
    await createCanonicalProductionV22Tables(db);

    const seller = '31655572';
    const legalId = 'tw-seller-$seller';
    final t1 = DateTime.utc(2026, 9, 14, 1).toIso8601String();
    final t2 = DateTime.utc(2026, 9, 14, 2).toIso8601String();

    await db.insert('merchant_legal_entities', <String, Object?>{
      'id': legalId,
      'jurisdiction': 'TW',
      'seller_identifier': seller,
      'legal_name': '官方登記名稱',
      'entity_type': 'company',
      'registration_status': '',
      'registry_source': '',
      'registry_version': '',
      'first_observed_at': t1,
      'last_observed_at': t2,
    });
    await db.insert('merchant_branches_or_outlets', <String, Object?>{
      'id': 'outlet-old',
      'legal_entity_id': legalId,
      'outlet_label': '舊門市名稱',
      'official_branch_identifier': '',
      'address': '舊地址',
      'valid_from': t1,
      'valid_to': t2,
      'created_at': t1,
      'updated_at': t2,
    });
    await db.insert('merchant_branches_or_outlets', <String, Object?>{
      'id': 'outlet-current',
      'legal_entity_id': legalId,
      'outlet_label': '新門市名稱',
      'official_branch_identifier': '',
      'address': '新地址',
      'valid_from': t2,
      'valid_to': null,
      'created_at': t2,
      'updated_at': t2,
    });
    await db.insert('merchant_identity_observations', <String, Object?>{
      'id': 'obs-old',
      'literal_name': '舊門市名稱',
      'normalized_name': '舊門市名稱',
      'seller_identifier': seller,
      'source': 'explicit_user_branch_confirmation',
      'source_reference': 'invoice/old',
      'merchant_brand_id': null,
      'legal_entity_id': legalId,
      'branch_or_outlet_id': 'outlet-old',
      'decision': 'confirmed',
      'observed_at': t1,
      'created_at': t1,
    });
    await db.insert('merchant_identity_observations', <String, Object?>{
      'id': 'obs-current',
      'literal_name': '新門市名稱',
      'normalized_name': '新門市名稱',
      'seller_identifier': seller,
      'source': 'explicit_user_branch_confirmation',
      'source_reference': 'invoice/new',
      'merchant_brand_id': null,
      'legal_entity_id': legalId,
      'branch_or_outlet_id': 'outlet-current',
      'decision': 'confirmed',
      'observed_at': t2,
      'created_at': t2,
    });

    final before = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM merchant_identity_observations'),
    );
    final history = await MerchantBranchOutletHistoryService(database: db)
        .listForSellerIdentifier(seller);
    final after = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM merchant_identity_observations'),
    );

    expect(history, hasLength(2));
    expect(history.first.outletLabel, '舊門市名稱');
    expect(history.first.isCurrent, isFalse);
    expect(history.last.outletLabel, '新門市名稱');
    expect(history.last.isCurrent, isTrue);
    expect(history.map((entry) => entry.source).toSet(),
        <String>{'explicit_user_branch_confirmation'});
    expect(before, after);
  });

  test('invalid seller identifier cannot manufacture branch history', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    final history = await MerchantBranchOutletHistoryService(database: db)
        .listForSellerIdentifier('weak-ocr');
    expect(history, isEmpty);
  });
}
