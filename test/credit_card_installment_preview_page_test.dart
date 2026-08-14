import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/plan/credit_card_bank_rule_profile.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_preview_page.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_providers.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository_factory.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_event.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';

void main() {
  testWidgets('credit card installment preview can create and cancel fake active plan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStoreProvider.overrideWithValue(_FakeAccountStore.defaultAccounts()),
          creditCardInstallmentDebugRepositoryModeProvider.overrideWith((ref) => CreditCardInstallmentRepositoryMode.previewSafeInMemory),
        ],
        child: const MaterialApp(home: CreditCardInstallmentPreviewPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('信用卡分期'), findsOneWidget);
    expect(find.text('Debug-only SQLite 測試入口'), findsOneWidget);
    expect(find.text('全部 Fake Active Plans'), findsOneWidget);
    expect(find.text('尚無 Fake Active Plan。'), findsOneWidget);
    expect(find.text('Debug SQLite 資料檢查'), findsNothing);

    final previewButton = find.widgetWithText(FilledButton, '更新試算預覽');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.text('試算結果'), findsOneWidget);
    expect(find.text('建立 Fake Active Plan'), findsOneWidget);

    final createButton = find.widgetWithText(OutlinedButton, '建立 Fake Active Plan');
    await tester.scrollUntilVisible(createButton, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('尚無 Fake Active Plan。'), findsNothing);
    expect(find.text('取消 Fake Plan'), findsOneWidget);
    expect(find.textContaining('Test Credit Card'), findsWidgets);

    final cancelButton = find.widgetWithText(TextButton, '取消 Fake Plan');
    await tester.scrollUntilVisible(cancelButton, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(find.text('尚無 Fake Active Plan。'), findsOneWidget);
  });

  test('sqlite installment preview source uses release labels for active plans', () {
    final source = File('lib/features/plan/credit_card_installment_preview_page.dart').readAsStringSync();

    expect(source, contains("'分期計畫'"));
    expect(source, contains("'尚無 active 分期計畫。'"));
    expect(source, contains("'建立分期計畫'"));
    expect(source, contains("'取消分期計畫'"));
    expect(source, isNot(contains('Debug SQLite Active Plans')));
    expect(source, isNot(contains('尚無 Debug SQLite Plan。')));
    expect(source, isNot(contains('建立 Debug SQLite Plan')));
    expect(source, isNot(contains('取消 Debug SQLite Plan')));
  });
}

class _FakeAccountStore implements AccountStore {
  _FakeAccountStore(this.accounts);

  factory _FakeAccountStore.defaultAccounts() {
    return _FakeAccountStore(const [
      AccountRecord(
        id: 'credit-card-1',
        name: 'Test Credit Card',
        type: AccountType.creditCard,
        initialBalance: 0,
        sortOrder: 10,
      ),
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
  }

  @override
  Future<String?> getCreditCardBankRuleProfileId(String cardId) async => bankRuleAssignments[cardId];

  @override
  Future<void> setCreditCardBankRuleProfileId(String cardId, String? profileId) async {
    bankRuleAssignments[cardId] = profileId;
  }
}
