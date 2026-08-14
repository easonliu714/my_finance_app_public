import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_executor.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_ports.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_review_decision.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('transaction and account fingerprints detect reviewed-state changes', () {
    final transaction = _transaction();
    final account = _account();

    expect(
      transactionFingerprint(transaction),
      isNot(transactionFingerprint(transaction.copyWith(note: 'changed'))),
    );
    expect(
      accountFingerprint(account),
      isNot(accountFingerprint(account.copyWith(isArchived: true))),
    );
  });

  test('exact duplicate records audit only and does not mutate transaction', () async {
    final fixture = _Fixture();
    final transaction = _transaction();
    fixture.transactions.records[transaction.id] = transaction;
    final request = _request(
      facts: _facts(),
      action: CloudInvoiceReconciliationOutcome.exactDuplicate,
      selectedTransactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(fixture.transactions.replaceCount, 0);
    expect(fixture.transactions.drafts, isEmpty);
    expect(fixture.metadata.links, isEmpty);
    expect(fixture.operations.audits.single.message, 'DECISION_RECORDED');
  });

  test('keep separate records audit only without requiring a transaction', () async {
    final fixture = _Fixture();
    final request = _request(
      facts: _facts(),
      action: CloudInvoiceReconciliationOutcome.keepSeparate,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(fixture.transactions.replaceCount, 0);
    expect(fixture.transactions.drafts, isEmpty);
    expect(fixture.metadata.links, isEmpty);
  });

  test('new draft preserves date-only and unknown currency semantics', () async {
    final fixture = _Fixture();
    final account = _account();
    fixture.accounts.records[account.id] = account;
    final facts = _facts();
    final request = _request(
      facts: facts,
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      selectedAccountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(fixture.transactions.drafts, hasLength(1));
    final draft = fixture.transactions.drafts.single;
    expect(draft.isFormalTransaction, isFalse);
    expect(draft.timePrecision, CloudInvoiceTimePrecision.dateOnly);
    expect(draft.currencyCode, isNull);
    expect(draft.invoiceDate, facts.candidate.invoiceDate);
    expect(draft.accountId, account.id);
  });

  test('replaying committed draft request is idempotent', () async {
    final fixture = _Fixture();
    final account = _account();
    fixture.accounts.records[account.id] = account;
    final request = _request(
      facts: _facts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      selectedAccountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
    );

    final first = await fixture.executor.execute(request);
    final second = await fixture.executor.execute(request);

    expect(first.status, CloudInvoicePersistenceStatus.committed);
    expect(second.status, CloudInvoicePersistenceStatus.alreadyApplied);
    expect(fixture.transactions.drafts, hasLength(1));
    expect(fixture.operations.audits, hasLength(1));
  });

  test('archived or changed account is rejected before draft mutation', () async {
    final fixture = _Fixture();
    final reviewed = _account();
    fixture.accounts.records[reviewed.id] = reviewed.copyWith(isArchived: true);
    final request = _request(
      facts: _facts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      selectedAccountId: reviewed.id,
      expectedAccountFingerprint: accountFingerprint(reviewed),
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.conflict);
    expect(result.message, 'ACCOUNT_ARCHIVED_AFTER_REVIEW');
    expect(fixture.transactions.drafts, isEmpty);
    expect(fixture.operations.records, isEmpty);
  });

  test('enrichment writes sidecar metadata and preserves transaction fields', () async {
    final fixture = _Fixture();
    final transaction = _transaction(note: 'user note', category: '餐飲');
    fixture.transactions.records[transaction.id] = transaction;
    final request = _request(
      facts: _facts(amount: transaction.amount),
      action: CloudInvoiceReconciliationOutcome.enrichExisting,
      selectedTransactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(fixture.metadata.links, hasLength(1));
    expect(fixture.metadata.links.single.transactionId, transaction.id);
    expect(fixture.transactions.records[transaction.id]?.note, 'user note');
    expect(fixture.transactions.records[transaction.id]?.category, '餐飲');
    expect(fixture.transactions.replaceCount, 0);
  });

  test('stale existing transaction is rejected before enrichment', () async {
    final fixture = _Fixture();
    final reviewed = _transaction();
    fixture.transactions.records[reviewed.id] = reviewed.copyWith(note: 'changed');
    final request = _request(
      facts: _facts(amount: reviewed.amount),
      action: CloudInvoiceReconciliationOutcome.enrichExisting,
      selectedTransactionId: reviewed.id,
      expectedTransactionFingerprint: transactionFingerprint(reviewed),
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.conflict);
    expect(result.message, 'TRANSACTION_CHANGED_AFTER_REVIEW');
    expect(fixture.metadata.links, isEmpty);
  });

  test('replacement requires second confirmation before any mutation', () async {
    final fixture = _Fixture();
    final transaction = _transaction();
    fixture.transactions.records[transaction.id] = transaction;
    final request = _request(
      facts: _facts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      selectedTransactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
      replacementConfirmed: false,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.preflightRejected);
    expect(result.message, 'REPLACEMENT_SECOND_CONFIRMATION_REQUIRED');
    expect(fixture.transactions.replaceCount, 0);
    expect(fixture.operations.beforeImages, isEmpty);
  });

  test('replacement stores before-image and preserves protected user fields', () async {
    final fixture = _Fixture();
    final transaction = _transaction(
      amount: 300,
      category: '原分類',
      note: '原備註',
      tagName: '原標籤',
      accountName: '信用卡',
      merchantName: '原商家',
    );
    fixture.transactions.records[transaction.id] = transaction;
    final request = _request(
      facts: _facts(amount: 328, sellerName: '雲端商家'),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      selectedTransactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
      replacementConfirmed: true,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.committed);
    expect(result.rollbackToken, isNotNull);
    expect(fixture.operations.beforeImages, hasLength(1));
    final replaced = fixture.transactions.records[transaction.id]!;
    expect(replaced.amount, 328);
    expect(replaced.category, '原分類');
    expect(replaced.note, '原備註');
    expect(replaced.tagName, '原標籤');
    expect(replaced.accountName, '信用卡');
    expect(replaced.merchantName, '原商家');
    expect(replaced.occurredAt, transaction.occurredAt);
  });

  test('rollback restores exact replacement before-image', () async {
    final fixture = _Fixture();
    final transaction = _transaction(amount: 300, note: 'before');
    fixture.transactions.records[transaction.id] = transaction;
    final request = _request(
      facts: _facts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      selectedTransactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
      replacementConfirmed: true,
    );
    final committed = await fixture.executor.execute(request);

    final rolledBack = await fixture.executor.rollback(committed.operationKey);

    expect(rolledBack.status, CloudInvoicePersistenceStatus.rolledBack);
    expect(
      transactionFingerprint(fixture.transactions.records[transaction.id]!),
      transactionFingerprint(transaction),
    );
    expect(fixture.transactions.restoreCount, 1);
  });

  test('replacement metadata failure immediately restores transaction', () async {
    final fixture = _Fixture();
    final transaction = _transaction(amount: 300);
    fixture.transactions.records[transaction.id] = transaction;
    fixture.metadata.failUpsert = true;
    final request = _request(
      facts: _facts(amount: 328),
      action: CloudInvoiceReconciliationOutcome.replaceExisting,
      selectedTransactionId: transaction.id,
      expectedTransactionFingerprint: transactionFingerprint(transaction),
      replacementConfirmed: true,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.failed);
    expect(
      transactionFingerprint(fixture.transactions.records[transaction.id]!),
      transactionFingerprint(transaction),
    );
    expect(fixture.transactions.restoreCount, 1);
  });

  test('merchant is compensated when draft fails and has no references', () async {
    final fixture = _Fixture();
    final account = _account();
    fixture.accounts.records[account.id] = account;
    fixture.transactions.failCreateDraft = true;
    final request = _request(
      facts: _facts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      selectedAccountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
      merchantConfirmed: true,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.failed);
    expect(fixture.merchants.createCount, 1);
    expect(fixture.merchants.compensateCount, 1);
    expect(fixture.merchants.records, isEmpty);
  });

  test('merchant is retained for review when external references exist', () async {
    final fixture = _Fixture();
    final account = _account();
    fixture.accounts.records[account.id] = account;
    fixture.transactions.failCreateDraft = true;
    fixture.merchants.externalReferences = true;
    final request = _request(
      facts: _facts(),
      action: CloudInvoiceReconciliationOutcome.createNewDraft,
      selectedAccountId: account.id,
      expectedAccountFingerprint: accountFingerprint(account),
      merchantConfirmed: true,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.failed);
    expect(fixture.merchants.compensateCount, 0);
    expect(fixture.merchants.records, hasLength(1));
    expect(result.message, contains('merchant retained for review'));
  });

  test('candidate reference mismatch is rejected without operation record', () async {
    final fixture = _Fixture();
    final facts = _facts();
    final request = CloudInvoicePersistenceRequest(
      facts: facts,
      decision: _decision(
        action: CloudInvoiceReconciliationOutcome.keepSeparate,
        candidateReference: 'different-reference',
      ),
      requestedAt: fixture.clock.now(),
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.preflightRejected);
    expect(result.message, 'CANDIDATE_REFERENCE_MISMATCH');
    expect(fixture.operations.records, isEmpty);
  });

  test('unsupported known currency is rejected rather than defaulted', () async {
    final fixture = _Fixture();
    final request = _request(
      facts: _facts(currencyCode: 'XYZ'),
      action: CloudInvoiceReconciliationOutcome.keepSeparate,
    );

    final result = await fixture.executor.execute(request);

    expect(result.status, CloudInvoicePersistenceStatus.preflightRejected);
    expect(result.message, 'UNSUPPORTED_CURRENCY_CODE');
  });
}

class _Fixture {
  _Fixture() {
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

  final _FakeTransactionPort transactions = _FakeTransactionPort();
  final _FakeAccountPort accounts = _FakeAccountPort();
  final _FakeMerchantPort merchants = _FakeMerchantPort();
  final _FakeMetadataPort metadata = _FakeMetadataPort();
  final _FakeOperationPort operations = _FakeOperationPort();
  final _FakeClock clock = _FakeClock();
  final _FakeIds ids = _FakeIds();

  late final CloudInvoicePersistenceExecutor executor;
}

CloudInvoiceCandidateFacts _facts({
  double amount = 100,
  String sellerName = '測試商家',
  String? currencyCode,
}) {
  return CloudInvoiceCandidateFacts(
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 18),
      sellerIdentifier: '12345678',
      sellerName: sellerName,
      totalAmount: amount,
      taxAmount: 5,
      carrierType: '手機條碼',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 18),
      lineItems: const <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '測試品項', amount: 100),
      ],
    ),
    currencyCode: currencyCode,
    currencySource: currencyCode == null
        ? CloudInvoiceCurrencySource.unknown
        : CloudInvoiceCurrencySource.officialDetail,
  );
}

