import '../../account/account_record.dart';
import '../../merchant/merchant_record.dart';
import '../../transaction/transaction_record.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_persistence_ports.dart';
import 'cloud_invoice_reconciliation_models.dart';

class CloudInvoicePersistenceExecutor {
  const CloudInvoicePersistenceExecutor({
    required this.transactions,
    required this.accounts,
    required this.merchants,
    required this.metadata,
    required this.operations,
    required this.clock,
    required this.ids,
  });

  final CloudInvoiceTransactionPersistencePort transactions;
  final CloudInvoiceAccountPersistencePort accounts;
  final CloudInvoiceMerchantPersistencePort merchants;
  final CloudInvoiceMetadataPersistencePort metadata;
  final CloudInvoiceOperationPersistencePort operations;
  final CloudInvoicePersistenceClock clock;
  final CloudInvoicePersistenceIdGenerator ids;

  Future<CloudInvoicePersistenceResult> execute(
    CloudInvoicePersistenceRequest request,
  ) async {
    final existingOperation =
        await operations.loadOperation(request.operationKey);
    if (existingOperation != null) {
      if (existingOperation.requestFingerprint != request.requestFingerprint) {
        return _result(
          request,
          CloudInvoicePersistenceStatus.conflict,
          'OPERATION_KEY_CONFLICT',
          operation: existingOperation,
        );
      }
      if (_isCompleted(existingOperation.status)) {
        return _result(
          request,
          CloudInvoicePersistenceStatus.alreadyApplied,
          'OPERATION_ALREADY_APPLIED',
          operation: existingOperation,
        );
      }
      return _result(
        request,
        CloudInvoicePersistenceStatus.conflict,
        'OPERATION_ALREADY_IN_PROGRESS',
        operation: existingOperation,
      );
    }

    final preflight = await _preflight(request);
    if (preflight.failure != null) return preflight.failure!;

    final now = clock.now();
    var operation = CloudInvoiceOperationRecord(
      operationKey: request.operationKey,
      requestFingerprint: request.requestFingerprint,
      action: request.decision.action,
      status: CloudInvoicePersistenceStatus.planned,
      candidateReference: request.decision.candidateReference,
      transactionId: request.decision.selectedTransactionId,
      accountId: request.decision.selectedAccountId,
      createdAt: now,
      updatedAt: now,
    );
    await operations.saveOperation(operation);

    switch (request.decision.action) {
      case CloudInvoiceReconciliationOutcome.exactDuplicate:
      case CloudInvoiceReconciliationOutcome.keepSeparate:
        operation = await _commitAuditOnly(request, operation);
        return _result(
          request,
          CloudInvoicePersistenceStatus.committed,
          'DECISION_RECORDED',
          operation: operation,
        );
      case CloudInvoiceReconciliationOutcome.createNewDraft:
        return _createDraft(request, operation, preflight.context!);
      case CloudInvoiceReconciliationOutcome.enrichExisting:
        return _enrichExisting(request, operation, preflight.context!);
      case CloudInvoiceReconciliationOutcome.replaceExisting:
        return _replaceExisting(request, operation, preflight.context!);
      case CloudInvoiceReconciliationOutcome.ambiguous:
      case CloudInvoiceReconciliationOutcome.blocked:
        return _failPlannedOperation(
          request,
          operation,
          CloudInvoicePersistenceStatus.preflightRejected,
          'NON_EXECUTABLE_REVIEW_ACTION',
        );
    }
  }

