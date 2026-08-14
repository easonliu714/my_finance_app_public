import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_review_decision.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_review_page.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  testWidgets('date-only and unknown currency remain visibly unknown', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
      ),
    );

    await _pump(tester, controller: controller);

    expect(find.text('開立時間未提供'), findsOneWidget);
    expect(find.text('幣別未提供'), findsOneWidget);
    expect(find.text('00:00:00'), findsNothing);
    expect(
      find.byKey(CloudInvoiceReconciliationReviewPage.safetyKey),
      findsOneWidget,
    );
  });

  testWidgets('exact time and known currency are displayed from real facts', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(
        invoiceDate: DateTime(2026, 5, 4, 11, 45, 50),
        timePrecision: CloudInvoiceTimePrecision.exactDateTime,
        currencyCode: 'TWD',
      ),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.keepSeparate,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.keepSeparate,
        },
      ),
    );

    await _pump(tester, controller: controller);

    expect(find.text('11:45:50'), findsOneWidget);
    expect(find.text('TWD'), findsOneWidget);
    expect(find.text('開立時間未提供'), findsNothing);
  });

  testWidgets('ambiguous match can be selected before enrichment', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.ambiguous,
        matches: <CloudInvoiceTransactionMatch>[
          _match(id: 'one', merchant: '第一商家'),
          _match(id: 'two', merchant: '第二商家'),
        ],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.ambiguous,
          CloudInvoiceReconciliationOutcome.keepSeparate,
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
      ),
    );
    CloudInvoiceReconciliationReviewDecision? emitted;

    await _pump(
      tester,
      controller: controller,
      onDecision: (decision) => emitted = decision,
    );

    expect(find.text('補充既有帳目'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey<String>('match_two')));
    await tester.tap(find.byKey(const ValueKey<String>('match_two')));
    await tester.pumpAndSettle();

    expect(find.text('補充既有帳目'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('action_enrichExisting')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('action_enrichExisting')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(CloudInvoiceReconciliationReviewPage.submitKey),
    );
    await tester.tap(
      find.byKey(CloudInvoiceReconciliationReviewPage.submitKey),
    );
    await tester.pumpAndSettle();

    expect(emitted?.action, CloudInvoiceReconciliationOutcome.enrichExisting);
    expect(emitted?.selectedTransactionId, 'two');
  });

  testWidgets('new draft requires merchant choice and account dropdown', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
        merchantPlan: const CloudInvoiceMerchantResolutionPlan(
          status: CloudInvoiceMerchantResolutionStatus.createDraftProposed,
          creationProposal: CloudInvoiceMerchantCreationProposal(
            name: '測試商家',
            sellerIdentifier: '12345678',
            sourceInvoiceNumber: 'AB12345678',
          ),
        ),
        accountPlan: _accountPlan(),
      ),
    );
    CloudInvoiceReconciliationReviewDecision? emitted;
    var addAccountCount = 0;

    await _pump(
      tester,
      controller: controller,
      onDecision: (decision) => emitted = decision,
      onAddAccount: () => addAccountCount += 1,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('action_createNewDraft')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('action_createNewDraft')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('merchant_create_choice')));
    await tester.tap(find.byKey(const Key('merchant_create_choice')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(CloudInvoiceReconciliationReviewPage.accountDropdownKey),
    );
    await tester.tap(
      find.byKey(CloudInvoiceReconciliationReviewPage.accountDropdownKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('信用卡｜建議').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(CloudInvoiceReconciliationReviewPage.addAccountKey),
    );
    await tester.pumpAndSettle();
    expect(addAccountCount, 1);

    await tester.ensureVisible(
      find.byKey(CloudInvoiceReconciliationReviewPage.submitKey),
    );
    final submit = tester.widget<FilledButton>(
      find.byKey(CloudInvoiceReconciliationReviewPage.submitKey),
    );
    expect(submit.onPressed, isNotNull);
    await tester.tap(
      find.byKey(CloudInvoiceReconciliationReviewPage.submitKey),
    );
    await tester.pumpAndSettle();

    expect(emitted?.selectedAccountId, 'card');
    expect(emitted?.merchantProposalConfirmed, isTrue);
  });

  testWidgets('suggested account is not preselected', (tester) async {
    final controller = _controller(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.createNewDraft,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
        accountPlan: _accountPlan(),
      ),
    );

    await _pump(tester, controller: controller);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('action_createNewDraft')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('action_createNewDraft')),
    );
    await tester.pumpAndSettle();

    expect(controller.selectedAccountId, isNull);
    expect(find.text('請選擇帳戶'), findsOneWidget);
    expect(controller.canSubmit, isFalse);
  });

  testWidgets('new-account-required state exposes add account callback', (
    tester,
  ) async {
    final controller = _controller(
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
    var addAccountCount = 0;

    await _pump(
      tester,
      controller: controller,
      onAddAccount: () => addAccountCount += 1,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('action_createNewDraft')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('action_createNewDraft')),
    );
    await tester.pumpAndSettle();

    expect(find.text('必須先新增帳戶，才能建立新草稿。'), findsOneWidget);
    await tester.tap(
      find.byKey(CloudInvoiceReconciliationReviewPage.addAccountKey),
    );
    await tester.pumpAndSettle();
    expect(addAccountCount, 1);
    expect(controller.canSubmit, isFalse);
  });

  testWidgets('replacement requires visible differences and confirmation', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(amount: 328),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.keepSeparate,
        matches: <CloudInvoiceTransactionMatch>[
          _match(
            id: 'replace',
            amount: 300,
            merchant: '測試商家',
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
    CloudInvoiceReconciliationReviewDecision? emitted;

    await _pump(
      tester,
      controller: controller,
      onDecision: (decision) => emitted = decision,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('action_replaceExisting')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('action_replaceExisting')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(CloudInvoiceReconciliationReviewPage.replacementSectionKey),
      findsOneWidget,
    );
    expect(find.text('重要衝突'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(CloudInvoiceReconciliationReviewPage.replacementConfirmKey),
    );
    final confirmationTile = tester.widget<CheckboxListTile>(
      find.byKey(
        CloudInvoiceReconciliationReviewPage.replacementConfirmKey,
      ),
    );
    expect(confirmationTile.value, isFalse);
    confirmationTile.onChanged!(true);
    await tester.pumpAndSettle();

    expect(controller.replacementConfirmed, isTrue);
    expect(controller.canSubmit, isTrue);
    emitted = controller.buildDecision();

    expect(
      emitted?.action,
      CloudInvoiceReconciliationOutcome.replaceExisting,
    );
    expect(emitted?.replacementSecondConfirmationCompleted, isTrue);
  });

  testWidgets('blocked plan disables every commit-like action', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(status: CloudInvoiceCandidateStatus.blocked),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.blocked,
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.blocked,
        },
      ),
    );

    await _pump(tester, controller: controller);

    expect(controller.isBlocked, isTrue);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      find.byKey(CloudInvoiceReconciliationReviewPage.blockedKey),
      findsOneWidget,
    );
    final submit = tester.widget<FilledButton>(
      find.byKey(CloudInvoiceReconciliationReviewPage.submitKey),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('small screen remains scrollable without overflow', (
    tester,
  ) async {
    final controller = _controller(
      facts: _facts(),
      plan: _plan(
        outcome: CloudInvoiceReconciliationOutcome.ambiguous,
        matches: <CloudInvoiceTransactionMatch>[
          _match(id: 'one'),
          _match(id: 'two'),
          _match(id: 'three'),
        ],
        allowedActions: const <CloudInvoiceReconciliationOutcome>{
          CloudInvoiceReconciliationOutcome.ambiguous,
          CloudInvoiceReconciliationOutcome.keepSeparate,
          CloudInvoiceReconciliationOutcome.createNewDraft,
        },
      ),
    );

    await _pump(
      tester,
      controller: controller,
      size: const Size(360, 560),
    );

    expect(tester.takeException(), isNull);
    for (var attempt = 0; attempt < 8; attempt += 1) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(CloudInvoiceReconciliationReviewPage.safetyKey),
      findsOneWidget,
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required CloudInvoiceReconciliationReviewController controller,
  ValueChanged<CloudInvoiceReconciliationReviewDecision>? onDecision,
  VoidCallback? onAddAccount,
  Size size = const Size(430, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CloudInvoiceReconciliationReviewPage(
        controller: controller,
        onDecision: onDecision,
        onAddAccount: onAddAccount,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CloudInvoiceReconciliationReviewController _controller({
  required CloudInvoiceCandidateFacts facts,
  required CloudInvoiceReconciliationPlan plan,
}) {
  return CloudInvoiceReconciliationReviewController(
    facts: facts,
    plan: plan,
    now: () => DateTime.utc(2026, 6, 18, 12),
  );
}

CloudInvoiceCandidateFacts _facts({
  DateTime? invoiceDate,
  CloudInvoiceTimePrecision timePrecision = CloudInvoiceTimePrecision.dateOnly,
  String? currencyCode,
  double amount = 100,
  CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
}) {
  return CloudInvoiceCandidateFacts(
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: status,
      invoiceNumber: 'AB12345678',
      invoiceDate: invoiceDate ?? DateTime(2026, 6, 18),
      sellerIdentifier: '12345678',
      sellerName: '測試商家',
      totalAmount: amount,
      taxAmount: 5,
      carrierType: '手機條碼',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 18),
      lineItems: const <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '測試品項', amount: 100),
      ],
    ),
    timePrecision: timePrecision,
    currencyCode: currencyCode,
  );
}

CloudInvoiceReconciliationPlan _plan({
  required CloudInvoiceReconciliationOutcome outcome,
  List<CloudInvoiceTransactionMatch> matches =
      const <CloudInvoiceTransactionMatch>[],
  required Set<CloudInvoiceReconciliationOutcome> allowedActions,
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
          existingMerchant: MerchantRecord(id: 'merchant', name: '測試商家'),
        ),
    accountPlan: accountPlan ?? _accountPlan(),
    fieldDifferences: const <CloudInvoiceFieldDifference>[],
    reasons: const <String>['交易日期相同', '仍需人工覆核'],
  );
}