CloudInvoicePersistenceRequest _request({
  required CloudInvoiceCandidateFacts facts,
  required CloudInvoiceReconciliationOutcome action,
  String? selectedTransactionId,
  String? selectedAccountId,
  String? expectedTransactionFingerprint,
  String? expectedAccountFingerprint,
  bool merchantConfirmed = false,
  bool replacementConfirmed = false,
}) {
  return CloudInvoicePersistenceRequest(
    facts: facts,
    decision: _decision(
      action: action,
      candidateReference: facts.candidate.duplicateKey,
      selectedTransactionId: selectedTransactionId,
      selectedAccountId: selectedAccountId,
      merchantConfirmed: merchantConfirmed,
      replacementConfirmed: replacementConfirmed,
    ),
    expectedTransactionFingerprint: expectedTransactionFingerprint,
    expectedAccountFingerprint: expectedAccountFingerprint,
    requestedAt: DateTime.utc(2026, 6, 18, 12),
  );
}

CloudInvoiceReconciliationReviewDecision _decision({
  required CloudInvoiceReconciliationOutcome action,
  required String candidateReference,
  String? selectedTransactionId,
  String? selectedAccountId,
  bool merchantConfirmed = false,
  bool replacementConfirmed = false,
}) {
  return CloudInvoiceReconciliationReviewDecision(
    action: action,
    selectedTransactionId: selectedTransactionId,
    selectedAccountId: selectedAccountId,
    merchantProposalReviewed: true,
    merchantProposalConfirmed: merchantConfirmed,
    replacementSecondConfirmationCompleted: replacementConfirmed,
    candidateReference: candidateReference,
    decidedAt: DateTime.utc(2026, 6, 18, 11),
  );
}

