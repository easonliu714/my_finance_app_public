import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
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
  testWidgets('new credit card expense shows textual installment entry and saves before opening sheet', (tester) async {
    final transactionStore = _FakeTransactionStore();
    final installmentRepository = InMemoryCreditCardInstallmentRepository();
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(
      const MaterialApp(home: TransactionEntryPage()),
      transactionStore: transactionStore,
      installmentRepository: installmentRepository,
    ));
    await tester.pumpAndSettle();

    expect(find.text('分期'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('現金'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('信用卡').last);
    await tester.pumpAndSettle();

    expect(find.text('分期'), findsOneWidget);

    await tester.tap(find.text('分期'));
    await tester.pumpAndSettle();

    expect(transactionStore.records, hasLength(1));
    expect(transactionStore.records.single.accountName, '信用卡');
    expect(transactionStore.records.single.type, TransactionType.expense);
    expect(find.text('轉為信用卡分期'), findsOneWidget);
    expect(find.text('建立分期計畫'), findsOneWidget);
  });
}

Widget _testApp(Widget child, {required _FakeTransactionStore transactionStore, required CreditCardInstallmentRepository installmentRepository}) {
  return ProviderScope(
    overrides: [
      transactionStoreProvider.overrideWithValue(transactionStore),
      accountStoreProvider.overrideWithValue(_FakeAccountStore.defaultAccounts()),
      creditCardInstallmentRepositoryProvider.overrideWithValue(installmentRepository),
    ],
    child: child,
  );
}

class _FakeTransactionStore implements TransactionStore {
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
    records.removeWhere((item) => item.id == record.id);
  }

  @override
  Future<List<TransactionRecord>> listRecent({int limit = 50}) async => records.take(limit).toList();

  @override
  Future<double> monthlyIncome(DateTime month) async => records.where((record) => record.type == TransactionType.income).fold<double>(0, (sum, record) => sum + record.amount);

  @override
  Future<double> monthlyExpense(DateTime month) async => records.where((record) => record.type == TransactionType.expense).fold<double>(0, (sum, record) => sum + record.amount);
}

class _FakeAccountStore implements AccountStore {
  _FakeAccountStore(this.accounts);

  factory _FakeAccountStore.defaultAccounts() {
    return _FakeAccountStore(const [
      AccountRecord(id: 'cash', name: '現金', type: AccountType.cash, initialBalance: 0, sortOrder: 10),
      AccountRecord(id: 'credit-card', name: '信用卡', type: AccountType.creditCard, initialBalance: 0, sortOrder: 20),
      AccountRecord(id: 'bank', name: '銀行帳戶', type: AccountType.bank, initialBalance: 0, sortOrder: 30),
      AccountRecord(id: 'ipass-money', name: '一卡通 Money', type: AccountType.eWallet, initialBalance: 0, sortOrder: 40),
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
