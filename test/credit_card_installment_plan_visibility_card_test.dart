import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/plan/credit_card_bank_rule_profile.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_plan_visibility_card.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_event.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';

void main() {
  testWidgets('installment visibility card lists active plans from repository', (tester) async {
    final repository = InMemoryCreditCardInstallmentRepository();
    final input = CreditCardInstallmentPlanInput(
      id: 'plan-visible-1',
      scenario: CreditCardInstallmentScenario.purchaseTime,
      cardId: 'credit-card-1',
      cardName: 'Line Card',
      currency: CurrencyCode.twd,
      principal: 5000,
      termCount: 6,
      firstStatementDate: DateTime(2026, 5, 28),
      sourceTransactionId: 'tx-visible-1',
    );
    await repository.createPlan(input: input, schedule: buildCreditCardInstallmentSchedule(input));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(_FakeAccountStore.defaultAccounts()),
          creditCardInstallmentRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: CreditCardInstallmentPlanVisibilityCard())),
      ),
    );
    await _pumpUntilFound(tester, find.text('信用卡分期'));

    expect(find.text('信用卡分期'), findsOneWidget);
    expect(find.text('1 筆 active'), findsOneWidget);
    expect(find.textContaining('Line Card'), findsOneWidget);
    expect(find.textContaining('5,000 TWD'), findsWidgets);
    expect(find.text('尚無 active 分期計畫。'), findsNothing);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder, {int maxPumps = 40}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

class _FakeAccountStore implements AccountStore {
  _FakeAccountStore(this.accounts);

  factory _FakeAccountStore.defaultAccounts() {
    return _FakeAccountStore(const [
      AccountRecord(id: 'credit-card-1', name: 'Line Card', type: AccountType.creditCard, initialBalance: 0, sortOrder: 10),
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
