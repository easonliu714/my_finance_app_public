import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/app.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/dashboard/dashboard_page.dart';
import 'package:my_finance_app/features/dashboard/ledger_detail_page.dart';
import 'package:my_finance_app/features/plan/credit_card_bank_rule_profile.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_event.dart';
import 'package:my_finance_app/features/transaction/transaction_entry_page.dart';
import 'package:my_finance_app/features/transaction/transaction_providers.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_store.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  testWidgets('dashboard shell renders initial accounting summary', (tester) async {
    await tester.pumpWidget(_testApp(const MyFinanceApp()));
    await tester.pumpAndSettle();

    expect(find.text('日常帳本'), findsWidgets);
    expect(find.text('本月支出'), findsOneWidget);
    expect(find.text('速記'), findsOneWidget);
    expect(find.text('發票'), findsOneWidget);
    expect(find.text('首頁'), findsOneWidget);
    expect(find.text('報表'), findsOneWidget);
  });

  testWidgets('reports back home button returns to dashboard without blank screen', (tester) async {
    final router = GoRouter(
      initialLocation: LedgerDetailPage.routePath,
      routes: [
        GoRoute(
          path: '/',
          name: DashboardPage.routeName,
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: LedgerDetailPage.routePath,
          name: LedgerDetailPage.routeName,
          builder: (context, state) => const LedgerDetailPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.byType(LedgerDetailPage), findsOneWidget);
    expect(find.byKey(LedgerDetailPage.backHomeButtonKey), findsOneWidget);

    await tester.tap(find.byKey(LedgerDetailPage.backHomeButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerDetailPage), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('tap add button opens transaction entry shell', (tester) async {
    await tester.pumpWidget(_testApp(const MyFinanceApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增記帳'));
    await tester.pumpAndSettle();

    expect(find.text('新增記帳'), findsOneWidget);
    expect(find.text('收入'), findsWidgets);
    expect(find.text('支出'), findsWidgets);
    expect(find.text('轉帳'), findsWidgets);
    expect(find.text('借貸'), findsWidgets);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('transaction entry saves a record through provider store', (tester) async {
    final store = FakeTransactionStore();
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(const MaterialApp(home: TransactionEntryPage()), transactionStore: store));
    await tester.pumpAndSettle();

    final lunchTile = find.ancestor(of: find.text('午餐'), matching: find.byType(InkWell)).first;
    await tester.ensureVisible(lunchTile);
    await tester.tap(lunchTile);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '1'));
    await tester.tap(find.widgetWithText(TextButton, '+'));
    await tester.tap(find.widgetWithText(TextButton, '2'));
    await tester.tap(find.widgetWithText(FilledButton, '='));
    await tester.pumpAndSettle();

    await tester.tap(find.text('現金'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('信用卡').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('備註 / 發票明細'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '公司午餐');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.records, hasLength(1));
    expect(store.records.single.category, '午餐');
    expect(store.records.single.amount, 3);
    expect(store.records.single.accountName, '信用卡');
    expect(store.records.single.note, '公司午餐');
  });

  testWidgets('transaction entry account selector reads account store', (tester) async {
    final transactionStore = FakeTransactionStore();
    final accountStore = FakeAccountStore([
      const AccountRecord(id: 'cash', name: '現金', type: AccountType.cash, initialBalance: 0, sortOrder: 10),
      const AccountRecord(id: 'line-pay', name: 'LINE Pay', type: AccountType.eWallet, initialBalance: 0, sortOrder: 20),
    ]);
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(const MaterialApp(home: TransactionEntryPage()), transactionStore: transactionStore, accountStore: accountStore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('現金'));
    await tester.pumpAndSettle();

    expect(find.text('選擇帳戶'), findsOneWidget);
    expect(find.text('LINE Pay'), findsOneWidget);

    await tester.tap(find.text('LINE Pay'));
    await tester.pumpAndSettle();
    expect(find.text('LINE Pay'), findsOneWidget);
  });

  testWidgets('transaction entry edits an existing record through provider store', (tester) async {
    final store = FakeTransactionStore();
    final record = TransactionRecord(
      id: 'record-1',
      type: TransactionType.expense,
      amount: 120,
      category: '早餐',
      occurredAt: DateTime(2026, 5, 21, 8, 10),
      accountName: '現金',
      memberName: '自己',
      merchantName: '不使用商家',
      tagName: '日常',
      note: '原始備註',
    );
    store.records.add(record);
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(MaterialApp(home: TransactionEntryPage(initialRecord: record)), transactionStore: store));
    await tester.pumpAndSettle();

    expect(find.text('編輯記帳'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('原始備註'), findsOneWidget);

    await tester.tap(find.text('原始備註'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '更新備註');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();

    expect(store.records, hasLength(1));
    expect(store.records.single.id, 'record-1');
    expect(store.records.single.amount, 120);
    expect(store.records.single.note, '更新備註');
  });

  testWidgets('transaction edit can open source transaction installment sheet and create plan', (tester) async {
    final store = FakeTransactionStore();
    final installmentRepository = InMemoryCreditCardInstallmentRepository();
    final record = TransactionRecord(
      id: 'credit-expense-1',
      type: TransactionType.expense,
      amount: 12000,
      category: '電子數碼',
      occurredAt: DateTime(2026, 7, 20, 10, 30),
      accountName: '信用卡',
      memberName: '自己',
      merchantName: 'Store',
      tagName: '日常',
      note: '手機',
      currency: CurrencyCode.twd,
    );
    store.records.add(record);
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(
      MaterialApp(home: TransactionEntryPage(initialRecord: record)),
      transactionStore: store,
      installmentRepository: installmentRepository,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('轉為信用卡分期'));
    await tester.pumpAndSettle();

    expect(find.text('轉為信用卡分期'), findsOneWidget);
    expect(find.text('建立分期計畫'), findsOneWidget);

    await tester.tap(find.text('建立分期計畫'));
    await tester.pumpAndSettle();

    final plans = await installmentRepository.loadPlansByCardId('credit-card', status: InstallmentPlanStatus.active);
    expect(plans, hasLength(1));
    expect(plans.single.sourceTransactionId, 'credit-expense-1');
    expect(store.records, hasLength(1));
    expect(store.records.single.id, 'credit-expense-1');
  });

  testWidgets('transaction entry opens integrated date time picker', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(const MaterialApp(home: TransactionEntryPage())));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip).first);
    await tester.pumpAndSettle();

    expect(find.text('調整日期時間'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('日'), findsWidgets);
    expect(find.text('星期'), findsOneWidget);
    expect(find.text('時'), findsOneWidget);
    expect(find.text('分'), findsOneWidget);
    expect(find.text('月曆'), findsOneWidget);
    expect(find.text('時鐘'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNWidgets(5));
  });
}

Widget _testApp(Widget child, {FakeTransactionStore? transactionStore, FakeAccountStore? accountStore, CreditCardInstallmentRepository? installmentRepository}) {
  return ProviderScope(
    overrides: [
      transactionStoreProvider.overrideWithValue(transactionStore ?? FakeTransactionStore()),
      accountStoreProvider.overrideWithValue(accountStore ?? FakeAccountStore.defaultAccounts()),
      if (installmentRepository != null) creditCardInstallmentRepositoryProvider.overrideWithValue(installmentRepository),
    ],
    child: child,
  );
}

class FakeTransactionStore implements TransactionStore {
  final List<TransactionRecord> records = [];

  @override
  Future<void> insert(TransactionRecord record) async {
    records.add(record);
  }

  @override
  Future<void> update(TransactionRecord record) async {
    final index = records.indexWhere((item) => item.id == record.id);
    if (index >= 0) records[index] = record;
  }

  @override
  Future<void> deleteById(String id) async {
    records.removeWhere((record) => record.id == id);
  }

  @override
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId) async {
    records.removeWhere((record) => record.repaymentGroupId == repaymentGroupId);
  }

  @override
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record) async {
    final groupId = record.repaymentGroupId?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      records.removeWhere((item) => item.repaymentGroupId == groupId);
      return;
    }
    final period = RegExp(r'第\s*(\d+)\s*期').firstMatch(record.note)?.group(1);
    if (period == null) {
      records.removeWhere((item) => item.id == record.id);
      return;
    }
    records.removeWhere((item) => item.tagName == '還款' && item.note.contains('第 $period 期') && ((item.type == TransactionType.loan && item.category == '還本') || (item.type == TransactionType.expense && item.category == '利息支出')));
  }

  @override
  Future<List<TransactionRecord>> listRecent({int limit = 50}) async => records.take(limit).toList();

  @override
  Future<double> monthlyIncome(DateTime month) async => records.where((record) => record.type.name == 'income').fold<double>(0, (sum, record) => sum + record.amount);

  @override
  Future<double> monthlyExpense(DateTime month) async => records.where((record) => record.type.name == 'expense').fold<double>(0, (sum, record) => sum + record.amount);
}

class FakeAccountStore implements AccountStore {
  FakeAccountStore(this.accounts);

  factory FakeAccountStore.defaultAccounts() {
    return FakeAccountStore(const [
      AccountRecord(id: 'cash', name: '現金', type: AccountType.cash, initialBalance: 0, sortOrder: 10),
      AccountRecord(id: 'bank', name: '銀行帳戶', type: AccountType.bank, initialBalance: 0, sortOrder: 20),
      AccountRecord(id: 'credit-card', name: '信用卡', type: AccountType.creditCard, initialBalance: 0, sortOrder: 30),
      AccountRecord(id: 'ipass-money', name: '一卡通 Money', type: AccountType.eWallet, initialBalance: 0, sortOrder: 40),
      AccountRecord(id: 'easycard', name: '悠遊卡', type: AccountType.storedValue, initialBalance: 0, sortOrder: 50),
    ]);
  }

  final List<AccountRecord> accounts;
  final List<AccountEventRecord> events = [];
  final List<TransactionRecord> transactions = [];
  final List<CreditCardStatementEvent> statementEvents = [];
  final List<CreditCardBankRuleProfile> bankRuleProfiles = [];
  final Map<String, String?> bankRuleAssignments = {};

  @override
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false}) async => accounts.where((account) => includeArchived || !account.isArchived).toList();

  @override
  Future<void> upsertAccount(AccountRecord account) async {
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index >= 0) {
      accounts[index] = account;
    } else {
      accounts.add(account);
    }
  }

  @override
  Future<void> archiveAccount(String id) async {
    final index = accounts.indexWhere((item) => item.id == id);
    if (index >= 0) accounts[index] = accounts[index].copyWith(isArchived: true);
  }

  @override
  Future<List<AccountEventRecord>> listAccountEvents(String accountName) async => events.where((event) => event.accountName == accountName).toList();

  @override
  Future<List<TransactionRecord>> listAccountTransactions(String accountName) async => transactions.where((record) => record.accountName == accountName || record.fromAccountName == accountName || record.toAccountName == accountName).toList();

  @override
  Future<void> upsertAccountEvent(AccountEventRecord event) async {
    events.removeWhere((item) => item.id == event.id);
    events.add(event);
  }

  @override
  Future<void> deleteAccountEvent(String id) async {
    events.removeWhere((event) => event.id == id);
  }

  @override
  Future<List<CreditCardStatementEvent>> listCreditCardStatementEvents(String cardId) async => statementEvents.where((event) => event.cardId == cardId).toList();

  @override
  Future<void> upsertCreditCardStatementEvent(CreditCardStatementEvent event) async {
    statementEvents.removeWhere((item) => item.id == event.id);
    statementEvents.add(event);
  }

  @override
  Future<void> deleteCreditCardStatementEvent(String id) async {
    statementEvents.removeWhere((event) => event.id == id);
  }

  @override
  Future<List<CreditCardBankRuleProfile>> listCreditCardBankRuleProfiles() async => List.unmodifiable(bankRuleProfiles);

  @override
  Future<void> upsertCreditCardBankRuleProfile(CreditCardBankRuleProfile profile) async {
    bankRuleProfiles.removeWhere((item) => item.id == profile.id);
    bankRuleProfiles.add(profile);
  }

  @override
  Future<void> deleteCreditCardBankRuleProfile(String id) async {
    bankRuleProfiles.removeWhere((item) => item.id == id);
    bankRuleAssignments.updateAll((key, value) => value == id ? null : value);
  }

  @override
  Future<String?> getCreditCardBankRuleProfileId(String cardId) async => bankRuleAssignments[cardId];

  @override
  Future<void> setCreditCardBankRuleProfileId(String cardId, String? profileId) async {
    bankRuleAssignments[cardId] = profileId;
  }
}
