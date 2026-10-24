import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_group_balance_semantics.dart';
import 'package:my_finance_app/features/account/account_record.dart';

void main() {
  test('asset-like groups distinguish bookkeeping sum from net worth', () {
    for (final type in <AccountType>[
      AccountType.cash,
      AccountType.bank,
      AccountType.debitCard,
      AccountType.storedValue,
      AccountType.eWallet,
      AccountType.other,
    ]) {
      expect(
        AccountGroupBalanceSemantics.groupNote(
          type,
          hasForeignCurrency: false,
        ),
        contains('非淨資產'),
      );
    }
  });

  test('credit, loan and investment meanings never promise real balance', () {
    expect(
      AccountGroupBalanceSemantics.groupNote(
        AccountType.creditCard,
        hasForeignCurrency: false,
      ),
      allOf(contains('非待繳款'), contains('可用額度')),
    );
    expect(
      AccountGroupBalanceSemantics.groupNote(
        AccountType.loan,
        hasForeignCurrency: false,
      ),
      contains('非未償本金'),
    );
    expect(
      AccountGroupBalanceSemantics.groupNote(
        AccountType.investment,
        hasForeignCurrency: false,
      ),
      contains('非即時市值'),
    );
  });

  test('foreign-currency reference never claims a live exchange rate', () {
    expect(
      AccountGroupBalanceSemantics.amountHeading(hasForeignCurrency: true),
      'TWD 參考合計',
    );
    expect(
      AccountGroupBalanceSemantics.amountHeading(hasForeignCurrency: false),
      'TWD 帳面餘額合計',
    );
    expect(
      AccountGroupBalanceSemantics.groupNote(
        AccountType.bank,
        hasForeignCurrency: true,
      ),
      allOf(contains('內建參考匯率'), contains('非即時')),
    );
    expect(
      AccountGroupBalanceSemantics.overviewNote(hasForeignCurrency: true),
      allOf(contains('非淨資產'), contains('非即時')),
    );
  });
}
