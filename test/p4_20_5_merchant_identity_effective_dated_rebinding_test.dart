import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_repository.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late MerchantIdentityRepository repository;

  MerchantRecord merchant(String id, String name) => MerchantRecord(
        id: id,
        name: name,
        sellerIdentifier: '31655572',
        createdAt: DateTime.utc(2026, 9, 13),
        updatedAt: DateTime.utc(2026, 9, 13),
      );

  Future<void> bind(
    MerchantRecord record, {
    required String sourceReference,
  }) async {
    await repository.recordConfirmedBinding(
      merchant: record,
      sellerIdentifier: '31655572',
      literalMerchantText: record.name,
      evidenceSource: 'explicit_user_confirmation',
      sourceReference: sourceReference,
    );
  }

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repository = MerchantIdentityRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('explicit re-binding closes prior period and preserves history', () async {
    final brandA = merchant('brand-a', 'Brand A');
    final brandB = merchant('brand-b', 'Brand B');

    await bind(brandA, sourceReference: 'owner-decision-a-1');
    await bind(brandB, sourceReference: 'owner-decision-b-1');

    final active =
        await repository.findConfirmedBySellerIdentifier('31655572');
    final history = await repository
        .listBindingHistoryForSellerIdentifier('31655572');

    expect(active, isNotNull);
    expect(active!.merchantBrandId, 'brand-b');
    expect(history, hasLength(2));
    expect(history[0].merchantBrandId, 'brand-a');
    expect(history[0].effectiveTo, isNotNull);
    expect(history[1].merchantBrandId, 'brand-b');
    expect(history[1].isActive, isTrue);
    expect(history[0].effectiveTo, history[1].effectiveFrom);
  });

  test('A to B to A creates three periods without overwriting history', () async {
    final brandA = merchant('brand-a', 'Brand A');
    final brandB = merchant('brand-b', 'Brand B');

    await bind(brandA, sourceReference: 'owner-decision-a-1');
    await bind(brandB, sourceReference: 'owner-decision-b-1');
    await bind(brandA, sourceReference: 'owner-decision-a-2');

    final history = await repository
        .listBindingHistoryForSellerIdentifier('31655572');

    expect(history, hasLength(3));
    expect(
      history.map((period) => period.merchantBrandId).toList(),
      <String>['brand-a', 'brand-b', 'brand-a'],
    );
    expect(history[0].isActive, isFalse);
    expect(history[1].isActive, isFalse);
    expect(history[2].isActive, isTrue);
    expect(history.map((period) => period.id).toSet(), hasLength(3));
  });

  test('repeating the same active binding is idempotent', () async {
    final brandA = merchant('brand-a', 'Brand A');

    await bind(brandA, sourceReference: 'owner-decision-a-1');
    await bind(brandA, sourceReference: 'owner-decision-a-repeat');

    final history = await repository
        .listBindingHistoryForSellerIdentifier('31655572');

    expect(history, hasLength(1));
    expect(history.single.merchantBrandId, 'brand-a');
    expect(history.single.isActive, isTrue);
  });

  test('history projection is read-only and keeps decision provenance', () async {
    final brandA = merchant('brand-a', 'Brand A');
    await bind(brandA, sourceReference: 'owner-decision-a-1');

    final before = await database.query('merchant_brand_legal_links');
    final history = await repository
        .listBindingHistoryForSellerIdentifier('31655572');
    final after = await database.query('merchant_brand_legal_links');

    expect(history.single.evidenceSource, 'explicit_user_confirmation');
    expect(after, before);
  });
}
