import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation.dart';

void main() {
  const service = WalletTopUpRecommendationService();
  const target = AccountRecord(
    id: 'stored-value-1',
    name: '交通儲值卡',
    type: AccountType.storedValue,
    initialBalance: 0,
    sortOrder: 10,
  );
  const funding = AccountRecord(
    id: 'bank-1',
    name: '連結銀行帳戶',
    type: AccountType.bank,
    initialBalance: 2000,
    sortOrder: 20,
  );
  const profile = WalletTopUpProfile(
    targetAccountId: 'stored-value-1',
    fundingAccountId: 'bank-1',
    currency: CurrencyCode.twd,
    threshold: 100,
    amountMode: WalletTopUpAmountMode.fixedAmount,
    fixedAmount: 500,
  );
  final evaluatedAt = DateTime.utc(2026, 7, 4, 12);

  test('balance below 100 triggers fixed 500 from linked funding account', () {
    final result = service.evaluate(
      WalletTopUpEvaluationInput(
        profile: profile,
        targetAccount: target,
        fundingAccount: funding,
        currentAvailableBalance: 99,
        fundingAvailableBalance: 2000,
        evaluatedAt: evaluatedAt,
      ),
    );

    expect(result, isA<WalletTopUpSuggestion>());
    final suggestion = result as WalletTopUpSuggestion;
    expect(suggestion.targetAccountId, target.id);
    expect(suggestion.fundingAccountId, funding.id);
    expect(suggestion.threshold, 100);
    expect(suggestion.suggestedAmount, 500);
    expect(suggestion.fundingSufficient, isTrue);
  });

  test('balance equal to 100 does not trigger', () {
    final result = service.evaluate(
      WalletTopUpEvaluationInput(
        profile: profile,
        targetAccount: target,
        fundingAccount: funding,
        currentAvailableBalance: 100,
        fundingAvailableBalance: 2000,
        evaluatedAt: evaluatedAt,
      ),
    );

    expect(result, isA<WalletTopUpNoSuggestion>());
    final noSuggestion = result as WalletTopUpNoSuggestion;
    expect(
      noSuggestion.reason,
      WalletTopUpNoSuggestionReason.balanceAtOrAboveThreshold,
    );
  });

  test('insufficient linked funding balance remains explicit and fail-closed', () {
    final result = service.evaluate(
      WalletTopUpEvaluationInput(
        profile: profile,
        targetAccount: target,
        fundingAccount: funding,
        currentAvailableBalance: 99,
        fundingAvailableBalance: 300,
        evaluatedAt: evaluatedAt,
      ),
    );

    expect(result, isA<WalletTopUpSuggestion>());
    final suggestion = result as WalletTopUpSuggestion;
    expect(suggestion.suggestedAmount, 500);
    expect(suggestion.fundingSufficient, isFalse);
    expect(suggestion.fundingShortfall, 200);
  });
}
