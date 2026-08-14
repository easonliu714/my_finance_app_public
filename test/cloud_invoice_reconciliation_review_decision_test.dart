import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_review_decision.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('ambiguous plan requires selecting a match before enrichment', () {
    final first = _match(id: 'one');
    final second = _match(id: 'two');
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.ambiguous,
        matches: <CloudInvoiceTransactionMatch>[first, second],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.ambiguous,
          CloudInvoiceReconciliationOutcome.keepSeparate,
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
      ),
    );

    expect(
      controller.availableActions,
      isNot(contains(CloudInvoiceReconciliationOutcome.enrichExisting)),
    );

    controller.selectTransaction('two');

    expect(
      controller.availableActions,
      contains(CloudInvoiceReconciliationOutcome.enrichExisting),
    );
    controller.selectAction(CloudInvoiceReconciliationOutcome.enrichExisting);
    expect(controller.canSubmit, isTrue);
    expect(controller.buildDecision().selectedTransactionId, 'two');
  });

  test('new draft requires explicit account and merchant decisions', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
        merchantPlan: _merchantProposal(),
        accountPlan: _accountSelectionPlan(),
      ),
      now: () => DateTime.utc(2026, 6, 18, 8, 30),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.createNewDraft);
    expect(controller.canSubmit, isFalse);

    controller.selectAccount('card');
    expect(controller.canSubmit, isFalse);

    controller.chooseMerchantProposal(
      CloudInvoiceMerchantProposalChoice.skipMerchant,
    );
    expect(controller.canSubmit, isTrue);

    final decision = controller.buildDecision();
    expect(decision.selectedAccountId, 'card');
    expect(decision.selectedTransactionId, isNull);
    expect(decision.merchantProposalReviewed, isTrue);
    expect(decision.merchantProposalConfirmed, isFalse);
    expect(decision.decidedAt, DateTime.utc(2026, 6, 18, 8, 30));
  });

  test('merchant creation choice is retained in emitted decision', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
        merchantPlan: _merchantProposal(),
        accountPlan: _accountSelectionPlan(),
      ),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.createNewDraft);
    controller.selectAccount('cash');
    controller.chooseMerchantProposal(
      CloudInvoiceMerchantProposalChoice.createMerchant,
    );

    final decision = controller.buildDecision();
    expect(decision.merchantProposalConfirmed, isTrue);
    expect(decision.canPersistMerchantAutomatically, isFalse);
  });

  test('currency-incompatible account cannot be selected', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(currencyCode: 'TWD'),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
        accountPlan: _accountSelectionPlan(usdCompatible: false),
      ),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.createNewDraft);
    expect(
      () => controller.selectAccount('usd'),
      throwsA(isA<ArgumentError>()),
    );
    expect(controller.canSubmit, isFalse);
  });

  test('new-account-required plan cannot emit a draft decision', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
        accountPlan: const CloudInvoiceAccountResolutionPlan(
          status: CloudInvoiceAccountResolutionStatus.newAccountRequired,
          options: <CloudInvoiceAccountSelectionOption>[],
        ),
      ),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.createNewDraft);
    expect(controller.requiresNewAccount, isTrue);
    expect(controller.canSubmit, isFalse);
    expect(controller.buildDecision, throwsA(isA<StateError>()));
  });

  test('replacement requires a selected match and second confirmation', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.keepSeparate,
        matches: <CloudInvoiceTransactionMatch>[
          _match(
            id: 'replace-me',
            recommendedOutcome:
                CloudInvoiceReconciliationOutcome.keepSeparate,
            canOfferReplacement: true,
          ),
        ],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.keepSeparate,
          CloudInvoiceReconciliationOutcome.replaceExisting,
        },
      ),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.replaceExisting);
    expect(controller.resolvedTransactionId, 'replace-me');
    expect(controller.canSubmit, isFalse);

    controller.setReplacementConfirmed(true);
    expect(controller.canSubmit, isTrue);
    final decision = controller.buildDecision();
    expect(decision.selectedTransactionId, 'replace-me');
    expect(decision.replacementSecondConfirmationCompleted, isTrue);
    expect(decision.canReplaceAutomatically, isFalse);
  });

  test('changing away from replacement clears second confirmation', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.keepSeparate,
        matches: <CloudInvoiceTransactionMatch>[
          _match(id: 'existing', canOfferReplacement: true),
        ],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.keepSeparate,
          CloudInvoiceReconciliationOutcome.replaceExisting,
        },
      ),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.replaceExisting);
    controller.setReplacementConfirmed(true);
    controller.selectAction(CloudInvoiceReconciliationOutcome.keepSeparate);

    expect(controller.replacementConfirmed, isFalse);
  });

  test('unique existing match is resolved without unnecessary selection', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.enrichExisting,
        matches: <CloudInvoiceTransactionMatch>[_match(id: 'unique')],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.enrichExisting,
          CloudInvoiceReconciliationOutcome.keepSeparate,
        },
        accountPlan: const CloudInvoiceAccountResolutionPlan(
          status: CloudInvoiceAccountResolutionStatus.preservedExisting,
          options: <CloudInvoiceAccountSelectionOption>[],
          preservedAccountName: '信用卡',
        ),
      ),
    );

    controller.selectAction(CloudInvoiceReconciliationOutcome.enrichExisting);
    expect(controller.canSubmit, isTrue);
    expect(controller.buildDecision().selectedTransactionId, 'unique');
  });

  test('blocked plan cannot select or emit a commit-like action', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(status: CloudInvoiceCandidateStatus.blocked),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.blocked,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.blocked,
        },
      ),
    );

    expect(controller.availableActions, isEmpty);
    expect(controller.canSubmit, isFalse);
    expect(
      () => controller.selectAction(
        CloudInvoiceReconciliationOutcome.createNewDraft,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('every decision preserves hard no-write boundaries', () {
    final controller = CloudInvoiceReconciliationReviewController(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.keepSeparate,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.keepSeparate,
        },
      ),
    );
    controller.selectAction(CloudInvoiceReconciliationOutcome.keepSeparate);

    final decision = controller.buildDecision();
    expect(decision.canWriteFormalTransactionAutomatically, isFalse);
    expect(decision.canPersistMerchantAutomatically, isFalse);
    expect(decision.canPersistAccountAutomatically, isFalse);
    expect(decision.canReplaceAutomatically, isFalse);
  });
}

