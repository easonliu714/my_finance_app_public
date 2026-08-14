import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../database/production_database_coordinator.dart';
import '../../../database/production_schema_v16.dart';
import 'canonical_cloud_invoice_merchant_adapter.dart';
import 'canonical_cloud_invoice_metadata_adapter.dart';
import 'canonical_cloud_invoice_operation_adapter.dart';
import 'canonical_cloud_invoice_transaction_adapter.dart';
import 'cloud_invoice_persistence_executor.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_persistence_ports.dart';
import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_recovery_models.dart';

typedef CanonicalCloudInvoiceDatabaseProvider = Future<Database> Function();
typedef CanonicalCloudInvoiceFaultInjector = Future<void> Function(
  String checkpoint,
);

class CanonicalCloudInvoicePersistenceService {
  CanonicalCloudInvoicePersistenceService({
    CanonicalCloudInvoiceDatabaseProvider? databaseProvider,
    CloudInvoicePersistenceClock? clock,
    CloudInvoicePersistenceIdGenerator? ids,
    this.faultInjector,
  })  : _databaseProvider = databaseProvider ??
            (() => ProductionDatabaseCoordinator.instance.database),
        _clock = clock ?? const SystemCloudInvoicePersistenceClock(),
        _ids = ids ?? const UuidCloudInvoicePersistenceIdGenerator();

  final CanonicalCloudInvoiceDatabaseProvider _databaseProvider;
  final CloudInvoicePersistenceClock _clock;
  final CloudInvoicePersistenceIdGenerator _ids;
  final CanonicalCloudInvoiceFaultInjector? faultInjector;

  Future<CloudInvoicePersistenceResult> execute(
    CloudInvoicePersistenceRequest request,
  ) async {
    final database = await _databaseProvider();
    await createCanonicalProductionV16Tables(database);
    try {
      return await database.transaction((transaction) async {
        final scope = _CanonicalPersistenceScope(
          transaction,
          clock: _clock,
          ids: _ids,
          faultInjector: faultInjector,
        );
        final recoveryResult = await scope.prepareRetry(request);
        if (recoveryResult != null) {
          return recoveryResult;
        }
        final result = await scope.executor.execute(request);
        if (result.status == CloudInvoicePersistenceStatus.failed) {
          await scope.cleanupFailedOperation(request.operationKey);
        }
        if (result.status == CloudInvoicePersistenceStatus.rollbackFailed) {
          throw _RollbackResult(result);
        }
        return result;
      });
    } on _RollbackResult catch (error) {
      return error.result;
    } on _RecoveryResult catch (error) {
      return error.result;
    }
  }

  Future<CloudInvoiceRecoveryInspection> inspectRecovery(
    CloudInvoicePersistenceRequest request,
  ) async {
    final database = await _databaseProvider();
    await createCanonicalProductionV16Tables(database);
    return database.transaction((transaction) async {
      final scope = _CanonicalPersistenceScope(
        transaction,
        clock: _clock,
        ids: _ids,
        faultInjector: faultInjector,
      );
      return scope.inspectRecovery(request);
    });
  }

  Future<CloudInvoicePersistenceResult> rollback(String operationKey) async {
    final database = await _databaseProvider();
    await createCanonicalProductionV16Tables(database);
    try {
      return await database.transaction((transaction) async {
        final scope = _CanonicalPersistenceScope(
          transaction,
          clock: _clock,
          ids: _ids,
          faultInjector: faultInjector,
        );
        final result = await scope.executor.rollback(operationKey);
        if (result.status == CloudInvoicePersistenceStatus.rolledBack) {
          await scope.metadata.removeLinksForOperation(operationKey);
        }
        if (result.status == CloudInvoicePersistenceStatus.rollbackFailed) {
          throw _RollbackResult(result);
        }
        return result;
      });
    } on _RollbackResult catch (error) {
      return error.result;
    }
  }
}

