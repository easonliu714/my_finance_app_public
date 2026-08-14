import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_service.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_recovery_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('failed draft operation removes partial draft and retries safely', () async {
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
    await _insertOperation(
      db,
      request,
      status: CloudInvoicePersistenceStatus.failed,
      draftId: 'partial-draft',
    );
    await _insertPartialDraft(db, request, account.id);
    final service = _service(db);

    final inspection = await service.inspectRecovery(request);
    final result = await service.execute(request);

    expect(inspection.disposition, CloudInvoiceRecoveryDisposition.retryable);
    expect(result.status, CloudInvoicePersistenceStatus.committed);
    final drafts = await db.query('cloud_invoice_drafts');
    expect(drafts, hasLength(1));
    expect(drafts.single['id'], isNot('partial-draft'));
    final audits = await db.query(
      'cloud_invoice_audits',
      orderBy: 'created_at ASC, id ASC',
    );
    expect(
      audits.map((row) => row['message']),
      containsAll(<Object?>['RETRY_CLEANUP_COMPLETED', 'DRAFT_CREATED']),
    );
  });

  test('failed enrichment removes partial link and retries safely', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final transaction = testTransaction();
    await insertTestTransaction(db, transaction);
    final request = testRequest(
      facts: testFacts(amount: transaction.amount),
      action: CloudInvoiceReconciliationOutcome.enrichExisting,
      transactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
    );
    await _insertOperation(
      db,
      request,
      status: CloudInvoicePersistenceStatus.failed,
      transactionId: transaction.id,
    );
    await _insertPartialLink(db, request, transaction.id);
    final service = _service(db);

    final result = await service.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    final links = await db.query('cloud_invoice_metadata_links');
    expect(links, hasLength(1));
    expect(links.single['id'], isNot('partial-link'));
    expect(links.single['transaction_id'], transaction.id);
  });

  test('planned operation remains blocked as in progress', () async {
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
    await _insertOperation(
      db,
      request,
      status: CloudInvoicePersistenceStatus.planned,
    );
    final service = _service(db);

    final inspection = await service.inspectRecovery(request);
    final result = await service.execute(request);

    expect(inspection.disposition, CloudInvoiceRecoveryDisposition.inProgress);
    expect(result.status, CloudInvoicePersistenceStatus.conflict);
    expect(result.message, 'OPERATION_ALREADY_IN_PROGRESS');
    expect(await db.query('cloud_invoice_drafts'), isEmpty);
  });

  test('operation key fingerprint mismatch remains a conflict', () async {
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
    await _insertOperation(
      db,
      request,
      status: CloudInvoicePersistenceStatus.failed,
      requestFingerprint: 'different-fingerprint',
    );
    final service = _service(db);

    final inspection = await service.inspectRecovery(request);
    final result = await service.execute(request);

    expect(
      inspection.disposition,
      CloudInvoiceRecoveryDisposition.requestConflict,
    );
    expect(result.status, CloudInvoicePersistenceStatus.conflict);
    expect(result.message, 'OPERATION_KEY_CONFLICT');
  });

  test('failed replacement requires manual review and is not retried', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    final transaction = testTransaction();
    await insertTestTransaction(db, transaction);
    final request = testRequest(
      facts: testFacts(amount: 125),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      transactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
      replacementConfirmed: true,
    );
    await _insertOperation(
      db,
      request,
      status: CloudInvoicePersistenceStatus.failed,
      transactionId: transaction.id,
      rollbackToken: 'rollback-review',
    );
    final service = _service(db);

    final inspection = await service.inspectRecovery(request);
    final result = await service.execute(request);

    expect(
      inspection.disposition,
      CloudInvoiceRecoveryDisposition.manualReview,
    );
    expect(result.status, CloudInvoicePersistenceStatus.conflict);
    expect(result.message, 'OPERATION_RECOVERY_REQUIRES_MANUAL_REVIEW');
    expect((await db.query('transactions')).single['amount'], transaction.amount);
  });
}

CanonicalCloudInvoicePersistenceService _service(Database db) {
  return CanonicalCloudInvoicePersistenceService(
    databaseProvider: () async => db,
    clock: FixedPersistenceClock(),
    ids: SequencePersistenceIds(),
  );
}

Future<void> _insertOperation(
  Database db,
  CloudInvoicePersistenceRequest request, {
  required CloudInvoicePersistenceStatus status,
  String? requestFingerprint,
  String? transactionId,
  String? draftId,
  String? rollbackToken,
}) async {
  await db.insert('cloud_invoice_operations', <String, Object?>{
    'operation_key': request.operationKey,
    'request_fingerprint': requestFingerprint ?? request.requestFingerprint,
    'action': request.decision.action.name,
    'status': status.name,
    'candidate_reference': request.decision.candidateReference,
    'transaction_id': transactionId,
    'account_id': request.decision.selectedAccountId,
    'merchant_id': null,
    'draft_id': draftId,
    'rollback_token': rollbackToken,
    'failure_message': 'injected failure',
    'created_at': DateTime.utc(2026, 6, 18, 10).toIso8601String(),
    'updated_at': DateTime.utc(2026, 6, 18, 11).toIso8601String(),
  });
}

Future<void> _insertPartialDraft(
  Database db,
  CloudInvoicePersistenceRequest request,
  String accountId,
) async {
  final candidate = request.facts.candidate;
  await db.insert('cloud_invoice_drafts', <String, Object?>{
    'id': 'partial-draft',
    'operation_key': request.operationKey,
    'candidate_reference': request.decision.candidateReference,
    'account_id': accountId,
    'account_name': '現金',
    'amount': candidate.totalAmount,
    'invoice_date': candidate.invoiceDate.toIso8601String(),
    'time_precision': request.facts.timePrecision.name,
    'time_source': request.facts.timeSource.name,
    'currency_code': null,
    'merchant_id': null,
    'invoice_number': candidate.invoiceNumber,
    'seller_identifier': candidate.sellerIdentifier,
    'seller_name': candidate.sellerName,
    'tax_amount': candidate.taxAmount,
    'line_items_json': '[]',
    'payload_version': 1,
    'created_at': DateTime.utc(2026, 6, 18, 11).toIso8601String(),
  });
}

Future<void> _insertPartialLink(
  Database db,
  CloudInvoicePersistenceRequest request,
  String transactionId,
) async {
  final candidate = request.facts.candidate;
  await db.insert('cloud_invoice_metadata_links', <String, Object?>{
    'id': 'partial-link',
    'operation_key': request.operationKey,
    'transaction_id': transactionId,
    'candidate_reference': request.decision.candidateReference,
    'invoice_number': candidate.invoiceNumber,
    'seller_identifier': candidate.sellerIdentifier,
    'seller_name': candidate.sellerName,
    'invoice_date': candidate.invoiceDate.toIso8601String(),
    'time_precision': request.facts.timePrecision.name,
    'time_source': request.facts.timeSource.name,
    'currency_code': null,
    'currency_source': request.facts.currencySource.name,
    'tax_amount': candidate.taxAmount,
    'merchant_id': null,
    'line_items_json': '[]',
    'payload_version': 1,
    'created_at': DateTime.utc(2026, 6, 18, 11).toIso8601String(),
  });
}