CloudInvoiceCandidateFacts _facts({
  String? currencyCode,
  CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
}) {
  return CloudInvoiceCandidateFacts(
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: status,
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 18),
      sellerIdentifier: '12345678',
      sellerName: '測試商家',
      totalAmount: 100,
      carrierType: '手機條碼',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 18),
    ),
    currencyCode: currencyCode,
  );
}

CloudInvoiceReconciliationPlan _plan({
  required CloudInvoiceReconciliationOutcome outcome,
  List<CloudInvoiceTransactionMatch> matches =
      const <CloudInvoiceTransactionMatch>[],
  Set<CloudInvoiceReconciliationOutcome> allowedActions =
      const <CloudInvoiceReconciliationOutcome>{},
  CloudInvoiceMerchantResolutionPlan? merchantPlan,
  CloudInvoiceAccountResolutionPlan? accountPlan,
}) {
  return CloudInvoiceReconciliationPlan(
    recommendedOutcome: outcome,
    rankedMatches: matches,
    allowedActions: allowedActions,
    merchantPlan: merchantPlan ??
        CloudInvoiceMerchantResolutionPlan(
          status: CloudInvoiceMerchantResolutionStatus.linkedExisting,
          existingMerchant: MerchantRecord(
            id: 'merchant',
            name: '測試商家',
          ),
        ),
    accountPlan: accountPlan ??
        const CloudInvoiceAccountResolutionPlan(
          status: CloudInvoiceAccountResolutionStatus.selectionRequired,
          options: <CloudInvoiceAccountSelectionOption>[],
        ),
    fieldDifferences: const <CloudInvoiceFieldDifference>[],
    reasons: const <String>['測試理由'],
  );
}

CloudInvoiceMerchantResolutionPlan _merchantProposal() {
  return const CloudInvoiceMerchantResolutionPlan(
    status: CloudInvoiceMerchantResolutionStatus.createDraftProposed,
    creationProposal: CloudInvoiceMerchantCreationProposal(
      name: '測試商家',
      sellerIdentifier: '12345678',
      sourceInvoiceNumber: 'AB12345678',
    ),
  );
}

CloudInvoiceAccountResolutionPlan _accountSelectionPlan({
  bool usdCompatible = true,
}) {
  return CloudInvoiceAccountResolutionPlan(
    status: CloudInvoiceAccountResolutionStatus.selectionRequired,
    suggestedAccountId: 'card',
    options: <CloudInvoiceAccountSelectionOption>[
      CloudInvoiceAccountSelectionOption(
        account: _account(id: 'cash', name: '現金'),
        currencyCompatible: true,
        matchesHint: false,
      ),
      CloudInvoiceAccountSelectionOption(
        account: _account(
          id: 'card',
          name: '信用卡',
          type: AccountType.creditCard,
        ),
        currencyCompatible: true,
        matchesHint: true,
      ),
      CloudInvoiceAccountSelectionOption(
        account: _account(
          id: 'usd',
          name: '美元帳戶',
          currency: CurrencyCode.usd,
        ),
        currencyCompatible: usdCompatible,
        matchesHint: false,
      ),
    ],
  );
}

CloudInvoiceTransactionMatch _match({
  required String id,
  CloudInvoiceReconciliationOutcome recommendedOutcome =
      CloudInvoiceReconciliationOutcome.enrichExisting,
  bool canOfferReplacement = false,
}) {
  return CloudInvoiceTransactionMatch(
    snapshot: LocalTransactionReconciliationSnapshot(
      transaction: TransactionRecord(
        id: id,
        type: TransactionType.expense,
        amount: 100,
        category: '其他',
        occurredAt: DateTime(2026, 6, 18, 12),
        accountName: '信用卡',
        memberName: '',
        merchantName: '測試商家',
        tagName: '',
        note: '',
        currency: CurrencyCode.twd,
      ),
    ),
    score: 90,
    signals: const <CloudInvoiceMatchSignal>{
      CloudInvoiceMatchSignal.sameCalendarDate,
      CloudInvoiceMatchSignal.exactAmount,
      CloudInvoiceMatchSignal.merchantExact,
    },
    recommendedOutcome: recommendedOutcome,
    canOfferReplacement: canOfferReplacement,
  );
}

AccountRecord _account({
  required String id,
  required String name,
  AccountType type = AccountType.cash,
  CurrencyCode currency = CurrencyCode.twd,
}) {
  return AccountRecord(
    id: id,
    name: name,
    type: type,
    currency: currency,
    initialBalance: 0,
    sortOrder: 0,
  );
}
