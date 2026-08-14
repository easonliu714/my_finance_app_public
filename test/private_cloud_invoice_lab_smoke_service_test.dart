import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_service.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_smoke_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('smoke draft is non-formal, nullable, idempotent, and cleanable', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final account = testAccount();
    final existingTransaction = testTransaction();
    await insertTestAccount(db, account);
    await insertTestTransaction(db, existingTransaction);
    final beforeTransaction = (await db.query('transactions')).single;
    final persistence = CanonicalCloudInvoicePersistenceService(
      databaseProvider: () async => db,
      clock: FixedPersistenceClock(),
      ids: SequencePersistenceIds(),
    );
    final smoke = PrivateCloudInvoiceLabSmokeService(
      databaseProvider: () async => db,
      persistenceService: persistence,
    );

    expect(await smoke.listActiveAccounts(), hasLength(1));
    final first = await smoke.execute(account);
    final second = await smoke.execute(account);

    expect(first.status, CloudInvoicePersistenceStatus.committed);
    expect(second.status, CloudInvoicePersistenceStatus.alreadyApplied);
    expect(first.transactionCountUnchanged, isTrue);
    expect(second.transactionCountUnchanged, isTrue);
    expect(await db.query('transactions'), <Object?>[beforeTransaction]);
    expect(await db.query('merchants'), isEmpty);
    final draft = (await db.query('cloud_invoice_drafts')).single;
    expect(draft['candidate_reference'],
        PrivateCloudInvoiceLabSmokeService.candidateReference);
    expect(draft['currency_code'], isNull);
    expect(draft['tax_amount'], isNull);
    expect(draft['time_precision'], 'dateOnly');
    expect(await db.query('cloud_invoice_drafts'), hasLength(1));
    expect(await db.query('cloud_invoice_operations'), hasLength(1));
    expect(await db.query('cloud_invoice_audits'), hasLength(1));

    await _insertUnrelatedAuditData(db);
    final cleanup = await smoke.cleanup(account);

    expect(cleanup.deletedDrafts, 1);
    expect(cleanup.deletedOperations, 1);
    expect(cleanup.deletedAudits, 1);
    expect(await db.query('transactions'), <Object?>[beforeTransaction]);
    expect(
      await db.query(
        'cloud_invoice_operations',
        where: 'candidate_reference = ?',
        whereArgs: const <Object?>['OTHER-CANDIDATE'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'cloud_invoice_audits',
        where: 'candidate_reference = ?',
        whereArgs: const <Object?>['OTHER-CANDIDATE'],
      ),
      hasLength(1),
    );
  });

  test('archived accounts are excluded from smoke selection', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    await insertTestAccount(db, testAccount(id: 'active'));
    await insertTestAccount(db, testAccount(id: 'archived', archived: true));
    final smoke = PrivateCloudInvoiceLabSmokeService(
      databaseProvider: () async => db,
      persistenceService: CanonicalCloudInvoicePersistenceService(
        databaseProvider: () async => db,
        clock: FixedPersistenceClock(),
        ids: SequencePersistenceIds(),
      ),
    );

    final accounts = await smoke.listActiveAccounts();

    expect(accounts.map((item) => item.id), <String>['active']);
  });
}

Future<void> _insertUnrelatedAuditData(Database db) async {
  await db.insert('cloud_invoice_operations', <String, Object?>{
    'operation_key': 'other-operation',
    'request_fingerprint': 'other-fingerprint',
    'action': 'keepSeparate',
    'status': 'committed',
    'candidate_reference': 'OTHER-CANDIDATE',
    'created_at': '2026-06-18T00:00:00.000Z',
    'updated_at': '2026-06-18T00:00:00.000Z',
  });
  await db.insert('cloud_invoice_audits', <String, Object?>{
    'id': 'other-audit',
    'operation_key': 'other-operation',
    'action': 'keepSeparate',
    'status': 'committed',
    'candidate_reference': 'OTHER-CANDIDATE',
    'message': 'unrelated',
    'created_at': '2026-06-18T00:00:00.000Z',
  });
}