  Future<CloudInvoicePersistenceResult> rollback(String operationKey) async {
    final operation = await operations.loadOperation(operationKey);
    if (operation == null) {
      return CloudInvoicePersistenceResult(
        status: CloudInvoicePersistenceStatus.preflightRejected,
        operationKey: operationKey,
        message: 'OPERATION_NOT_FOUND',
      );
    }
    if (operation.status == CloudInvoicePersistenceStatus.rolledBack) {
      return CloudInvoicePersistenceResult(
        status: CloudInvoicePersistenceStatus.alreadyApplied,
        operationKey: operationKey,
        message: 'ROLLBACK_ALREADY_APPLIED',
        transactionId: operation.transactionId,
        accountId: operation.accountId,
        merchantId: operation.merchantId,
        rollbackToken: operation.rollbackToken,
      );
    }
    if (operation.status != CloudInvoicePersistenceStatus.committed ||
        operation.action !=
            CloudInvoiceReconciliationOutcome.replaceExisting ||
        operation.rollbackToken == null) {
      return CloudInvoicePersistenceResult(
        status: CloudInvoicePersistenceStatus.preflightRejected,
        operationKey: operationKey,
        message: 'ROLLBACK_NOT_AVAILABLE',
        transactionId: operation.transactionId,
      );
    }

    final beforeImage =
        await operations.loadBeforeImage(operation.rollbackToken!);
    if (beforeImage == null) {
      final failed = operation.copyWith(
        status: CloudInvoicePersistenceStatus.rollbackFailed,
        failureMessage: 'BEFORE_IMAGE_NOT_FOUND',
        updatedAt: clock.now(),
      );
      await operations.saveOperation(failed);
      return _operationResult(failed, 'BEFORE_IMAGE_NOT_FOUND');
    }

    try {
      await transactions.restoreTransaction(beforeImage.transaction);
      final rolledBack = operation.copyWith(
        status: CloudInvoicePersistenceStatus.rolledBack,
        clearFailureMessage: true,
        updatedAt: clock.now(),
      );
      await operations.saveOperation(rolledBack);
      await operations.appendAudit(
        CloudInvoiceAuditRecord(
          id: ids.nextId('cloud-invoice-audit'),
          operationKey: operation.operationKey,
          action: operation.action,
          status: CloudInvoicePersistenceStatus.rolledBack,
          candidateReference: operation.candidateReference,
          transactionId: operation.transactionId,
          accountId: operation.accountId,
          merchantId: operation.merchantId,
          rollbackToken: operation.rollbackToken,
          message: 'REPLACEMENT_ROLLED_BACK',
          createdAt: clock.now(),
        ),
      );
      return _operationResult(rolledBack, 'REPLACEMENT_ROLLED_BACK');
    } catch (error) {
      final failed = operation.copyWith(
        status: CloudInvoicePersistenceStatus.rollbackFailed,
        failureMessage: error.toString(),
        updatedAt: clock.now(),
      );
      await operations.saveOperation(failed);
      return _operationResult(failed, 'ROLLBACK_FAILED');
    }
  }

