import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/transaction/grouped_account_choice_sheet.dart';

void main() {
  testWidgets('groups same-name accounts by type and preserves exact identity',
      (tester) async {
    const accounts = <AccountRecord>[
      AccountRecord(
        id: 'bank-line',
        name: 'LineBank',
        suffix: '7597',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 10,
        currency: CurrencyCode.twd,
      ),
      AccountRecord(
        id: 'debit-line',
        name: 'LineBank',
        suffix: '9936',
        type: AccountType.debitCard,
        initialBalance: 0,
        sortOrder: 20,
        currency: CurrencyCode.twd,
      ),
      AccountRecord(
        id: 'wallet-pass',
        name: '一卡通 Money',
        type: AccountType.eWallet,
        initialBalance: 0,
        sortOrder: 30,
        currency: CurrencyCode.twd,
      ),
    ];
    AccountRecord? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showGroupedAccountChoiceSheet(
                    context,
                    title: '選擇帳戶',
                    accounts: accounts,
                    selectedDisplayName: 'LineBank・7597',
                    selectedAccountId: 'bank-line',
                  );
                },
                child: const Text('開啟'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('transaction-account-group-bank')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('transaction-account-group-debitCard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('transaction-account-group-eWallet')),
      findsOneWidget,
    );
    expect(find.text('LineBank・7597'), findsOneWidget);
    expect(find.text('LineBank・9936'), findsOneWidget);
    expect(find.text('銀行・TWD 新台幣'), findsOneWidget);
    expect(find.text('簽帳金融卡・TWD 新台幣'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const Key('transaction-account-option-bank-line'),
        ),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const Key('transaction-account-option-debit-line'),
        ),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('transaction-account-option-debit-line')),
    );
    await tester.pumpAndSettle();

    expect(selected?.id, 'debit-line');
    expect(selected?.displayName, 'LineBank・9936');
  });

  testWidgets('uses account id when duplicate display names are identical',
      (tester) async {
    const accounts = <AccountRecord>[
      AccountRecord(
        id: 'duplicate-a',
        name: '共同帳戶',
        suffix: '0000',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 10,
      ),
      AccountRecord(
        id: 'duplicate-b',
        name: '共同帳戶',
        suffix: '0000',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 20,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showGroupedAccountChoiceSheet(
                context,
                title: '選擇帳戶',
                accounts: accounts,
                selectedDisplayName: '共同帳戶・0000',
                selectedAccountId: 'duplicate-b',
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(
          const Key('transaction-account-option-duplicate-a'),
        ),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const Key('transaction-account-option-duplicate-b'),
        ),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not infer a selected id from an ambiguous display name',
      (tester) async {
    const accounts = <AccountRecord>[
      AccountRecord(
        id: 'duplicate-a',
        name: '共同帳戶',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 10,
      ),
      AccountRecord(
        id: 'duplicate-b',
        name: '共同帳戶',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 20,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showGroupedAccountChoiceSheet(
                context,
                title: '選擇帳戶',
                accounts: accounts,
                selectedDisplayName: '共同帳戶',
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('does not render archived accounts', (tester) async {
    const accounts = <AccountRecord>[
      AccountRecord(
        id: 'active-bank',
        name: '主要銀行',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 10,
      ),
      AccountRecord(
        id: 'archived-bank',
        name: '舊銀行',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 20,
        isArchived: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showGroupedAccountChoiceSheet(
                context,
                title: '選擇帳戶',
                accounts: accounts,
                selectedDisplayName: '',
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    expect(find.text('主要銀行'), findsOneWidget);
    expect(find.text('舊銀行'), findsNothing);
  });
}