TransactionRecord _transaction({
  String id = 'transaction-1',
  double amount = 100,
  String category = '其他',
  String accountName = '現金',
  String merchantName = '原商家',
  String tagName = '',
  String note = '',
}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    category: category,
    occurredAt: DateTime(2026, 6, 18, 9, 30),
    accountName: accountName,
    memberName: '',
    merchantName: merchantName,
    tagName: tagName,
    note: note,
    currency: CurrencyCode.twd,
  );
}

AccountRecord _account({
  String id = 'account-1',
  bool archived = false,
}) {
  return AccountRecord(
    id: id,
    name: '現金',
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 0,
    currency: CurrencyCode.twd,
    isArchived: archived,
  );
}

class _FakeTransactionPort implements CloudInvoiceTransactionPersistencePort {
  final Map<String, TransactionRecord> records = <String, TransactionRecord>{};
  final List<CloudInvoiceDraftRecord> drafts = <CloudInvoiceDraftRecord>[];
  int replaceCount = 0;
  int restoreCount = 0;
  bool failCreateDraft = false;
  bool failReplace = false;
  bool failRestore = false;

  @override
  Future<TransactionRecord?> loadTransaction(String transactionId) async =>
      records[transactionId];

  @override
  Future<void> createDraft(CloudInvoiceDraftRecord draft) async {
    if (failCreateDraft) throw StateError('draft failure');
    drafts.add(draft);
  }