  Future<_Preflight> _preflight(
    CloudInvoicePersistenceRequest request,
  ) async {
    final candidate = request.facts.candidate;
    final decision = request.decision;

    if (decision.candidateReference != candidate.duplicateKey) {
      return _Preflight.failed(
        _result(
          request,
          CloudInvoicePersistenceStatus.preflightRejected,
          'CANDIDATE_REFERENCE_MISMATCH',
        ),
      );
    }
    if (candidate.totalAmount <= 0) {
      return _Preflight.failed(
        _result(
          request,
          CloudInvoicePersistenceStatus.preflightRejected,
          'NON_POSITIVE_CANDIDATE_TOTAL',
        ),
      );
    }
    if (request.facts.hasKnownCurrency &&
        _currencyByExactCode(request.facts.currencyCode!) == null) {
      return _Preflight.failed(
        _result(
          request,
          CloudInvoicePersistenceStatus.preflightRejected,
          'UNSUPPORTED_CURRENCY_CODE',
        ),
      );
    }

    TransactionRecord? transaction;
    if (_usesExistingTransaction(decision.action)) {
      final transactionId = decision.selectedTransactionId;
      if (transactionId == null || transactionId.trim().isEmpty) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.preflightRejected,
            'TRANSACTION_SELECTION_REQUIRED',
          ),
        );
      }
      transaction = await transactions.loadTransaction(transactionId);
      if (transaction == null) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.conflict,
            'TRANSACTION_NOT_FOUND',
          ),
        );
      }
      final expected = request.expectedTransactionFingerprint;
      if (expected == null || expected.trim().isEmpty) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.preflightRejected,
            'TRANSACTION_FINGERPRINT_REQUIRED',
          ),
        );
      }
      if (transactionFingerprint(transaction) != expected) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.conflict,
            'TRANSACTION_CHANGED_AFTER_REVIEW',
          ),
        );
      }
      if (!_sameCalendarDate(transaction.occurredAt, candidate.invoiceDate)) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.conflict,
            'TRANSACTION_DATE_CHANGED_AFTER_REVIEW',
          ),
        );
      }
    }

    AccountRecord? account;
    if (decision.action == CloudInvoiceReconciliationOutcome.createNewDraft) {
      final accountId = decision.selectedAccountId?.trim() ?? '';
      if (accountId.isNotEmpty) {
        account = await accounts.loadAccount(accountId);
        if (account == null) {
          return _Preflight.failed(
            _result(
              request,
              CloudInvoicePersistenceStatus.conflict,
              'ACCOUNT_NOT_FOUND',
            ),
          );
        }
        if (account.isArchived) {
          return _Preflight.failed(
            _result(
              request,
              CloudInvoicePersistenceStatus.conflict,
              'ACCOUNT_ARCHIVED_AFTER_REVIEW',
            ),
          );
        }
        final expected = request.expectedAccountFingerprint;
        if (expected == null || expected.trim().isEmpty) {
          return _Preflight.failed(
            _result(
              request,
              CloudInvoicePersistenceStatus.preflightRejected,
              'ACCOUNT_FINGERPRINT_REQUIRED',
            ),
          );
        }
        if (accountFingerprint(account) != expected) {
          return _Preflight.failed(
            _result(
              request,
              CloudInvoicePersistenceStatus.conflict,
              'ACCOUNT_CHANGED_AFTER_REVIEW',
            ),
          );
        }
        if (request.facts.hasKnownCurrency &&
            account.currency.code !=
                request.facts.currencyCode!.trim().toUpperCase()) {
          return _Preflight.failed(
            _result(
              request,
              CloudInvoicePersistenceStatus.conflict,
              'ACCOUNT_CURRENCY_CONFLICT',
            ),
          );
        }
      }
    }

    MerchantRecord? merchant;
    if (decision.merchantProposalConfirmed) {
      final sellerName = candidate.sellerName.trim();
      if (sellerName.isEmpty) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.preflightRejected,
            'MERCHANT_NAME_REQUIRED',
          ),
        );
      }
      merchant = await merchants.findByNormalizedName(
        normalizeMerchantName(sellerName),
      );
      if (merchant != null && merchant.isArchived) {
        return _Preflight.failed(
          _result(
            request,
            CloudInvoicePersistenceStatus.conflict,
            'MERCHANT_ARCHIVED_AFTER_REVIEW',
          ),
        );
      }
      final expected = request.expectedMerchantFingerprint;
      if (expected != null && expected.trim().isNotEmpty) {
        if (merchant == null || merchantFingerprint(merchant) != expected) {
          return _Preflight.failed(
            _result(
              request,
              CloudInvoicePersistenceStatus.conflict,
              'MERCHANT_CHANGED_AFTER_REVIEW',
            ),
          );
        }
      }
    }

    if (decision.action ==
            CloudInvoiceReconciliationOutcome.replaceExisting &&
        !decision.replacementSecondConfirmationCompleted) {
      return _Preflight.failed(
        _result(
          request,
          CloudInvoicePersistenceStatus.preflightRejected,
          'REPLACEMENT_SECOND_CONFIRMATION_REQUIRED',
        ),
      );
    }

    return _Preflight.ok(
      _PreflightContext(
        transaction: transaction,
        account: account,
        merchant: merchant,
      ),
    );
  }

  Future<CloudInvoiceOperationRecord> _commitAuditOnly(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
  ) async {
    final committed = operation.copyWith(
      status: CloudInvoicePersistenceStatus.committed,
      clearFailureMessage: true,
      updatedAt: clock.now(),
    );
    await operations.appendAudit(_audit(request, committed, 'DECISION_RECORDED'));
    await operations.saveOperation(committed);
    return committed;
  }

  Future<CloudInvoicePersistenceResult> _createDraft(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
    _PreflightContext context,
  ) async {
    CloudInvoiceMerchantCreationResult? merchantResult;
    try {
      merchantResult = await _ensureMerchant(request, context.merchant);
      final draftId = ids.nextId('cloud-invoice-draft');
      final candidate = request.facts.candidate;
      final account = context.account;
      final draft = CloudInvoiceDraftRecord(
        id: draftId,
        operationKey: request.operationKey,
        candidateReference: request.decision.candidateReference,
        accountId: account?.id ?? '',
        accountName: account?.displayName ?? '',
        amount: candidate.totalAmount,
        invoiceDate: candidate.invoiceDate,
        timePrecision: request.facts.timePrecision,
        timeSource: request.facts.timeSource,
        currencyCode: request.facts.hasKnownCurrency
            ? request.facts.currencyCode!.trim().toUpperCase()
            : null,
        merchantId: merchantResult?.merchant.id,
        invoiceNumber: candidate.invoiceNumber,
        sellerIdentifier: candidate.sellerIdentifier,
        sellerName: candidate.sellerName,
        taxAmount: candidate.taxAmount,
        lineItems: List.unmodifiable(candidate.lineItems),
        createdAt: clock.now(),
      );
      await transactions.createDraft(draft);
      final committed = operation.copyWith(
        status: CloudInvoicePersistenceStatus.committed,
        accountId: account?.id,
        merchantId: merchantResult?.merchant.id,
        draftId: draftId,
        clearFailureMessage: true,
        updatedAt: clock.now(),
      );
      await operations.appendAudit(_audit(request, committed, 'DRAFT_CREATED'));
      await operations.saveOperation(committed);
      return _operationResult(committed, 'DRAFT_CREATED');
    } catch (error) {
      return _handleFailure(
        request,
        operation,
        error,
        merchantResult: merchantResult,
      );
    }
  }

  Future<CloudInvoicePersistenceResult> _enrichExisting(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
    _PreflightContext context,
  ) async {
    CloudInvoiceMerchantCreationResult? merchantResult;
    try {
      merchantResult = await _ensureMerchant(request, context.merchant);
      final transaction = context.transaction!;
      await metadata.upsertLink(
        _buildLink(
          request,
          transaction.id,
          merchantResult?.merchant.id,
        ),
      );
      final committed = operation.copyWith(
        status: CloudInvoicePersistenceStatus.committed,
        transactionId: transaction.id,
        merchantId: merchantResult?.merchant.id,
        clearFailureMessage: true,
        updatedAt: clock.now(),
      );
      await operations.appendAudit(_audit(request, committed, 'METADATA_ENRICHED'));
      await operations.saveOperation(committed);
      return _operationResult(committed, 'METADATA_ENRICHED');
    } catch (error) {
      return _handleFailure(
        request,
        operation,
        error,
        merchantResult: merchantResult,
      );
    }
  }

  Future<CloudInvoicePersistenceResult> _replaceExisting(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
    _PreflightContext context,
  ) async {
    final before = context.transaction!;
    final rollbackToken = ids.nextId('cloud-invoice-rollback');
    final beforeImage = CloudInvoiceBeforeImageRecord(
      rollbackToken: rollbackToken,
      operationKey: request.operationKey,
      transaction: before,
      transactionFingerprint: transactionFingerprint(before),
      createdAt: clock.now(),
    );
    await operations.saveBeforeImage(beforeImage);

    CloudInvoiceMerchantCreationResult? merchantResult;
    var transactionMutated = false;
    try {
      merchantResult = await _ensureMerchant(request, context.merchant);
      final replacement = _replacementTransaction(
        request,
        before,
        merchantResult?.merchant,
      );
      await transactions.replaceTransaction(replacement);
      transactionMutated = true;
      await metadata.upsertLink(
        _buildLink(
          request,
          replacement.id,
          merchantResult?.merchant.id,
        ),
      );
      final committed = operation.copyWith(
        status: CloudInvoicePersistenceStatus.committed,
        transactionId: replacement.id,
        merchantId: merchantResult?.merchant.id,
        rollbackToken: rollbackToken,
        clearFailureMessage: true,
        updatedAt: clock.now(),
      );
      await operations.appendAudit(
        _audit(request, committed, 'TRANSACTION_REPLACED'),
      );
      await operations.saveOperation(committed);
      return _operationResult(committed, 'TRANSACTION_REPLACED');
    } catch (error) {
      if (transactionMutated) {
        try {
          await transactions.restoreTransaction(before);
        } catch (restoreError) {
          final failed = operation.copyWith(
            status: CloudInvoicePersistenceStatus.rollbackFailed,
            rollbackToken: rollbackToken,
            failureMessage: '$error | restore: $restoreError',
            updatedAt: clock.now(),
          );
          await operations.saveOperation(failed);
          return _operationResult(failed, 'REPLACEMENT_ROLLBACK_FAILED');
        }
      }
      return _handleFailure(
        request,
        operation.copyWith(rollbackToken: rollbackToken),
        error,
        merchantResult: merchantResult,
      );
    }
  }

  Future<CloudInvoiceMerchantCreationResult?> _ensureMerchant(
    CloudInvoicePersistenceRequest request,
    MerchantRecord? existing,
  ) async {
    if (!request.decision.merchantProposalConfirmed) return null;
    if (existing != null) {
      return CloudInvoiceMerchantCreationResult(
        merchant: existing,
        createdForOperation: false,
      );
    }
    final now = clock.now();
    final candidate = request.facts.candidate;
    return merchants.createMerchant(
      merchant: MerchantRecord(
        id: ids.nextId('cloud-invoice-merchant'),
        name: candidate.sellerName.trim(),
        note: candidate.sellerIdentifier.trim().isEmpty
            ? ''
            : '雲端發票賣方統編 ${candidate.sellerIdentifier.trim()}',
        createdAt: now,
        updatedAt: now,
      ),
      operationKey: request.operationKey,
    );
  }

  Future<CloudInvoicePersistenceResult> _handleFailure(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
    Object error, {
    CloudInvoiceMerchantCreationResult? merchantResult,
  }) async {
    var message = error.toString();
    if (merchantResult?.createdForOperation == true) {
      final merchantId = merchantResult!.merchant.id;
      try {
        final referenced = await merchants.hasExternalReferences(merchantId);
        if (!referenced) {
          await merchants.compensateCreatedMerchant(
            merchantId: merchantId,
            operationKey: request.operationKey,
          );
          message = '$message | merchant compensated';
        } else {
          message = '$message | merchant retained for review';
        }
      } catch (compensationError) {
        message = '$message | merchant compensation failed: $compensationError';
      }
    }
    return _failPlannedOperation(
      request,
      operation,
      CloudInvoicePersistenceStatus.failed,
      message,
    );
  }

  Future<CloudInvoicePersistenceResult> _failPlannedOperation(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
    CloudInvoicePersistenceStatus status,
    String message,
  ) async {
    final failed = operation.copyWith(
      status: status,
      failureMessage: message,
      updatedAt: clock.now(),
    );
    await operations.appendAudit(_audit(request, failed, message));
    await operations.saveOperation(failed);
    return _operationResult(failed, message);
  }

  CloudInvoiceMetadataLinkRecord _buildLink(
    CloudInvoicePersistenceRequest request,
    String transactionId,
    String? merchantId,
  ) {
    final candidate = request.facts.candidate;
    return CloudInvoiceMetadataLinkRecord(
      id: ids.nextId('cloud-invoice-link'),
      operationKey: request.operationKey,
      transactionId: transactionId,
      candidateReference: request.decision.candidateReference,
      invoiceNumber: candidate.invoiceNumber,
      sellerIdentifier: candidate.sellerIdentifier,
      sellerName: candidate.sellerName,
      invoiceDate: candidate.invoiceDate,
      timePrecision: request.facts.timePrecision,
      timeSource: request.facts.timeSource,
      currencyCode: request.facts.hasKnownCurrency
          ? request.facts.currencyCode!.trim().toUpperCase()
          : null,
      currencySource: request.facts.currencySource,
      taxAmount: candidate.taxAmount,
      merchantId: merchantId,
      lineItems: List.unmodifiable(candidate.lineItems),
      createdAt: clock.now(),
    );
  }

  TransactionRecord _replacementTransaction(
    CloudInvoicePersistenceRequest request,
    TransactionRecord before,
    MerchantRecord? merchant,
  ) {
    final candidate = request.facts.candidate;
    final knownCurrency = request.facts.hasKnownCurrency
        ? _currencyByExactCode(request.facts.currencyCode!)
        : null;
    final occurredAt = request.facts.hasExactTime
        ? candidate.invoiceDate
        : before.occurredAt;
    final merchantName = request.decision.merchantProposalConfirmed &&
            candidate.sellerName.trim().isNotEmpty
        ? candidate.sellerName.trim()
        : before.merchantName;

    return before.copyWith(
      amount: candidate.totalAmount,
      occurredAt: occurredAt,
      merchantName: merchant?.name ?? merchantName,
      currency: knownCurrency ?? before.currency,
    );
  }

  CloudInvoiceAuditRecord _audit(
    CloudInvoicePersistenceRequest request,
    CloudInvoiceOperationRecord operation,
    String message,
  ) {
    return CloudInvoiceAuditRecord(
      id: ids.nextId('cloud-invoice-audit'),
      operationKey: operation.operationKey,
      action: operation.action,
      status: operation.status,
      candidateReference: operation.candidateReference,
      transactionId: operation.transactionId,
      accountId: operation.accountId,
      merchantId: operation.merchantId,
      rollbackToken: operation.rollbackToken,
      message: message,
      createdAt: clock.now(),
    );
  }

  CloudInvoicePersistenceResult _result(
    CloudInvoicePersistenceRequest request,
    CloudInvoicePersistenceStatus status,
    String message, {
    CloudInvoiceOperationRecord? operation,
  }) {
    return CloudInvoicePersistenceResult(
      status: status,
      operationKey: request.operationKey,
      message: message,
      transactionId:
          operation?.transactionId ?? request.decision.selectedTransactionId,
      accountId: operation?.accountId ?? request.decision.selectedAccountId,
      merchantId: operation?.merchantId,
      draftId: operation?.draftId,
      rollbackToken: operation?.rollbackToken,
    );
  }

  CloudInvoicePersistenceResult _operationResult(
    CloudInvoiceOperationRecord operation,
    String message,
  ) {
    return CloudInvoicePersistenceResult(
      status: operation.status,
      operationKey: operation.operationKey,
      message: message,
      transactionId: operation.transactionId,
      accountId: operation.accountId,
      merchantId: operation.merchantId,
      draftId: operation.draftId,
      rollbackToken: operation.rollbackToken,
    );
  }

  bool _usesExistingTransaction(CloudInvoiceReconciliationOutcome action) {
    return action == CloudInvoiceReconciliationOutcome.exactDuplicate ||
        action == CloudInvoiceReconciliationOutcome.enrichExisting ||
        action == CloudInvoiceReconciliationOutcome.replaceExisting;
  }

  bool _isCompleted(CloudInvoicePersistenceStatus status) {
    return status == CloudInvoicePersistenceStatus.committed ||
        status == CloudInvoicePersistenceStatus.rolledBack;
  }

  CurrencyCode? _currencyByExactCode(String value) {
    final code = value.trim().toUpperCase();
    for (final currency in CurrencyCode.values) {
      if (currency.code == code) return currency;
    }
    return null;
  }

  bool _sameCalendarDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _Preflight {
  const _Preflight._({this.context, this.failure});

  factory _Preflight.ok(_PreflightContext context) =>
      _Preflight._(context: context);

  factory _Preflight.failed(CloudInvoicePersistenceResult failure) =>
      _Preflight._(failure: failure);

  final _PreflightContext? context;
  final CloudInvoicePersistenceResult? failure;
}

class _PreflightContext {
  const _PreflightContext({
    required this.transaction,
    required this.account,
    required this.merchant,
  });

  final TransactionRecord? transaction;
  final AccountRecord? account;
  final MerchantRecord? merchant;
}
