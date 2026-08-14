import '../../account/account_record.dart';
import '../../merchant/merchant_record.dart';
import '../../transaction/transaction_record.dart';
import '../cloud_invoice_candidate.dart';
import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_reconciliation_review_decision.dart';

enum CloudInvoicePersistenceStatus {
  planned,
  preflightRejected,
  committed,
  alreadyApplied,
  conflict,
  failed,
  rolledBack,
  rollbackFailed,
}

class CloudInvoicePersistenceRequest {
  const CloudInvoicePersistenceRequest({
    required this.facts,
    required this.decision,
    required this.requestedAt,
    this.expectedTransactionFingerprint,
    this.expectedAccountFingerprint,
    this.expectedMerchantFingerprint,
  });

  final CloudInvoiceCandidateFacts facts;
  final CloudInvoiceReconciliationReviewDecision decision;
  final DateTime requestedAt;
  final String? expectedTransactionFingerprint;
  final String? expectedAccountFingerprint;
  final String? expectedMerchantFingerprint;

  String get operationKey {
    return <String>[
      'cloud-invoice',
      _escape(decision.candidateReference),
      decision.action.name,
      _escape(decision.selectedTransactionId ?? '-'),
      _escape(
        decision.action == CloudInvoiceReconciliationOutcome.createNewDraft
            ? '-'
            : (decision.selectedAccountId ?? '-'),
      ),
      decision.merchantProposalConfirmed ? 'merchant' : 'no-merchant',
    ].join(':');
  }

  String get requestFingerprint {
    final candidate = facts.candidate;
    return <String>[
      operationKey,
      _escape(candidate.invoiceNumber),
      _escape(candidate.sellerIdentifier),
      _escape(candidate.sellerName),
      candidate.totalAmount.toStringAsFixed(6),
      candidate.invoiceDate.toIso8601String(),
      facts.timePrecision.name,
      facts.timeSource.name,
      _escape(facts.currencyCode ?? ''),
      facts.currencySource.name,
      _escape(expectedTransactionFingerprint ?? ''),
      _escape(expectedAccountFingerprint ?? ''),
      _escape(expectedMerchantFingerprint ?? ''),
      decision.replacementSecondConfirmationCompleted ? 'replace-confirmed' : 'replace-not-confirmed',
    ].join('|');
  }
}

class CloudInvoiceDraftRecord {
  const CloudInvoiceDraftRecord({
    required this.id,
    required this.operationKey,
    required this.candidateReference,
    required this.accountId,
    required this.accountName,
    required this.amount,
    required this.invoiceDate,
    required this.timePrecision,
    required this.timeSource,
    required this.invoiceNumber,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.lineItems,
    required this.createdAt,
    this.currencyCode,
    this.currencySource = CloudInvoiceCurrencySource.unknown,
    this.merchantId,
    this.taxAmount,
  });

  final String id;
  final String operationKey;
  final String candidateReference;
  final String accountId;
  final String accountName;
  final double amount;
  final DateTime invoiceDate;
  final CloudInvoiceTimePrecision timePrecision;
  final CloudInvoiceTimeSource timeSource;
  final String? currencyCode;
  final CloudInvoiceCurrencySource currencySource;
  final String? merchantId;
  final String invoiceNumber;
  final String sellerIdentifier;
  final String sellerName;
  final double? taxAmount;
  final List<CloudInvoiceLineItem> lineItems;
  final DateTime createdAt;

  bool get isFormalTransaction => false;
}

class CloudInvoiceMetadataLinkRecord {
  const CloudInvoiceMetadataLinkRecord({
    required this.id,
    required this.operationKey,
    required this.transactionId,
    required this.candidateReference,
    required this.invoiceNumber,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.invoiceDate,
    required this.timePrecision,
    required this.timeSource,
    required this.currencySource,
    required this.lineItems,
    required this.createdAt,
    this.currencyCode,
    this.taxAmount,
    this.merchantId,
  });

  final String id;
  final String operationKey;
  final String transactionId;
  final String candidateReference;
  final String invoiceNumber;
  final String sellerIdentifier;
  final String sellerName;
  final DateTime invoiceDate;
  final CloudInvoiceTimePrecision timePrecision;
  final CloudInvoiceTimeSource timeSource;
  final String? currencyCode;
  final CloudInvoiceCurrencySource currencySource;
  final double? taxAmount;
  final String? merchantId;
  final List<CloudInvoiceLineItem> lineItems;
  final DateTime createdAt;
}

class CloudInvoiceBeforeImageRecord {
  const CloudInvoiceBeforeImageRecord({
    required this.rollbackToken,
    required this.operationKey,
    required this.transaction,
    required this.transactionFingerprint,
    required this.createdAt,
  });