class UuidCloudInvoicePersistenceIdGenerator
    implements CloudInvoicePersistenceIdGenerator {
  const UuidCloudInvoicePersistenceIdGenerator();

  @override
  String nextId(String namespace) => '$namespace-${const Uuid().v4()}';
}

class _RollbackResult implements Exception {
  const _RollbackResult(this.result);

  final CloudInvoicePersistenceResult result;
}

class _RecoveryResult implements Exception {
  const _RecoveryResult(this.result);

  final CloudInvoicePersistenceResult result;
}

class _CanonicalPersistenceScope {
  _CanonicalPersistenceScope(
    DatabaseExecutor db, {
    required CloudInvoicePersistenceClock clock,
    required CloudInvoicePersistenceIdGenerator ids,
    required CanonicalCloudInvoiceFaultInjector? faultInjector,
  })  : _clock = clock,
        _ids = ids,
        transactions = CanonicalCloudInvoiceTransactionAdapter(
          db,
          faultInjector: faultInjector,
        ),
        accounts = CanonicalCloudInvoiceAccountAdapter(db),
        merchants = CanonicalCloudInvoiceMerchantAdapter(
          db,
          faultInjector: faultInjector,
        ),
        metadata = CanonicalCloudInvoiceMetadataAdapter(
          db,
          faultInjector: faultInjector,
        ),
        operations = CanonicalCloudInvoiceOperationAdapter(
          db,
          faultInjector: faultInjector,
        ) {
    executor = CloudInvoicePersistenceExecutor(
      transactions: transactions,
      accounts: accounts,
      merchants: merchants,
      metadata: metadata,
      operations: operations,
      clock: clock,
      ids: ids,
    );
  }

  final CloudInvoicePersistenceClock _clock;
  final CloudInvoicePersistenceIdGenerator _ids;
  final CanonicalCloudInvoiceTransactionAdapter transactions;
  final CanonicalCloudInvoiceAccountAdapter accounts;
  final CanonicalCloudInvoiceMerchantAdapter merchants;
  final CanonicalCloudInvoiceMetadataAdapter metadata;
  final CanonicalCloudInvoiceOperationAdapter operations;
  late final CloudInvoicePersistenceExecutor executor;

  Future<CloudInvoiceRecoveryInspection> inspectRecovery(
    CloudInvoicePersistenceRequest request,
  ) async {
    final operation = await operations.loadOperation(request.operationKey);
    if (operation == null) {
      return CloudInvoiceRecoveryInspection(
        operationKey: request.operationKey,
        disposition: CloudInvoiceRecoveryDisposition.notFound,
        message: 'OPERATION_NOT_FOUND',
      );
    }
    if (operation.requestFingerprint != request.requestFingerprint) {
      return CloudInvoiceRecoveryInspection(
        operationKey: request.operationKey,
        disposition: CloudInvoiceRecoveryDisposition.requestConflict,
        message: 'OPERATION_KEY_CONFLICT',
        status: operation.status,
        action: operation.action,
      );
    }

    switch (operation.status) {
      case CloudInvoicePersistenceStatus.committed:
      case CloudInvoicePersistenceStatus.rolledBack:
      case CloudInvoicePersistenceStatus.alreadyApplied:
        return _inspection(
          operation,
          CloudInvoiceRecoveryDisposition.completed,
          'OPERATION_ALREADY_COMPLETED',
        );
      case CloudInvoicePersistenceStatus.planned:
        return _inspection(
          operation,
          CloudInvoiceRecoveryDisposition.inProgress,
          'OPERATION_ALREADY_IN_PROGRESS',
        );
      case CloudInvoicePersistenceStatus.failed:
      case CloudInvoicePersistenceStatus.preflightRejected:
        if (_isSafeRetryAction(operation.action)) {
          return _inspection(
            operation,
            CloudInvoiceRecoveryDisposition.retryable,
            'SAFE_RETRY_AVAILABLE',
          );
        }
        return _inspection(
          operation,
          CloudInvoiceRecoveryDisposition.manualReview,
          'OPERATION_RECOVERY_REQUIRES_MANUAL_REVIEW',
        );
      case CloudInvoicePersistenceStatus.rollbackFailed:
        return _inspection(
          operation,
          CloudInvoiceRecoveryDisposition.manualReview,
          'ROLLBACK_RECOVERY_REQUIRES_MANUAL_REVIEW',
        );
      case CloudInvoicePersistenceStatus.conflict:
        return _inspection(
          operation,
          CloudInvoiceRecoveryDisposition.manualReview,
          'OPERATION_CONFLICT_REQUIRES_NEW_REVIEW',
        );
    }
  }

