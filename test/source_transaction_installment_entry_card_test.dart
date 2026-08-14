import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_source_transaction_flow.dart';
import 'package:my_finance_app/features/plan/source_transaction_installment_entry_card.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  testWidgets('creates installment plan from eligible credit card expense transaction', (tester) async {
    final repository = InMemoryCreditCardInstallmentRepository();
    InstallmentPlanRecord? created;
    await tester.pumpWidget(_testApp(
      repository: repository,
      child: SourceTransactionInstallmentEntryCard(
        transaction: _expenseTransaction(),
        card: _creditCard(),
        onPlanCreated: (plan) => created = plan,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('轉為信用卡分期'), findsOneWidget);
    expect(find.text('建立分期計畫'), findsOneWidget);

    await tester.tap(find.text('建立分期計畫'));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.sourceTransactionId, 'tx-1');
    expect(created!.principal, 12000);
    expect(find.textContaining('已建立分期計畫'), findsOneWidget);
    expect(find.text('此交易已有分期計畫'), findsOneWidget);
    expect(find.text('分期期別'), findsOneWidget);
    expect(find.textContaining('第 1 期'), findsOneWidget);
    expect(find.textContaining('本金 2000 TWD'), findsWidgets);
    expect(find.textContaining('應付 2000 TWD'), findsWidgets);
    expect(find.text('建立分期計畫'), findsNothing);
    final items = await repository.loadScheduleItems(created!.id);
    expect(items, hasLength(6));
    expect(items.every((item) => item.generatedTransactionId == null), isTrue);
  });

  testWidgets('shows existing active source transaction plan and schedule instead of create form', (tester) async {
    final repository = InMemoryCreditCardInstallmentRepository();
    final existingPlan = await createInstallmentPlanFromSourceTransaction(
      id: 'existing-plan',
      repository: repository,
      transaction: _expenseTransaction(),
      card: _creditCard(),
      termCount: 6,
      firstStatementDate: DateTime(2026, 8, 5),
    );

    await tester.pumpWidget(_testApp(
      repository: repository,
      child: SourceTransactionInstallmentEntryCard(transaction: _expenseTransaction(), card: _creditCard()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('此交易已有分期計畫'), findsOneWidget);
    expect(find.text('計畫：${existingPlan.id}'), findsOneWidget);
    expect(find.text('期數：6'), findsOneWidget);
    expect(find.text('分期期別'), findsOneWidget);
    expect(find.textContaining('第 1 期・2026/08/05'), findsOneWidget);
    expect(find.textContaining('第 6 期'), findsOneWidget);
    expect(find.textContaining('本金 2000 TWD'), findsWidgets);
    expect(find.text('建立分期計畫'), findsNothing);
  });

  testWidgets('debug payment simulation shows preview dialog without mutating schedule items', (tester) async {
    final repository = InMemoryCreditCardInstallmentRepository();
    final existingPlan = await createInstallmentPlanFromSourceTransaction(
      id: 'existing-plan',
      repository: repository,
      transaction: _expenseTransaction(),
      card: _creditCard(),
      termCount: 6,
      firstStatementDate: DateTime(2026, 8, 5),
    );
    final beforeItems = await repository.loadScheduleItems(existingPlan.id);

    await tester.pumpWidget(_testApp(
      repository: repository,
      child: SourceTransactionInstallmentEntryCard(transaction: _expenseTransaction(), card: _creditCard()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Debug 模擬付款'), findsNWidgets(6));
    await tester.tap(find.text('Debug 模擬付款').first);
    await tester.pumpAndSettle();

    expect(find.text('Debug 付款模擬'), findsOneWidget);
    expect(find.textContaining('此為 preview，不會寫入交易、帳單或帳戶餘額。'), findsOneWidget);
    expect(find.textContaining('交易草案：installment-payment-preview-existing-plan-1'), findsOneWidget);
    expect(find.textContaining('付款帳戶：Debug 付款帳戶'), findsOneWidget);
    expect(find.textContaining('金額：2000 TWD'), findsOneWidget);
    expect(find.textContaining('期別狀態：pending → billed'), findsOneWidget);

    final afterItems = await repository.loadScheduleItems(existingPlan.id);
    expect(afterItems.map((item) => item.generatedTransactionId), beforeItems.map((item) => item.generatedTransactionId));
    expect(afterItems.map((item) => item.status), beforeItems.map((item) => item.status));
  });

  testWidgets('shows existing state after duplicate creation attempt without creating another plan', (tester) async {
    final repository = InMemoryCreditCardInstallmentRepository();
    await tester.pumpWidget(_testApp(
      repository: repository,
      child: SourceTransactionInstallmentEntryCard(transaction: _expenseTransaction(), card: _creditCard()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('建立分期計畫'));
    await tester.pumpAndSettle();

    expect(find.text('此交易已有分期計畫'), findsOneWidget);
    expect(find.text('分期期別'), findsOneWidget);
    expect(find.text('建立分期計畫'), findsNothing);
    final plans = await repository.loadPlansByCardId('card-1', status: InstallmentPlanStatus.active);
    expect(plans, hasLength(1));
  });

  testWidgets('blocks non-credit-card account', (tester) async {
    await tester.pumpWidget(_testApp(
      repository: InMemoryCreditCardInstallmentRepository(),
      child: SourceTransactionInstallmentEntryCard(transaction: _expenseTransaction(), card: _cashAccount()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('信用卡帳戶'), findsOneWidget);
    expect(find.text('建立分期計畫'), findsNothing);
  });
}

Widget _testApp({required CreditCardInstallmentRepository repository, required Widget child}) {
  return ProviderScope(
    overrides: [creditCardInstallmentRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

AccountRecord _creditCard() {
  return const AccountRecord(
    id: 'card-1',
    name: 'Test Credit Card',
    type: AccountType.creditCard,
    initialBalance: 0,
    sortOrder: 10,
  );
}

AccountRecord _cashAccount() {
  return const AccountRecord(
    id: 'cash-1',
    name: 'Cash',
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 1,
  );
}

TransactionRecord _expenseTransaction() {
  return TransactionRecord(
    id: 'tx-1',
    type: TransactionType.expense,
    amount: 12000,
    category: '電子數碼',
    occurredAt: DateTime(2026, 7, 20, 10, 30),
    accountName: 'Test Credit Card',
    memberName: '自己',
    merchantName: 'Store',
    tagName: '日常',
    note: '',
    currency: CurrencyCode.twd,
  );
}
