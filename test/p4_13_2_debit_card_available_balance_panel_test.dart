import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_available_balance_panel.dart';
import 'package:my_finance_app/features/account/debit_card_available_balance_presentation.dart';
import 'package:my_finance_app/features/transaction/debit_card_available_balance.dart';

void main() {
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 1000,
    sortOrder: 10,
  );
  const debitA = AccountRecord(
    id: 'debit-a',
    name: 'A 簽帳卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 20,
  );
  const debitB = AccountRecord(
    id: 'debit-b',
    name: 'B 簽帳卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 30,
  );

  Widget host(AsyncValue<AccountAvailableBalancePresentation?> value) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DebitCardAvailableBalancePanel(value: value),
          ),
        ),
      ),
    );
  }

  testWidgets('debit-card panel shows ledger reserved and available values', (
    tester,
  ) async {
    const presentation = AccountAvailableBalancePresentation(
      viewedAccount: debitA,
      linkedBankAccount: bank,
      linkedDebitCardAccounts: [debitA],
      snapshot: DebitCardAvailableBalanceSnapshot(
        debitCardAccountId: 'debit-a',
        linkedBankAccountId: 'bank-1',
        currency: CurrencyCode.twd,
        ledgerBalance: 1000,
        reservedPendingAmount: 300,
        availableBalance: 700,
        activeReservationCount: 1,
      ),
    );

    await tester.pumpWidget(host(const AsyncValue.data(presentation)));
    await tester.pumpAndSettle();

    expect(find.text('簽帳金融卡可用餘額'), findsOneWidget);
    expect(find.textContaining('薪轉銀行'), findsOneWidget);
    expect(find.text('1,000 TWD'), findsOneWidget);
    expect(find.text('300 TWD'), findsOneWidget);
    expect(find.text('700 TWD'), findsOneWidget);
    expect(find.text('待扣款 1 筆'), findsOneWidget);
    expect(find.textContaining('本機帳務估算'), findsOneWidget);
  });

  testWidgets('linked-bank panel shows shared cards and over-reserved warning', (
    tester,
  ) async {
    const presentation = AccountAvailableBalancePresentation(
      viewedAccount: bank,
      linkedBankAccount: bank,
      linkedDebitCardAccounts: [debitA, debitB],
      snapshot: DebitCardAvailableBalanceSnapshot(
        debitCardAccountId: 'debit-a',
        linkedBankAccountId: 'bank-1',
        currency: CurrencyCode.twd,
        ledgerBalance: 1000,
        reservedPendingAmount: 1200,
        availableBalance: -200,
        activeReservationCount: 2,
      ),
    );

    await tester.pumpWidget(host(const AsyncValue.data(presentation)));
    await tester.pumpAndSettle();

    expect(find.text('簽帳金融卡共用資金池'), findsOneWidget);
    expect(find.textContaining('A 簽帳卡'), findsOneWidget);
    expect(find.textContaining('B 簽帳卡'), findsOneWidget);
    expect(find.text('-200 TWD'), findsOneWidget);
    expect(find.text('連結 2 張卡'), findsOneWidget);
    expect(find.textContaining('預計扣款已超過帳面餘額'), findsOneWidget);
    expect(
      find.textContaining('預計扣款已超過帳面餘額 200 TWD'),
      findsOneWidget,
    );
  });

  testWidgets('null presentation renders no section', (tester) async {
    await tester.pumpWidget(
      host(const AsyncValue<AccountAvailableBalancePresentation?>.data(null)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsNothing);
    expect(find.textContaining('簽帳金融卡'), findsNothing);
  });

  testWidgets('read failure is non-blocking and user-readable', (tester) async {
    await tester.pumpWidget(
      host(
        AsyncValue<AccountAvailableBalancePresentation?>.error(
          StateError('read failed'),
          StackTrace.empty,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('可用餘額暫時無法讀取'), findsOneWidget);
    expect(find.textContaining('帳戶明細仍可正常使用'), findsOneWidget);
    expect(find.textContaining('read failed'), findsNothing);
  });
}
