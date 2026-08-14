import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_service.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('new draft commits draft operation and audit atomically', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final account = testAccount();
    await insertTestAccount(db, account);
    final facts = testFacts();
    final request = testRequest(
      facts: facts,
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      accountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
    );
    final service = _service(db);

    final result = await service.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    final draft = (await db.query('cloud_invoice_drafts')).single;
    expect(draft['currency_code'], isNull);
    expect(draft['tax_amount'], isNull);
    expect(draft['time_precision'], 'dateOnly');
    expect(draft['account_id'], account.id);
    expect(await db.query('cloud_invoice_operations'), hasLength(1));
    expect(await db.query('cloud_invoice_audits'), hasLength(1));
  });

  test('committed draft replay is idempotent', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final account = testAccount();
    await insertTestAccount(db, account);
    final request = testRequest(
      facts: testFacts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      accountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
    );
    final service = _service(db);

    final first = await service.execute(request);
    final second = await service.execute(request);

    expect(first.status, CloudInvoicePersistenceStatus.committed);
    expect(second.status, CloudInvoicePersistenceStatus.alreadyApplied);
    expect(await db.query('cloud_invoice_drafts'), hasLength(1));
    expect(await db.query('cloud_invoice_operations'), hasLength(1));
    expect(await db.query('cloud_invoice_audits'), hasLength(1));
  });

  test('enrichment writes sidecar without changing transaction', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final transaction = testTransaction(note: '使用者備註');
    await insertTestTransaction(db, transaction);
    final before = (await db.query('transactions')).single;
    final request = testRequest(
      facts: testFacts(amount: transaction.amount),
      action: CloudInvoiceReconciliationOutcome.enrichExisting,
      transactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
    );

    final result = await _service(db).execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(await db.query('cloud_invoice_metadata_links'), hasLength(1));
    expect((await db.query('transactions')).single, before);
    expect(await db.query('cloud_invoice_operations'), hasLength(1));
    expect(await db.query('cloud_invoice_audits'), hasLength(1));
  });

  test('stale transaction fingerprint rejects before mutation', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final transaction = testTransaction();
    await insertTestTransaction(db, transaction);
    final request = testRequest(
      facts: testFacts(amount: transaction.amount),
      action: CloudInvoiceReconciliationOutcome.enrichExisting,
      transactionId: transaction.id,
      expectedTransactionFingerprint: 'stale-fingerprint',
    );

    final result = await _service(db).execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.conflict);
    expect(await db.query('cloud_invoice_metadata_links'), isEmpty);
    expect(await db.query('cloud_invoice_operations'), isEmpty);
    expect(await db.query('cloud_invoice_audits'), isEmpty);
  });

  test('draft failure compensates merchant and keeps failure audit only', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final account = testAccount();
    await insertTestAccount(db, account);
    final request = testRequest(
      facts: testFacts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      accountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
      merchantConfirmed: true,
    );
    final service = _service(
      db,
      faultInjector: (checkpoint) async {
        if (checkpoint == 'before_create_draft') {
          throw StateError('injected draft failure');
        }
      },
    );

    final result = await service.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.failed);
    expect(await db.query('merchants'), isEmpty);
    expect(await db.query('cloud_invoice_drafts'), isEmpty);
    expect(await db.query('cloud_invoice_metadata_links'), isEmpty);
    expect(await db.query('cloud_invoice_before_images'), isEmpty);
    expect(
      (await db.query('cloud_invoice_operations')).single['status'],
      'failed',
    );
    expect(await db.query('cloud_invoice_audits'), hasLength(1));
  });

  test('unexpected audit failure rolls back the whole transaction', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final account = testAccount();
    await insertTestAccount(db, account);
    final request = testRequest(
      facts: testFacts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      accountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
    );
    final service = _service(
      db,
      faultInjector: (checkpoint) async {
        if (checkpoint == 'before_append_audit') {
          throw StateError('injected audit failure');
        }
      },
    );

    await expectLater(service.execute(request), throwsA(isA<StateError>()));

    expect(await db.query('cloud_invoice_drafts'), isEmpty);
    expect(await db.query('cloud_invoice_operations'), isEmpty);
    expect(await db.query('cloud_invoice_audits'), isEmpty);
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
