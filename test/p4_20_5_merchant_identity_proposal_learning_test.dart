import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/invoice/merchant_identity_proposal_learning_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> openDb() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    await createCanonicalProductionV22Tables(db);
    return db;
  }

  test('weak proposal cannot create learning evidence without explicit user decision', () async {
    final db = await openDb();
    addTearDown(db.close);
    final service = MerchantIdentityProposalLearningService(database: db);

    await expectLater(
      service.recordExplicitOutcome(
        proposalName: '弱 OCR 商家',
        sellerIdentifier: '31655572',
        sourceReference: 'invoice/weak-1',
        outcome: MerchantIdentityProposalOutcome.reject,
        explicitUserDecision: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('merchant_identity_observations'), isEmpty);
  });

  test('explicit rejection is append-only, idempotent, and suppressible', () async {
    final db = await openDb();
    addTearDown(db.close);
    final service = MerchantIdentityProposalLearningService(database: db);

    Future<void> reject() => service.recordExplicitOutcome(
          proposalName: '  弱 OCR 商家  ',
          sellerIdentifier: '31655572',
          sourceReference: 'invoice/reject-1',
          outcome: MerchantIdentityProposalOutcome.reject,
          explicitUserDecision: true,
        );

    await reject();
    await reject();

    expect(
      await service.wasExplicitlyRejected(
        proposalName: '弱 OCR 商家',
        sellerIdentifier: '31655572',
      ),
      isTrue,
    );
    final rows = await db.query('merchant_identity_observations');
    expect(rows, hasLength(1));
    expect(rows.single['decision'], 'rejected');
    expect(rows.single['source'], 'explicit_user_proposal_reject');
    expect(rows.single['merchant_brand_id'], isNull);
  });

  test('accept and correct retain explicit provenance without formal transaction writes', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db.insert('merchant_brands', <String, Object?>{
      'id': 'brand-a',
      'display_name': '品牌 A',
      'display_override': '',
      'note': '',
      'is_archived': 0,
      'created_at': '2026-09-14T00:00:00Z',
      'updated_at': '2026-09-14T00:00:00Z',
    });
    await db.insert('merchant_brands', <String, Object?>{
      'id': 'brand-b',
      'display_name': '品牌 B',
      'display_override': '',
      'note': '',
      'is_archived': 0,
      'created_at': '2026-09-14T00:00:00Z',
      'updated_at': '2026-09-14T00:00:00Z',
    });
    final service = MerchantIdentityProposalLearningService(database: db);

    await service.recordExplicitOutcome(
      proposalName: '辨識商家 A',
      sellerIdentifier: '31655572',
      sourceReference: 'invoice/accept-1',
      outcome: MerchantIdentityProposalOutcome.accept,
      explicitUserDecision: true,
      selectedMerchantBrandId: 'brand-a',
    );
    await service.recordExplicitOutcome(
      proposalName: '辨識商家 A',
      sellerIdentifier: '31655572',
      sourceReference: 'invoice/correct-1',
      outcome: MerchantIdentityProposalOutcome.correct,
      explicitUserDecision: true,
      selectedMerchantBrandId: 'brand-b',
    );

    final rows = await db.query(
      'merchant_identity_observations',
      orderBy: 'source_reference ASC',
    );
    expect(rows, hasLength(2));
    expect(rows[0]['source'], 'explicit_user_proposal_accept');
    expect(rows[0]['merchant_brand_id'], 'brand-a');
    expect(rows[1]['source'], 'explicit_user_proposal_correct');
    expect(rows[1]['merchant_brand_id'], 'brand-b');
    expect(rows.every((row) => row['decision'] == 'confirmed'), isTrue);

    final transactionTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('transactions', 'transaction_entries')",
    );
    for (final table in transactionTables) {
      final name = table['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        expect((await db.query(name)).length, 0);
      }
    }
  });
}
