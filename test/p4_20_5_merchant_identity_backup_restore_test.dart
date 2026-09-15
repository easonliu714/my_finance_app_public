import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_backup_service.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<Database> openDb() => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );

  MerchantRecord merchant(String id, String name) => MerchantRecord(
        id: id,
        name: name,
        sellerIdentifier: '31655572',
        createdAt: DateTime.utc(2026, 9, 14),
        updatedAt: DateTime.utc(2026, 9, 14),
      );

  test('backup restore preserves effective-dated history and is repeatable', () async {
    final source = await openDb();
    final target = await openDb();
    addTearDown(source.close);
    addTearDown(target.close);

    final sourceRepository = MerchantIdentityRepository(database: source);
    await sourceRepository.recordConfirmedBinding(
      merchant: merchant('brand-a', 'Brand A'),
      sellerIdentifier: '31655572',
      literalMerchantText: 'Brand A invoice literal',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'owner-a',
    );
    await sourceRepository.recordConfirmedBinding(
      merchant: merchant('brand-b', 'Brand B'),
      sellerIdentifier: '31655572',
      literalMerchantText: 'Brand B invoice literal',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'owner-b',
    );

    final snapshot = await MerchantIdentityBackupService(database: source)
        .exportSnapshot();
    final backup = MerchantIdentityBackupService(database: target);
    await backup.restoreSnapshot(snapshot);
    await backup.restoreSnapshot(snapshot);

    final restored = MerchantIdentityRepository(database: target);
    final history =
        await restored.listBindingHistoryForSellerIdentifier('31655572');
    final active = await restored.findConfirmedBySellerIdentifier('31655572');
    final observations = await target.query('merchant_identity_observations');

    expect(history, hasLength(2));
    expect(history[0].merchantBrandId, 'brand-a');
    expect(history[0].isActive, isFalse);
    expect(history[1].merchantBrandId, 'brand-b');
    expect(history[1].isActive, isTrue);
    expect(active?.merchantBrandId, 'brand-b');
    expect(observations, hasLength(2));
  });

  test('Registry cache replacement cannot delete user-owned identity history', () async {
    final database = await openDb();
    addTearDown(database.close);
    final repository = MerchantIdentityRepository(database: database);

    await repository.recordConfirmedBinding(
      merchant: merchant('brand-a', 'Consumer Brand'),
      sellerIdentifier: '31655572',
      literalMerchantText: 'OCR literal is separate',
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: 'owner-confirmation',
    );

    await database.insert('business_registry_snapshots', <String, Object?>{
      'version': 'registry-v1',
      'source_dataset': 'local-fixture',
      'source_data_date': '2026-09-14',
      'content_sha256': List<String>.filled(64, 'a').join(),
      'status': 'installed',
      'installed_at': DateTime.utc(2026, 9, 14).toIso8601String(),
      'created_at': DateTime.utc(2026, 9, 14).toIso8601String(),
    });
    await database.insert('business_registry_entities', <String, Object?>{
      'snapshot_version': 'registry-v1',
      'jurisdiction': 'TW',
      'seller_identifier': '31655572',
      'entity_type': 'company',
      'legal_name': 'Replaceable Legal Name',
      'registration_status': 'active',
      'parent_seller_identifier': '',
      'source_dataset': 'local-fixture',
    });

    await database.delete(
      'business_registry_snapshots',
      where: 'version = ?',
      whereArgs: <Object?>['registry-v1'],
    );

    final active = await repository.findConfirmedBySellerIdentifier('31655572');
    final history =
        await repository.listBindingHistoryForSellerIdentifier('31655572');
    final observations = await database.query('merchant_identity_observations');

    expect(active?.displayName, 'Consumer Brand');
    expect(history, hasLength(1));
    expect(history.single.evidenceSource, 'explicit_user_confirmation');
    expect(observations, hasLength(1));
    expect(await database.query('business_registry_entities'), isEmpty);
  });

  test('backup payload excludes replaceable Registry cache tables', () async {
    final database = await openDb();
    addTearDown(database.close);
    final snapshot = await MerchantIdentityBackupService(database: database)
        .exportSnapshot();

    expect(
      snapshot.tables.keys,
      containsAll(MerchantIdentityBackupService.userOwnedTables),
    );
    expect(snapshot.tables, isNot(contains('business_registry_snapshots')));
    expect(snapshot.tables, isNot(contains('business_registry_entities')));
    expect(
      snapshot.tables,
      isNot(contains('business_registry_negative_lookups')),
    );
  });
}
