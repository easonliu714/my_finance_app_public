import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_bank_rule_profile.dart';
import 'package:my_finance_app/features/plan/credit_card_bank_rule_resolver.dart';
import 'package:my_finance_app/features/plan/credit_card_revolving_interest_service.dart';

void main() {
  const card = AccountRecord(
    id: 'card-1',
    name: '測試信用卡',
    type: AccountType.creditCard,
    initialBalance: 0,
    sortOrder: 1,
    currency: CurrencyCode.twd,
  );

  test('falls back to system default when no profile is assigned', () {
    final resolved = resolveCreditCardBankRule(
      card: card,
      assignedProfileId: null,
      profiles: const [],
    );

    expect(resolved.source, CreditCardBankRuleSource.systemDefault);
    expect(resolved.sourceLabel, '系統預設估算');
    expect(resolved.profile.id, 'default-estimate-twd');
  });

  test('uses custom profile when assigned profile exists', () {
    const custom = CreditCardBankRuleProfile(
      id: 'custom-rule',
      name: '自訂銀行規則',
      currency: CurrencyCode.twd,
      minimumPaymentRate: 0.08,
      revolvingBalanceRate: 0.1,
      minimumPaymentFloor: 1200,
      cashAdvanceMinimum: 0,
      feeMinimum: 0,
      includeEstimatedFees: true,
      annualInterestRate: 0.16,
      daysInYear: 365,
      estimatedCycleDays: 31,
      lateFeeTiers: [CreditCardLateFeeTier(missedMinimumPaymentCount: 1, amount: 300)],
      lateFeeWaiveThreshold: 0,
      note: '測試規則',
      isVerifiedAgainstStatement: true,
    );

    final resolved = resolveCreditCardBankRule(
      card: card,
      assignedProfileId: 'custom-rule',
      profiles: const [custom],
    );

    expect(resolved.source, CreditCardBankRuleSource.custom);
    expect(resolved.sourceLabel, '自訂銀行規則');
    expect(resolved.profile.id, custom.id);
    expect(resolved.profile.minimumPaymentRate, 0.08);
    expect(resolved.profile.annualInterestRate, 0.16);
  });

  test('falls back to system default when assigned profile is missing', () {
    final resolved = resolveCreditCardBankRule(
      card: card,
      assignedProfileId: 'deleted-rule',
      profiles: const [],
    );

    expect(resolved.source, CreditCardBankRuleSource.systemDefault);
    expect(resolved.profile.name, '預設估算規則');
  });
}
