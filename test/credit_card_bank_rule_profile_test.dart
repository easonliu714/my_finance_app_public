import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/plan/credit_card_bank_rule_profile.dart';
import 'package:my_finance_app/features/plan/credit_card_minimum_payment_service.dart';
import 'package:my_finance_app/features/plan/credit_card_revolving_interest_service.dart';
import 'package:my_finance_app/features/plan/credit_card_statement_service.dart';

void main() {
  test('default bank rule profile matches existing estimate rules', () {
    final profile = CreditCardBankRuleProfile.defaultEstimate(CurrencyCode.twd);
    final minimumRule = CreditCardMinimumPaymentRule.defaultEstimate(CurrencyCode.twd);
    final revolvingRule = CreditCardRevolvingInterestRule.defaultEstimate(CurrencyCode.twd);

    expect(profile.minimumPaymentRate, minimumRule.currentPurchaseRate);
    expect(profile.revolvingBalanceRate, minimumRule.revolvingBalanceRate);
    expect(profile.minimumPaymentFloor, minimumRule.minimumFloor);
    expect(profile.annualInterestRate, revolvingRule.annualInterestRate);
    expect(profile.estimatedCycleDays, revolvingRule.estimatedCycleDays);
    expect(profile.lateFeeTiers.map((tier) => tier.amount), revolvingRule.lateFeeTiers.map((tier) => tier.amount));
    expect(profile.isVerifiedAgainstStatement, isFalse);
  });

  test('profile rules keep minimum payment and revolving estimates stable', () {
    const card = AccountRecord(
      id: 'card-1',
      name: '測試信用卡',
      type: AccountType.creditCard,
      initialBalance: 0,
      sortOrder: 1,
      currency: CurrencyCode.twd,
    );
    final statement = CreditCardStatementEstimate(
      card: card,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      dueDate: DateTime(2026, 6, 15),
      purchaseTotal: 20000,
      paymentTotal: 0,
      estimatedDue: 20000,
      outstandingTotal: 20000,
      totalPurchaseCount: 1,
      totalPaymentCount: 0,
      isPaid: false,
      purchaseCount: 1,
      paymentCount: 0,
    );
    final profile = CreditCardBankRuleProfile.defaultEstimate(CurrencyCode.twd);

    final defaultMinimum = buildCreditCardMinimumPaymentEstimate(statement);
    final profileMinimum = buildCreditCardMinimumPaymentEstimate(statement, rule: profile.toMinimumPaymentRule());
    final defaultRevolving = buildCreditCardRevolvingInterestEstimate(defaultMinimum);
    final profileRevolving = buildCreditCardRevolvingInterestEstimate(profileMinimum, rule: profile.toRevolvingInterestRule());

    expect(profileMinimum.estimatedMinimumDue, defaultMinimum.estimatedMinimumDue);
    expect(profileMinimum.componentSubtotal, defaultMinimum.componentSubtotal);
    expect(profileRevolving.revolvingPrincipal, defaultRevolving.revolvingPrincipal);
    expect(profileRevolving.estimatedCycleInterest, defaultRevolving.estimatedCycleInterest);
    expect(profileRevolving.estimatedLateFee, defaultRevolving.estimatedLateFee);
  });

  test('profile map roundtrip preserves late fee tiers and flags', () {
    const profile = CreditCardBankRuleProfile(
      id: 'custom-twd',
      name: '自訂估算規則',
      currency: CurrencyCode.twd,
      minimumPaymentRate: 0.08,
      revolvingBalanceRate: 0.12,
      minimumPaymentFloor: 1200,
      cashAdvanceMinimum: 100,
      feeMinimum: 50,
      includeEstimatedFees: true,
      annualInterestRate: 0.145,
      daysInYear: 365,
      estimatedCycleDays: 31,
      lateFeeTiers: [
        CreditCardLateFeeTier(missedMinimumPaymentCount: 1, amount: 300),
        CreditCardLateFeeTier(missedMinimumPaymentCount: 2, amount: 500),
      ],
      lateFeeWaiveThreshold: 10,
      note: '估算規則備註',
      isVerifiedAgainstStatement: true,
    );

    final restored = CreditCardBankRuleProfile.fromMap(profile.toMap());

    expect(restored.id, profile.id);
    expect(restored.name, profile.name);
    expect(restored.minimumPaymentRate, 0.08);
    expect(restored.revolvingBalanceRate, 0.12);
    expect(restored.minimumPaymentFloor, 1200);
    expect(restored.includeEstimatedFees, isTrue);
    expect(restored.annualInterestRate, 0.145);
    expect(restored.estimatedCycleDays, 31);
    expect(restored.lateFeeTiers, hasLength(2));
    expect(restored.lateFeeTiers.last.amount, 500);
    expect(restored.isVerifiedAgainstStatement, isTrue);
  });
}