  @override
  Future<void> removeDraft({
    required String draftId,
    required String operationKey,
  }) async {
    drafts.removeWhere(
      (draft) => draft.id == draftId && draft.operationKey == operationKey,
    );
  }

  @override
  Future<void> replaceTransaction(TransactionRecord transaction) async {
    if (failReplace) throw StateError('replace failure');
    replaceCount += 1;
    records[transaction.id] = transaction;
  }

  @override
  Future<void> restoreTransaction(TransactionRecord beforeImage) async {
    if (failRestore) throw StateError('restore failure');
    restoreCount += 1;
    records[beforeImage.id] = beforeImage;
  }
}

class _FakeAccountPort implements CloudInvoiceAccountPersistencePort {
  final Map<String, AccountRecord> records = <String, AccountRecord>{};

  @override
  Future<AccountRecord?> loadAccount(String accountId) async =>
      records[accountId];
}

class _FakeMerchantPort implements CloudInvoiceMerchantPersistencePort {
  final Map<String, MerchantRecord> records = <String, MerchantRecord>{};
  int createCount = 0;
  int compensateCount = 0;
  bool externalReferences = false;

  @override
  Future<MerchantRecord?> findByNormalizedName(String normalizedName) async =>
      records[normalizedName];

  @override
  Future<CloudInvoiceMerchantCreationResult> createMerchant({
    required MerchantRecord merchant,
    required String operationKey,
  }) async {
    createCount += 1;
    records[normalizeMerchantName(merchant.name)] = merchant;
    return CloudInvoiceMerchantCreationResult(
      merchant: merchant,
      createdForOperation: true,
    );
  }

  @override
  Future<bool> hasExternalReferences(String merchantId) async =>
      externalReferences;

  @override
  Future<void> compensateCreatedMerchant({
    required String merchantId,
    required String operationKey,
  }) async {
    compensateCount += 1;
    records.removeWhere((key, merchant) => merchant.id == merchantId);
  }
}

class _FakeMetadataPort implements CloudInvoiceMetadataPersistencePort {
  final List<CloudInvoiceMetadataLinkRecord> links =
      <CloudInvoiceMetadataLinkRecord>[];
  bool failUpsert = false;

  @override
  Future<void> upsertLink(CloudInvoiceMetadataLinkRecord link) async {
    if (failUpsert) throw StateError('metadata failure');
    links.removeWhere((item) => item.operationKey == link.operationKey);
    links.add(link);
  }

  @override
  Future<void> removeLinksForOperation(String operationKey) async {
    links.removeWhere((item) => item.operationKey == operationKey);
  }
}

class _FakeOperationPort implements CloudInvoiceOperationPersistencePort {
  final Map<String, CloudInvoiceOperationRecord> records =
      <String, CloudInvoiceOperationRecord>{};
  final Map<String, CloudInvoiceBeforeImageRecord> beforeImages =
      <String, CloudInvoiceBeforeImageRecord>{};
  final List<CloudInvoiceAuditRecord> audits = <CloudInvoiceAuditRecord>[];

  @override
  Future<CloudInvoiceOperationRecord?> loadOperation(String operationKey) async =>
      records[operationKey];

  @override
  Future<void> saveOperation(CloudInvoiceOperationRecord operation) async {
    records[operation.operationKey] = operation;
  }

  @override
  Future<void> saveBeforeImage(
    CloudInvoiceBeforeImageRecord beforeImage,
  ) async {
    beforeImages[beforeImage.rollbackToken] = beforeImage;
  }

  @override
  Future<CloudInvoiceBeforeImageRecord?> loadBeforeImage(
    String rollbackToken,
  ) async =>
      beforeImages[rollbackToken];

  @override
  Future<void> appendAudit(CloudInvoiceAuditRecord audit) async {
    audits.add(audit);
  }
}

class _FakeClock implements CloudInvoicePersistenceClock {
  @override
  DateTime now() => DateTime.utc(2026, 6, 18, 12);
}

class _FakeIds implements CloudInvoicePersistenceIdGenerator {
  final Map<String, int> _counts = <String, int>{};

  @override
  String nextId(String namespace) {
    final next = (_counts[namespace] ?? 0) + 1;
    _counts[namespace] = next;
    return '$namespace-$next';
  }
}
