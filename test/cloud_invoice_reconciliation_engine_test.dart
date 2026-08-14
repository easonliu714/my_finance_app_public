import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_engine.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const engine = CloudInvoiceReconciliationEngine();

  test('date-only candidate accepts any transaction time on the same day', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 4),
        sellerName: 'Example Asia Pacific Pte Ltd',
        amount: 660,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'late-evening',
          occurredAt: DateTime(2026, 5, 4, 23, 59, 59),
          amount: 660,
          merchantName: 'Example Asia Pacific Pte Ltd',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.enrichExisting,
    );
    expect(plan.rankedMatches.single.hasExactAmount, isTrue);
    expect(
      plan.reasons,
      contains('雲端資料只有日期；同日 00:00 至 23:59 均視為可比對範圍。'),
    );
  });

  test('exact time remains a weak fact and does not narrow same-day matching', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 4, 11, 45, 50),
        sellerName: 'Example Asia Pacific Pte Ltd',
        amount: 660,
        timePrecision: CloudInvoiceTimePrecision.exactDateTime,
        timeSource: CloudInvoiceTimeSource.officialInvoiceIssuedAt,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'morning',
          occurredAt: DateTime(2026, 5, 4, 8),
          amount: 660,
          merchantName: 'Example Asia Pacific Pte Ltd',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.enrichExisting,
    );
  });

  test('cross-date transaction is not recommended as the same event', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 4),
        sellerName: 'Google',
        amount: 660,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'next-day',
          occurredAt: DateTime(2026, 5, 5),
          amount: 660,
          merchantName: 'Google',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.createNewDraft,
    );
    expect(plan.rankedMatches, isEmpty);
  });

  test('date and amount alone remain ambiguous', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '',
        amount: 75,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'amount-only',
          occurredAt: DateTime(2026, 5, 3, 17, 25),
          amount: 75,
          merchantName: '',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.ambiguous,
    );
    expect(
      plan.rankedMatches.single.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.ambiguous,
    );
  });

  test('account hint plus date and amount can recommend enrichment', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '',
        amount: 75,
        paymentHint: const CloudInvoicePaymentHint(
          accountName: '現金錢包',
        ),
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'account-match',
          occurredAt: DateTime(2026, 5, 3, 17, 25),
          amount: 75,
          merchantName: '',
          accountName: '現金錢包',
        ),
      ],
      accounts: <AccountRecord>[_account(name: '現金錢包')],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.enrichExisting,
    );
    expect(
      plan.rankedMatches.single.signals,
      contains(CloudInvoiceMatchSignal.accountNameMatch),
    );
  });

  test('deterministic invoice identity recommends exact duplicate', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceNumber: 'AD90000004',
        invoiceDate: DateTime(2026, 5, 4),
        sellerIdentifier: '42523557',
        sellerName: 'Example Asia Pacific Pte Ltd',
        amount: 660,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'already-linked',
          occurredAt: DateTime(2026, 5, 4, 11, 45),
          amount: 660,
          merchantName: 'Example Asia Pacific Pte Ltd',
          invoiceNumber: 'AD-9000 0004',
          sellerIdentifier: '42523557',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.exactDuplicate,
    );
    expect(
      plan.rankedMatches.single.signals,
      contains(CloudInvoiceMatchSignal.invoiceIdentity),
    );
  });

  test('multiple plausible same-day matches become ambiguous', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '測試商行',
        amount: 75,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'one',
          occurredAt: DateTime(2026, 5, 3, 9),
          amount: 75,
          merchantName: '測試商行',
        ),
        _snapshot(
          id: 'two',
          occurredAt: DateTime(2026, 5, 3, 17, 25),
          amount: 75,
          merchantName: '測試商行',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.ambiguous,
    );
    expect(plan.rankedMatches, hasLength(2));
  });

  test('same merchant with different amount defaults to keep separate', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '測試文創有限公司',
        amount: 328,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'different-amount',
          occurredAt: DateTime(2026, 5, 3, 12),
          amount: 300,
          merchantName: '測試文創有限公司',
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.keepSeparate,
    );
    expect(
      plan.allowedActions,
      contains(CloudInvoiceReconciliationOutcome.replaceExisting),
    );
    expect(plan.canReplaceAutomatically, isFalse);
  });

  test('known conflicting currency keeps records separate', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 4),
        sellerName: 'Google',
        amount: 660,
        currencyCode: 'USD',
        currencySource: CloudInvoiceCurrencySource.officialDetail,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'twd-record',
          occurredAt: DateTime(2026, 5, 4),
          amount: 660,
          merchantName: 'Google',
          currency: CurrencyCode.twd,
        ),
      ],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.keepSeparate,
    );
    expect(plan.rankedMatches.single.hasCurrencyConflict, isTrue);
  });

  test('existing match preserves its assigned account', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 4),
        sellerName: 'Google',
        amount: 660,
      ),
      transactions: <LocalTransactionReconciliationSnapshot>[
        _snapshot(
          id: 'existing',
          occurredAt: DateTime(2026, 5, 4),
          amount: 660,
          merchantName: 'Google',
          accountName: '信用卡 A',
        ),
      ],
      accounts: <AccountRecord>[
        _account(
          id: 'card-a',
          name: '信用卡 A',
          type: AccountType.creditCard,
        ),
      ],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.accountPlan.status,
      CloudInvoiceAccountResolutionStatus.preservedExisting,
    );
    expect(plan.accountPlan.preservedAccountName, '信用卡 A');
  });

  test('new draft lists active accounts and still requires selection', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 6),
        sellerName: '新商家',
        amount: 120,
        paymentHint: const CloudInvoicePaymentHint(
          accountName: '信用卡 A',
        ),
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[
        _account(id: 'cash', name: '現金', sortOrder: 2),
        _account(
          id: 'card-a',
          name: '信用卡 A',
          type: AccountType.creditCard,
          sortOrder: 1,
        ),
        _account(id: 'archived', name: '舊帳戶', archived: true),
      ],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.createNewDraft,
    );
    expect(
      plan.accountPlan.status,
      CloudInvoiceAccountResolutionStatus.selectionRequired,
    );
    expect(plan.accountPlan.options, hasLength(2));
    expect(plan.accountPlan.options.first.account.id, 'card-a');
    expect(plan.accountPlan.suggestedAccountId, 'card-a');
    expect(plan.accountPlan.requiresUserSelection, isTrue);
    expect(plan.accountPlan.canCreateFormalTransaction, isFalse);
    expect(plan.accountPlan.canAddNewAccount, isTrue);
  });

  test('no active account requires new account creation', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 6),
        sellerName: '新商家',
        amount: 120,
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[
        _account(id: 'archived', name: '舊帳戶', archived: true),
      ],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.accountPlan.status,
      CloudInvoiceAccountResolutionStatus.newAccountRequired,
    );
    expect(plan.accountPlan.requiresNewAccount, isTrue);
    expect(plan.accountPlan.options, isEmpty);
  });

  test('unknown currency does not force an account currency', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 6),
        sellerName: '新商家',
        amount: 120,
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[
        _account(id: 'twd', name: 'TWD 帳戶', currency: CurrencyCode.twd),
        _account(id: 'usd', name: 'USD 帳戶', currency: CurrencyCode.usd),
      ],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.accountPlan.options.every((option) => option.currencyCompatible),
      isTrue,
    );
    expect(plan.reasons, contains('幣別未知，不自動補值或作為排除條件。'));
  });

  test('existing merchant is linked by normalized name', () {
    final merchant = MerchantRecord(id: 'merchant-1', name: '測試商行');
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '測試 商行',
        amount: 75,
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[_account()],
      merchants: <MerchantRecord>[merchant],
    );

    expect(
      plan.merchantPlan.status,
      CloudInvoiceMerchantResolutionStatus.linkedExisting,
    );
    expect(plan.merchantPlan.existingMerchant?.id, 'merchant-1');
  });

  test('new merchant is proposed from real invoice fields', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceNumber: 'BS90000015',
        invoiceDate: DateTime(2026, 5, 3),
        sellerIdentifier: '60325013',
        sellerName: '測試文創有限公司',
        amount: 328,
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.merchantPlan.status,
      CloudInvoiceMerchantResolutionStatus.createDraftProposed,
    );
    expect(plan.merchantPlan.creationProposal?.name, '測試文創有限公司');
    expect(
      plan.merchantPlan.creationProposal?.sellerIdentifier,
      '60325013',
    );
    expect(plan.merchantPlan.creationProposal?.canPersistAutomatically, isFalse);
  });

  test('missing seller stays unresolved and is not fabricated', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '',
        amount: 75,
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.merchantPlan.status,
      CloudInvoiceMerchantResolutionStatus.unresolved,
    );
    expect(plan.merchantPlan.creationProposal, isNull);
  });

  test('blocked candidate cannot create a formal transaction', () {
    final plan = engine.reconcile(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 3),
        sellerName: '測試商家',
        amount: 75,
        status: CloudInvoiceCandidateStatus.blocked,
      ),
      transactions: const <LocalTransactionReconciliationSnapshot>[],
      accounts: <AccountRecord>[_account()],
      merchants: const <MerchantRecord>[],
    );

    expect(
      plan.recommendedOutcome,
      CloudInvoiceReconciliationOutcome.blocked,
    );
    expect(plan.canWriteFormalTransactionAutomatically, isFalse);
  });
}

