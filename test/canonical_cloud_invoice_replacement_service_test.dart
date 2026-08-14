import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_service.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('replacement commits update before-image link operation and audit', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final original = testTransaction(amount: 300, note: '原備註');
    await insertTestTransaction(db, original);
    final request = testRequest(
      facts: testFacts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      transactionId: original.id,
      expectedTransactionFingerprint: transactionFingerprint(original),
      replacementConfirmed: true,
    );

    final result = await _service(db).execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(result.rollbackToken, isNotNull);
    final stored = TransactionRecord.fromMap(
      (await db.query('transactions')).single,
    );
    expect(stored.id, original.id);
    expect(stored.amount, 328);
    expect(stored.category, original.category);
    expect(stored.note, original.note);
    expect(stored.tagName, original.tagName);
    expect(stored.occurredAt, original.occurredAt);
    expect(await db.query('cloud_invoice_before_images'), hasLength(1));
    expect(await db.query('cloud_invoice_metadata_links'), hasLength(1));
    expect(await db.query('cloud_invoice_operations'), hasLength(1));
    expect(await db.query('cloud_invoice_audits'), hasLength(1));
  });

  test('rollback restores exact transaction and removes active link', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final original = testTransaction(amount: 300, note: 'before');
    await insertTestTransaction(db, original);
    final request = testRequest(
      facts: testFacts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      transactionId: original.id,
      expectedTransactionFingerprint: transactionFingerprint(original),
      replacementConfirmed: true,
    );
    final service = _service(db);
    final committed = await service.execute(request);

    final rolledBack = await service.rollback(committed.operationKey);

    expect(rolledBack.status, CloudInvoicePersistenceStatus.rolledBack);
    final restored = TransactionRecord.fromMap(
      (await db.query('transactions')).single,
    );
    expect(transactionFingerprint(restored), transactionFingerprint(original));
    expect(await db.query('cloud_invoice_metadata_links'), isEmpty);
    expect(
      (await db.query('cloud_invoice_operations')).single['status'],
      'rolledBack',
    );
    expect(await db.query('cloud_invoice_audits'), hasLength(2));
    expect(await db.query('cloud_invoice_before_images'), hasLength(1));
  });

  test('metadata failure restores transaction and removes partial rows', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final original = testTransaction(amount: 300);
    await insertTestTransaction(db, original);
    final request = testRequest(
      facts: testFacts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      transactionId: original.id,
      expectedTransactionFingerprint: transactionFingerprint(original),
      merchantConfirmed: true,
      replacementConfirmed: true,
    );
    final service = _service(
      db,
      faultInjector: (checkpoint) async {
        if (checkpoint == 'before_upsert_metadata_link') {
          throw StateError('injected metadata failure');
        }
      },
    );

    final result = await service.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.failed);
    final restored = TransactionRecord.fromMap(
      (await db.query('transactions')).single,
    );
    expect(transactionFingerprint(restored), transactionFingerprint(original));
    expect(await db.query('merchants'), isEmpty);
    expect(await db.query('cloud_invoice_metadata_links'), isEmpty);
    expect(await db.query('cloud_invoice_before_images'), isEmpty);
    expect(
      (await db.query('cloud_invoice_operations')).single['status'],
      'failed',
    );
  });

  test('exact source time replaces occurred-at while date-only does not', () async {
    final exactDb = await openCanonicalPersistenceTestDatabase();
    addTearDown(exactDb.close);
    final exactOriginal = testTransaction(id: 'exact', amount: 300);
    await insertTestTransaction(exactDb, exactOriginal);
    final exactRequest = testRequest(
      facts: testFacts(
        amount: 328,
        currencyCode: 'TWD',
        timePrecision: CloudInvoiceTimePrecision.exactDateTime,
      ),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      transactionId: exactOriginal.id,
      expectedTransactionFingerprint: transactionFingerprint(exactOriginal),
      replacementConfirmed: true,
    );

    await _service(exactDb).execute(exactRequest);

    final exactStored = TransactionRecord.fromMap(
      (await exactDb.query('transactions')).single,
    );
    expect(exactStored.occurredAt, DateTime(2026, 6, 18, 11, 45, 50));
  });

  test('failed rollback attempt leaves committed replacement intact', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final original = testTransaction(amount: 300);
    await insertTestTransaction(db, original);
    final request = testRequest(
      facts: testFacts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      transactionId: original.id,
      expectedTransactionFingerprint: transactionFingerprint(original),
      replacementConfirmed: true,
    );
    final committed = await _service(db).execute(request);
    final failingService = _service(
      db,
      faultInjector: (checkpoint) async {
        if (checkpoint == 'before_restore_transaction') {
          throw StateError('injected restore failure');
        }
      },
    );

    final result = await failingService.rollback(committed.operationKey);

    expect(result.status, CloudInvoicePersistenceStatus.rollbackFailed);
    final stillReplaced = TransactionRecord.fromMap(
      (await db.query('transactions')).single,
    );
    expect(stillReplaced.amount, 328);
    expect(
      (await db.query('cloud_invoice_operations')).single['status'],
      'committed',
    );
    expect(await db.query('cloud_invoice_metadata_links'), hasLength(1));
  });
}

CanonicalCloudInvoicePersistenceService _service(
  Database db, {
  CanonicalCloudInvoiceFaultInjector? faultInjector,
}) {
  return CanonicalCloudInvoicePersistenceService(
    databaseProvider: () async => db,
    clock: FixedPersistenceClock(),
    ids: SequencePersistenceIds(),
    faultInjector: faultInjector,
  );
}