  Future<CloudInvoicePersistenceResult?> prepareRetry(
    CloudInvoicePersistenceRequest request,
  ) async {
    final inspection = await inspectRecovery(request);
    if (inspection.disposition == CloudInvoiceRecoveryDisposition.notFound ||
        inspection.disposition == CloudInvoiceRecoveryDisposition.completed ||
        inspection.disposition == CloudInvoiceRecoveryDisposition.inProgress ||
        inspection.disposition ==
            CloudInvoiceRecoveryDisposition.requestConflict) {
      return null;
    }
    if (inspection.disposition == CloudInvoiceRecoveryDisposition.manualReview) {
      return CloudInvoicePersistenceResult(
        status: CloudInvoicePersistenceStatus.conflict,
        operationKey: request.operationKey,
        message: inspection.message,
        transactionId: request.decision.selectedTransactionId,
        accountId: request.decision.selectedAccountId,
      );
    }

    final operation = await operations.loadOperation(request.operationKey);
    if (operation == null) {
      return null;
    }
    try {
      await cleanupFailedOperation(request.operationKey);
      await operations.appendAudit(
        CloudInvoiceAuditRecord(
          id: _ids.nextId('cloud-invoice-audit'),
          operationKey: operation.operationKey,
          action: operation.action,
          status: operation.status,
          candidateReference: operation.candidateReference,
          transactionId: operation.transactionId,
          accountId: operation.accountId,
          merchantId: operation.merchantId,
          rollbackToken: operation.rollbackToken,
          message: 'RETRY_CLEANUP_COMPLETED',
          createdAt: _clock.now(),
        ),
      );
      await operations.removeOperation(request.operationKey);
      return null;
    } catch (error) {
      throw _RecoveryResult(
        CloudInvoicePersistenceResult(
          status: CloudInvoicePersistenceStatus.failed,
          operationKey: request.operationKey,
          message: 'RETRY_CLEANUP_FAILED:$error',
          transactionId: operation.transactionId,
          accountId: operation.accountId,
          merchantId: operation.merchantId,
          draftId: operation.draftId,
          rollbackToken: operation.rollbackToken,
        ),
      );
    }
  }

  Future<void> cleanupFailedOperation(String operationKey) async {
    await transactions.removeDraftsForOperation(operationKey);
    await metadata.removeLinksForOperation(operationKey);
    await operations.removeBeforeImagesForOperation(operationKey);
  }

  CloudInvoiceRecoveryInspection _inspection(
    CloudInvoiceOperationRecord operation,
    CloudInvoiceRecoveryDisposition disposition,
    String message,
  ) {
    return CloudInvoiceRecoveryInspection(
      operationKey: operation.operationKey,
      disposition: disposition,
      message: message,
      status: operation.status,
      action: operation.action,
    );
  }

  bool _isSafeRetryAction(CloudInvoiceReconciliationOutcome action) {
    return action == CloudInvoiceReconciliationOutcome.createNewDraft ||
        action == CloudInvoiceReconciliationOutcome.enrichExisting ||
        action == CloudInvoiceReconciliationOutcome.exactDuplicate ||
        action == CloudInvoiceReconciliationOutcome.keepSeparate;
  }
}
