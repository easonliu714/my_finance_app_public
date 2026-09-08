import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/database/production_schema_v23.dart' as v23;
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('V23 preserves registry cache and accepts unknown subtype', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    addTearDown(db.close);
    await createCanonicalProductionV22Tables(db);
    await db.insert('business_registry_snapshots', <String, Object?>{
      'version': 'registry-v22',
      'source_dataset': 'official-fixture',
      'source_data_date': '2026-09-07',
      'content_sha256': 'a' * 64,
      'status': 'installed',
      'installed_at': '2026-09-08T00:00:00.000Z',
      'created_at': '2026-09-08T00:00:00.000Z',
    });
    await db.insert('business_registry_entities', <String, Object?>{
      'snapshot_version': 'registry-v22',
      'jurisdiction': 'TW',
      'seller_identifier': '11111111',
      'entity_type': 'company',
      'legal_name': '既有公司',
      'registration_status': 'active',
      'parent_seller_identifier': '',
      'source_dataset': 'official-fixture',
    });

    await v23.upgradeBusinessRegistryEntityTypeToV23(db);
    final preserved = await db.query(
      'business_registry_entities',
      where: 'seller_identifier = ?',
      whereArgs: const <Object?>['11111111'],
    );
    expect(preserved.single['entity_type'], 'company');

    await db.insert('business_registry_entities', <String, Object?>{
      'snapshot_version': 'registry-v22',
      'jurisdiction': 'TW',
      'seller_identifier': '22222222',
      'entity_type': 'unknown',
      'legal_name': '官方稅籍實體',
      'registration_status': 'active_tax_registration',
      'parent_seller_identifier': '',
      'source_dataset': 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    });
    expect(
      (await db.query(
        'business_registry_entities',
        where: 'seller_identifier = ?',
        whereArgs: const <Object?>['22222222'],
      )).single['entity_type'],
      'unknown',
    );

    await db.delete(
      'business_registry_snapshots',
      where: 'version = ?',
      whereArgs: const <Object?>['registry-v22'],
    );
    expect(await db.query('business_registry_entities'), isEmpty);
  });

  test('registry wire model round-trips unknown without subtype promotion', () {
    const entity = BusinessRegistryEntity(
      sellerIdentifier: '33333333',
      entityType: BusinessRegistryEntityType.unknown,
      legalName: '官方稅籍名稱',
      registrationStatus: 'active_tax_registration',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    );
    final decoded = BusinessRegistryEntity.fromJson(entity.toCanonicalJson());
    expect(decoded.entityType, BusinessRegistryEntityType.unknown);
    expect(decoded.legalName, '官方稅籍名稱');
  });

  test('canonical production schema version advances to V23', () {
    expect(v23.canonicalProductionSchemaVersion, 23);
  });
}
