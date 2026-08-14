import 'package:sqflite/sqflite.dart';

import '../../../database/production_database_coordinator.dart';
import '../../account/account_record.dart';
import '../cloud_invoice_candidate.dart';
import 'canonical_cloud_invoice_persistence_service.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_reconciliation_review_decision.dart';

class PrivateCloudInvoiceLabSmokeSnapshot {
  const PrivateCloudInvoiceLabSmokeSnapshot({
    required this.status,
    required this.operationKey,
    required this.message,
    required this.draftCount,
    required this.operationCount,
    required this.auditCount,
    required this.transactionCountUnchanged,
    this.draftId,
  });

  final CloudInvoicePersistenceStatus status;
  final String operationKey;
  final String message;
  final String? draftId;
  final int draftCount;
  final int operationCount;
  final int auditCount;
  final bool transactionCountUnchanged;
}

class PrivateCloudInvoiceLabCleanupResult {
  const PrivateCloudInvoiceLabCleanupResult({
    required this.deletedDrafts,
    required this.deletedLinks,
    required this.deletedBeforeImages,
    required this.deletedAudits,
    required this.deletedOperations,
  });

  final int deletedDrafts;
  final int deletedLinks;
  final int deletedBeforeImages;
  final int deletedAudits;
  final int deletedOperations;

  int get totalDeleted =>
      deletedDrafts +
      deletedLinks +
      deletedBeforeImages +
      deletedAudits +
      deletedOperations;
}

abstract interface class PrivateCloudInvoiceLabSmokePort {
  Future<List<AccountRecord>> listActiveAccounts();

  Future<PrivateCloudInvoiceLabSmokeSnapshot> execute(AccountRecord account);

  Future<PrivateCloudInvoiceLabCleanupResult> cleanup(AccountRecord account);
}

class PrivateCloudInvoiceLabSmokeService
    implements PrivateCloudInvoiceLabSmokePort {
  PrivateCloudInvoiceLabSmokeService({
    Future<Database> Function()? databaseProvider,
    CanonicalCloudInvoicePersistenceService? persistenceService,
  })  : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database),
        _persistenceService = persistenceService ??
            CanonicalCloudInvoicePersistenceService();

  static const String candidateReference = 'PRIVATE-LAB-SMOKE-V1';
  static const String invoiceNumber = 'LB00000001';

  final Future<Database> Function() _databaseProvider;
  final CanonicalCloudInvoicePersistenceService _persistenceService;

  @override
  Future<List<AccountRecord>> listActiveAccounts() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'accounts',
      where: 'is_archived = 0',
      orderBy: 'sort_order ASC, name ASC, suffix ASC',
    );
    return rows.map(AccountRecord.fromMap).toList(growable: false);
  }

  @override
  Future<PrivateCloudInvoiceLabSmokeSnapshot> execute(
    AccountRecord account,
  ) async {
    if (account.isArchived) {
      throw StateError('LAB_ACCOUNT_ARCHIVED');
    }
    final db = await _databaseProvider();
    final beforeTransactions = await _count(db, 'transactions');
    final request = buildRequest(account);
    final result = await _persistenceService.execute(request);
    final afterTransactions = await _count(db, 'transactions');

    return PrivateCloudInvoiceLabSmokeSnapshot(
      status: result.status,
      operationKey: request.operationKey,
      message: result.message,
      draftId: result.draftId,
      draftCount: await _countExact(
        db,
        'cloud_invoice_drafts',
        request.operationKey,
      ),
      operationCount: await _countExact(
        db,
        'cloud_invoice_operations',
        request.operationKey,
      ),
      auditCount: await _countExact(
        db,
        'cloud_invoice_audits',
        request.operationKey,
      ),
      transactionCountUnchanged: beforeTransactions == afterTransactions,
    );
  }

  @override
  Future<PrivateCloudInvoiceLabCleanupResult> cleanup(
    AccountRecord account,
  ) async {
    final db = await _databaseProvider();
    final operationKey = buildRequest(account).operationKey;
    return db.transaction((txn) async {
      final drafts = await _deleteExact(
        txn,
        'cloud_invoice_drafts',
        operationKey,
      );
      final links = await _deleteExact(
        txn,
        'cloud_invoice_metadata_links',
        operationKey,
      );
      final beforeImages = await _deleteByOperation(
        txn,
        'cloud_invoice_before_images',
        operationKey,
      );
      final audits = await _deleteExact(
        txn,
        'cloud_invoice_audits',
        operationKey,
      );
      final operations = await _deleteExact(
        txn,
        'cloud_invoice_operations',
        operationKey,
      );
      return PrivateCloudInvoiceLabCleanupResult(
        deletedDrafts: drafts,
        deletedLinks: links,
        deletedBeforeImages: beforeImages,
        deletedAudits: audits,
        deletedOperations: operations,
      );
    });
  }

  CloudInvoicePersistenceRequest buildRequest(AccountRecord account) {
    final candidate = CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: invoiceNumber,
      invoiceDate: DateTime.utc(2000, 1, 1),
      sellerIdentifier: 'LAB00000',
      sellerName: 'P4.LAB.9 模擬候選',
      totalAmount: 1,
      carrierType: 'private-lab',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2000, 1, 1),
      lineItems: const <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '非正式草稿驗證', amount: 1),
      ],
      duplicateKeyOverride: candidateReference,
    );
    final facts = CloudInvoiceCandidateFacts(
      candidate: candidate,
      timePrecision: CloudInvoiceTimePrecision.dateOnly,
      timeSource: CloudInvoiceTimeSource.unknown,
      currencyCode: null,
      currencySource: CloudInvoiceCurrencySource.unknown,
    );
    return CloudInvoicePersistenceRequest(
      facts: facts,
      decision: CloudInvoiceReconciliationReviewDecision(
        action: CloudInvoiceReconciliationOutcome.createNewDraft,
        selectedTransactionId: null,
        selectedAccountId: account.id,
        merchantProposalReviewed: true,
        merchantProposalConfirmed: false,
        replacementSecondConfirmationCompleted: false,
        candidateReference: candidateReference,
        decidedAt: DateTime.utc(2000, 1, 1),
      ),
      expectedAccountFingerprint: accountFingerprint(account),
      requestedAt: DateTime.utc(2000, 1, 1),
    );
  }

  Future<int> _count(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
    return (rows.single['total'] as num).toInt();
  }

  Future<int> _countExact(
    DatabaseExecutor db,
    String table,
    String operationKey,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $table '
      'WHERE operation_key = ? AND candidate_reference = ?',
      <Object?>[operationKey, candidateReference],
    );
    return (rows.single['total'] as num).toInt();
  }

  Future<int> _deleteExact(
    DatabaseExecutor db,
    String table,
    String operationKey,
  ) {
    return db.delete(
      table,
      where: 'operation_key = ? AND candidate_reference = ?',
      whereArgs: <Object?>[operationKey, candidateReference],
    );
  }

  Future<int> _deleteByOperation(
    DatabaseExecutor db,
    String table,
    String operationKey,
  ) {
    return db.delete(
      table,
      where: 'operation_key = ?',
      whereArgs: <Object?>[operationKey],
    );
  }
}
