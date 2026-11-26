import 'account_record.dart';

/// Presentation-only meaning of a sum of existing account balances.
///
/// Never reinterpret a liability sign or convert an estimated group sum into
/// net assets, available credit, loan principal, or an investment market value.
class AccountGroupBalanceSemantics {
  const AccountGroupBalanceSemantics._();

  static String amountHeading({required bool hasForeignCurrency}) =>
      hasForeignCurrency ? 'TWD 參考合計' : 'TWD 帳面餘額合計';

  static String overviewNote({required bool hasForeignCurrency}) {
    const note = '含信用卡及借貸帳面餘額，非淨資產';
    return hasForeignCurrency
        ? '$note；外幣採內建參考匯率（非即時）'
        : note;
  }

  static String groupNote(
    AccountType type, {
    required bool hasForeignCurrency,
  }) {
    final meaning = switch (type) {
      AccountType.creditCard => '信用卡帳面餘額，非待繳款或可用額度',
      AccountType.loan => '借貸帳面餘額，非未償本金',
      AccountType.investment => '投資帳面餘額，非即時市值或投資報酬',
      AccountType.cash ||
      AccountType.bank ||
      AccountType.debitCard ||
      AccountType.storedValue ||
      AccountType.eWallet ||
      AccountType.other => '帳面餘額合計，非淨資產',
    };
    return hasForeignCurrency
        ? '$meaning；外幣採內建參考匯率（非即時）'
        : meaning;
  }
}
