import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_providers.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/account_store.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/account/debit_card_account_store.dart';
import 'package:my_finance_app/features/account/debit_card_account_sheet.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';

void main() {
  testWidgets('shows an actionable empty state when no bank account exists',
      (tester) async {
    final store = _FakeDebitCardAccountStore(const <AccountRecord>[]);
    await _pumpHarness(tester, store: store);

    await tester.tap(find.text('開啟簽帳金融卡表單'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('debit-card-empty-bank-state')), findsOneWidget);
    expect(find.text('目前沒有可綁定的銀行帳戶。'), findsOneWidget);
    expect(find.byKey(const Key('debit-card-create-bank')), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('debit-card-save')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('creates a zero-balance debit card linked to selected bank',
      (tester) async {
    const bank = AccountRecord(
      id: 'bank-usd',
      name: '美元銀行',
      type: AccountType.bank,
      initialBalance: 500,
      sortOrder: 10,
      suffix: '8899',
      currency: CurrencyCode.usd,
    );
    final store = _FakeDebitCardAccountStore(<AccountRecord>[bank]);
    await _pumpHarness(tester, store: store);

    await tester.tap(find.text('開啟簽帳金融卡表單'));
    await tester.pumpAndSettle();

    expect(find.text('美元銀行・8899・USD'), findsOneWidget);
    expect(find.text('USD 美元'), findsOneWidget);
    expect(find.text('0（清算帳戶固定值）'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('debit-card-name')),
      '旅遊簽帳卡',
    );
    await tester.enterText(
      find.byKey(const Key('debit-card-suffix')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const Key('debit-card-settlement-days')),
      '3',
    );
    await tester.tap(find.byKey(const Key('debit-card-save')));
    await tester.pumpAndSettle();

    expect(store.savedAccount, isNotNull);
    expect(store.savedAccount!.name, '旅遊簽帳卡');
    expect(store.savedAccount!.suffix, '1234');
    expect(store.savedAccount!.type, AccountType.debitCard);
    expect(store.savedAccount!.currency, CurrencyCode.usd);
    expect(store.savedAccount!.initialBalance, 0);
    expect(store.savedProfile, isNotNull);
    expect(store.savedProfile!.linkedBankAccountId, bank.id);
    expect(store.savedProfile!.settlementBusinessDays, 3);
    expect(store.savedProfile!.isEnabled, isTrue);
  });

  testWidgets('editing preloads the existing bank link and profile settings',
      (tester) async {
    const bank = AccountRecord(
      id: 'bank-twd',
      name: '主要銀行',
      type: AccountType.bank,
      initialBalance: 10000,
      sortOrder: 10,
      currency: CurrencyCode.twd,
    );
    const debit = AccountRecord(
      id: 'debit-1',
      name: '日常簽帳卡',
      type: AccountType.debitCard,
      initialBalance: 0,
      sortOrder: 20,
      suffix: '5678',
      currency: CurrencyCode.twd,
    );
    final profile = DebitCardAccountProfile.link(
      debitCardAccountId: debit.id,
      linkedBankAccount: bank,
      debitCardCurrency: debit.currency,
      settlementBusinessDays: 5,
      isEnabled: false,
    );
    final store = _FakeDebitCardAccountStore(
      <AccountRecord>[bank, debit],
      profiles: <String, DebitCardAccountProfile>{debit.id: profile},
    );
    await _pumpHarness(tester, store: store, account: debit);

    await tester.tap(find.text('開啟簽帳金融卡表單'));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(
      find.byKey(const Key('debit-card-name')),
    );
    final suffixField = tester.widget<TextField>(
      find.byKey(const Key('debit-card-suffix')),
    );
    final daysField = tester.widget<TextField>(
      find.byKey(const Key('debit-card-settlement-days')),
    );
    final enabledSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('debit-card-enabled')),
    );

    expect(nameField.controller!.text, '日常簽帳卡');
    expect(suffixField.controller!.text, '5678');
    expect(daysField.controller!.text, '5');
    expect(enabledSwitch.value, isFalse);
    expect(find.text('主要銀行・TWD'), findsOneWidget);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required _FakeDebitCardAccountStore store,
  AccountRecord? account,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountStoreProvider.overrideWithValue(store),
        debitCardAccountStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, child) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDebitCardAccountSheet(
                  context,
                  ref,
                  account: account,
                ),
                child: const Text('開啟簽帳金融卡表單'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeDebitCardAccountStore extends AccountStore implements DebitCardAccountStore {
  _FakeDebitCardAccountStore(
    List<AccountRecord> accounts, {
    Map<String, DebitCardAccountProfile>? profiles,
  })  : accounts = List<AccountRecord>.from(accounts),
        profiles = <String, DebitCardAccountProfile>{...?profiles};

  final List<AccountRecord> accounts;
  final Map<String, DebitCardAccountProfile> profiles;
  AccountRecord? savedAccount;
  DebitCardAccountProfile? savedProfile;

  @override
  Future<List<AccountRecord>> listAccounts({bool includeArchived = false}) async {
    return accounts
        .where((account) => includeArchived || !account.isArchived)
        .toList(growable: false);
  }

  @override
  Future<void> upsertAccount(AccountRecord account) async {
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index < 0) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }
  }

  @override
  Future<void> upsertDebitCardAccount(
    AccountRecord account,
    DebitCardAccountProfile profile,
  ) async {
    savedAccount = account;
    savedProfile = profile;
    await upsertAccount(account);
    profiles[account.id] = profile;
  }

  @override
  Future<DebitCardAccountProfile?> getDebitCardProfile(String accountId) async {
    return profiles[accountId];
  }

  @override
  Future<void> archiveAccount(String id) async {
    final index = accounts.indexWhere((item) => item.id == id);
    if (index >= 0) {
      accounts[index] = accounts[index].copyWith(isArchived: true);
    }
  }

  @override
  Future<List<AccountEventRecord>> listAccountEvents(
    String accountName,
  ) async =>
      const <AccountEventRecord>[];

  @override
  Future<List<TransactionRecord>> listAccountTransactions(
    String accountName,
  ) async =>
      const <TransactionRecord>[];

  @override
  Future<void> upsertAccountEvent(AccountEventRecord event) async {}

  @override
  Future<void> deleteAccountEvent(String id) async {}
}