CloudInvoiceCandidateFacts _facts({
  String invoiceNumber = 'AB12345678',
  DateTime? invoiceDate,
  String sellerIdentifier = '12345678',
  String sellerName = '測試商家',
  double amount = 100,
  CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
  CloudInvoiceTimePrecision timePrecision = CloudInvoiceTimePrecision.dateOnly,
  CloudInvoiceTimeSource timeSource = CloudInvoiceTimeSource.unknown,
  String? currencyCode,
  CloudInvoiceCurrencySource currencySource =
      CloudInvoiceCurrencySource.unknown,
  CloudInvoicePaymentHint paymentHint = const CloudInvoicePaymentHint(),
}) {
  return CloudInvoiceCandidateFacts(
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: status,
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate ?? DateTime(2026, 5, 1),
      sellerIdentifier: sellerIdentifier,
      sellerName: sellerName,
      totalAmount: amount,
      carrierType: '手機條碼',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 18),
    ),
    timePrecision: timePrecision,
    timeSource: timeSource,
    currencyCode: currencyCode,
    currencySource: currencySource,
    paymentHint: paymentHint,
  );
}

LocalTransactionReconciliationSnapshot _snapshot({
  required String id,
  required DateTime occurredAt,
  required double amount,
  required String merchantName,
  String accountName = '現金',
  CurrencyCode currency = CurrencyCode.twd,
  String? invoiceNumber,
  String? sellerIdentifier,
}) {
  return LocalTransactionReconciliationSnapshot(
    transaction: TransactionRecord(
      id: id,
      type: TransactionType.expense,
      amount: amount,
      category: '其他',
      occurredAt: occurredAt,
      accountName: accountName,
      memberName: '',
      merchantName: merchantName,
      tagName: '',
      note: '',
      currency: currency,
    ),
    invoiceNumber: invoiceNumber,
    sellerIdentifier: sellerIdentifier,
  );
}

AccountRecord _account({
  String id = 'cash',
  String name = '現金',
  AccountType type = AccountType.cash,
  CurrencyCode currency = CurrencyCode.twd,
  int sortOrder = 0,
  bool archived = false,
}) {
  return AccountRecord(
    id: id,
    name: name,
    type: type,
    currency: currency,
    initialBalance: 0,
    sortOrder: sortOrder,
    isArchived: archived,
  );
}