CloudInvoiceAccountResolutionPlan _accountPlan() {
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
    ],
  );
}

CloudInvoiceTransactionMatch _match({
  required String id,
  String merchant = '測試商家',
  double amount = 100,
  CloudInvoiceReconciliationOutcome recommendedOutcome =
      CloudInvoiceReconciliationOutcome.enrichExisting,
  bool canOfferReplacement = false,
}) {
  return CloudInvoiceTransactionMatch(
    snapshot: LocalTransactionReconciliationSnapshot(
      transaction: TransactionRecord(
        id: id,
        type: TransactionType.expense,
        amount: amount,
        category: '其他',
        occurredAt: DateTime(2026, 6, 18, 12),
        accountName: '信用卡',
        memberName: '',
        merchantName: merchant,
        tagName: '',
        note: '',
        currency: CurrencyCode.twd,
      ),
      invoiceNumber: 'OLD12345678',
      sellerIdentifier: '87654321',
    ),
    score: 90,
    signals: <CloudInvoiceMatchSignal>{
      CloudInvoiceMatchSignal.sameCalendarDate,
      if (amount == 100) CloudInvoiceMatchSignal.exactAmount,
      CloudInvoiceMatchSignal.merchantExact,
      if (amount != 100) CloudInvoiceMatchSignal.amountConflict,
    },
    recommendedOutcome: recommendedOutcome,
    canOfferReplacement: canOfferReplacement,
  );
}

AccountRecord _account({
  required String id,
  required String name,
  AccountType type = AccountType.cash,
}) {
  return AccountRecord(
    id: id,
    name: name,
    type: type,
    currency: CurrencyCode.twd,
    initialBalance: 0,
    sortOrder: 0,
  );
}