  final String rollbackToken;
  final String operationKey;
  final TransactionRecord transaction;
  final String transactionFingerprint;
  final DateTime createdAt;
}

class CloudInvoiceAuditRecord {
  const CloudInvoiceAuditRecord({
    required this.id,
    required this.operationKey,
    required this.action,
    required this.status,
    required this.candidateReference,
    required this.message,
    required this.createdAt,
    this.transactionId,
    this.accountId,
    this.merchantId,
    this.rollbackToken,
  });

  final String id;
  final String operationKey;
  final CloudInvoiceReconciliationOutcome action;
  final CloudInvoicePersistenceStatus status;
  final String candidateReference;
  final String? transactionId;
  final String? accountId;
  final String? merchantId;
  final String? rollbackToken;
  final String message;
  final DateTime createdAt;
}

class CloudInvoiceOperationRecord {
  const CloudInvoiceOperationRecord({
    required this.operationKey,
    required this.requestFingerprint,
    required this.action,
    required this.status,
    required this.candidateReference,
    required this.createdAt,
    required this.updatedAt,
    this.transactionId,
    this.accountId,
    this.merchantId,
    this.draftId,
    this.rollbackToken,
    this.failureMessage,
  });

  final String operationKey;
  final String requestFingerprint;
  final CloudInvoiceReconciliationOutcome action;
  final CloudInvoicePersistenceStatus status;
  final String candidateReference;
  final String? transactionId;
  final String? accountId;
  final String? merchantId;
  final String? draftId;
  final String? rollbackToken;
  final String? failureMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  CloudInvoiceOperationRecord copyWith({
    CloudInvoicePersistenceStatus? status,
    String? transactionId,
    String? accountId,
    String? merchantId,
    String? draftId,
    String? rollbackToken,
    String? failureMessage,
    bool clearFailureMessage = false,
    DateTime? updatedAt,
  }) {
    return CloudInvoiceOperationRecord(
      operationKey: operationKey,
      requestFingerprint: requestFingerprint,
      action: action,
      status: status ?? this.status,
      candidateReference: candidateReference,
      transactionId: transactionId ?? this.transactionId,
      accountId: accountId ?? this.accountId,
      merchantId: merchantId ?? this.merchantId,
      draftId: draftId ?? this.draftId,
      rollbackToken: rollbackToken ?? this.rollbackToken,
      failureMessage: clearFailureMessage
          ? null
          : (failureMessage ?? this.failureMessage),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CloudInvoiceMerchantCreationResult {
  const CloudInvoiceMerchantCreationResult({
    required this.merchant,
    required this.createdForOperation,
  });

  final MerchantRecord merchant;
  final bool createdForOperation;
}

class CloudInvoicePersistenceResult {
  const CloudInvoicePersistenceResult({
    required this.status,
    required this.operationKey,
    required this.message,
    this.transactionId,
    this.accountId,
    this.merchantId,
    this.draftId,
    this.rollbackToken,
  });

  final CloudInvoicePersistenceStatus status;
  final String operationKey;
  final String message;
  final String? transactionId;
  final String? accountId;
  final String? merchantId;
  final String? draftId;
  final String? rollbackToken;

  bool get committed => status == CloudInvoicePersistenceStatus.committed;
  bool get idempotentReplay =>
      status == CloudInvoicePersistenceStatus.alreadyApplied;
}

String transactionFingerprint(TransactionRecord record) {
  return <String>[
    _escape(record.id),
    record.type.name,
    record.amount.toStringAsFixed(6),
    _escape(record.category),
    record.occurredAt.toIso8601String(),
    _escape(record.accountName),
    _escape(record.memberName),
    _escape(record.merchantName),
    _escape(record.tagName),
    _escape(record.note),
    record.currency.code,
    record.exchangeRateToBase.toStringAsFixed(8),
    _escape(record.fromAccountName ?? ''),
    _escape(record.toAccountName ?? ''),
    _escape(record.repaymentGroupId ?? ''),
  ].join('|');
}

String accountFingerprint(AccountRecord record) {
  return <String>[
    _escape(record.id),
    _escape(record.name),
    _escape(record.suffix),
    record.type.name,
    record.currency.code,
    record.isArchived ? 'archived' : 'active',
    record.sortOrder.toString(),
  ].join('|');
}

String merchantFingerprint(MerchantRecord record) {
  return <String>[
    _escape(record.id),
    _escape(record.name),
    _escape(record.alias),
    record.isArchived ? 'archived' : 'active',
    record.updatedAt.toIso8601String(),
  ].join('|');
}

String normalizeMerchantName(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_.，。、／/()（）]'), '');
}

String _escape(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('|', '\\|').replaceAll(':', '\\:');
}
