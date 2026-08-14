import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation.dart';

void main() {
  const service = WalletTopUpRecommendationService();
  final evaluatedAt = DateTime.utc(2026, 7, 4, 5);

  AccountRecord targetAccount({
    String id = 'wallet-1',
    AccountType type = AccountType.eWallet,
    CurrencyCode currency = CurrencyCode.twd,
    bool archived = false,
  }) {
    return AccountRecord(
      id: id,
      name: 'Wallet',
      type: type,
      initialBalance: 0,
      sortOrder: 10,
      currency: currency,
      isArchived: archived,
    );
  }

  AccountRecord fundingAccount({
    String id = 'bank-1',
    AccountType type = AccountType.bank,
    CurrencyCode currency = CurrencyCode.twd,
    bool archived = false,
  }) {
    return AccountRecord(
      id: id,
      name: 'Funding',
      type: type,
      initialBalance: 0,
      sortOrder: 20,
      currency: currency,
      isArchived: archived,
    );
  }

  WalletTopUpProfile profile({
    String targetId = 'wallet-1',
    String fundingId = 'bank-1',
    CurrencyCode currency = CurrencyCode.twd,
    double threshold = 100,
    WalletTopUpAmountMode mode = WalletTopUpAmountMode.targetBalance,
    double targetBalance = 500,
    double fixedAmount = 0,
    bool enabled = true,
    Duration cooldown = Duration.zero,
    String? lastSuggestionId,
    DateTime? lastSuggestedAt,
  }) {
    return WalletTopUpProfile(
      targetAccountId: targetId,
      fundingAccountId: fundingId,
      currency: currency,
      threshold: threshold,
      amountMode: mode,
      targetBalance: targetBalance,
      fixedAmount: fixedAmount,
      isEnabled: enabled,
      cooldown: cooldown,
      lastSuggestionId: lastSuggestionId,
      lastSuggestedAt: lastSuggestedAt,
    );
  }

  WalletTopUpEvaluationInput input({
    WalletTopUpProfile? configuredProfile,
    AccountRecord? target,
    AccountRecord? funding,
    double currentBalance = 50,
    double fundingBalance = 1000,
    DateTime? now,
  }) {
    return WalletTopUpEvaluationInput(
      profile: configuredProfile ?? profile(),
      targetAccount: target ?? targetAccount(),
      fundingAccount: funding ?? fundingAccount(),
      currentAvailableBalance: currentBalance,
      fundingAvailableBalance: fundingBalance,
      evaluatedAt: now ?? evaluatedAt,
    );
  }

  Matcher failsWith(WalletTopUpRecommendationErrorCode code) {
    return throwsA(
      isA<WalletTopUpRecommendationException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
  }

  test('balance equal to threshold does not trigger a suggestion', () {
    final result = service.evaluate(input(currentBalance: 100));

    expect(result, isA<WalletTopUpNoSuggestion>());
    final noSuggestion = result as WalletTopUpNoSuggestion;
    expect(
      noSuggestion.reason,
      WalletTopUpNoSuggestionReason.balanceAtOrAboveThreshold,
    );
    expect(noSuggestion.currentAvailableBalance, 100);
    expect(noSuggestion.threshold, 100);
  });

  test('target-balance mode creates a deterministic reviewed suggestion', () {
    final first = service.evaluate(input(currentBalance: 75));
    final second = service.evaluate(input(currentBalance: 75));

    expect(first, isA<WalletTopUpSuggestion>());
    final suggestion = first as WalletTopUpSuggestion;
    expect(suggestion.suggestedAmount, 425);
    expect(suggestion.fundingSufficient, isTrue);
    expect(suggestion.fundingShortfall, 0);
    expect(suggestion.targetAccountId, 'wallet-1');
    expect(suggestion.fundingAccountId, 'bank-1');
    expect(suggestion.suggestionId, startsWith('wallet-top-up-'));
    expect(
      (second as WalletTopUpSuggestion).suggestionId,
      suggestion.suggestionId,
    );
  });

  test('fixed-amount mode reports funding insufficiency without blocking', () {
    final result = service.evaluate(
      input(
        configuredProfile: profile(
          mode: WalletTopUpAmountMode.fixedAmount,
          fixedAmount: 250,
        ),
        currentBalance: 20,
        fundingBalance: 100,
      ),
    );

    expect(result, isA<WalletTopUpSuggestion>());
    final suggestion = result as WalletTopUpSuggestion;
    expect(suggestion.suggestedAmount, 250);
    expect(suggestion.fundingSufficient, isFalse);
    expect(suggestion.fundingShortfall, 150);
  });

  test('zero-decimal currencies use deterministic rounding', () {
    final result = service.evaluate(
      input(
        configuredProfile: profile(
          currency: CurrencyCode.jpy,
          threshold: 100.4,
          targetBalance: 500.4,
        ),
        target: targetAccount(currency: CurrencyCode.jpy),
        funding: fundingAccount(currency: CurrencyCode.jpy),
        currentBalance: 99.4,
        fundingBalance: 1000.4,
      ),
    );

    final suggestion = result as WalletTopUpSuggestion;
    expect(suggestion.threshold, 100);
    expect(suggestion.currentAvailableBalance, 99);
    expect(suggestion.fundingAvailableBalance, 1000);
    expect(suggestion.suggestedAmount, 401);
  });

  test('stored-value accounts are eligible targets', () {
    final result = service.evaluate(
      input(target: targetAccount(type: AccountType.storedValue)),
    );

    expect(result, isA<WalletTopUpSuggestion>());
  });

  test('identical state is suppressed during cooldown and allowed at boundary', () {
    final first = service.evaluate(input()) as WalletTopUpSuggestion;
    final lastSuggestedAt = evaluatedAt;
    final configured = profile(
      cooldown: const Duration(hours: 6),
      lastSuggestionId: first.suggestionId,
      lastSuggestedAt: lastSuggestedAt,
    );

    final suppressed = service.evaluate(
      input(
        configuredProfile: configured,
        now: evaluatedAt.add(const Duration(hours: 5)),
      ),
    );
    expect(suppressed, isA<WalletTopUpNoSuggestion>());
    expect(
      (suppressed as WalletTopUpNoSuggestion).reason,
      WalletTopUpNoSuggestionReason.cooldownSuppressed,
    );
    expect(suppressed.suppressedSuggestionId, first.suggestionId);

    final boundary = service.evaluate(
      input(
        configuredProfile: configured,
        now: evaluatedAt.add(const Duration(hours: 6)),
      ),
    );
    expect(boundary, isA<WalletTopUpSuggestion>());
  });

  test('changed low-balance state creates a different suggestion identity', () {
    final first = service.evaluate(input()) as WalletTopUpSuggestion;
    final configured = profile(
      cooldown: const Duration(days: 1),
      lastSuggestionId: first.suggestionId,
      lastSuggestedAt: evaluatedAt,
    );

    final changed = service.evaluate(
      input(
        configuredProfile: configured,
        currentBalance: 40,
        now: evaluatedAt.add(const Duration(minutes: 1)),
      ),
    ) as WalletTopUpSuggestion;

    expect(changed.suggestionId, isNot(first.suggestionId));
    expect(changed.suggestedAmount, 460);
  });

  test('disabled, wrong-type, archived, identity and currency contexts fail closed', () {
    expect(
      () => service.evaluate(input(configuredProfile: profile(enabled: false))),
      failsWith(WalletTopUpRecommendationErrorCode.profileDisabled),
    );
    expect(
      () => service.evaluate(
        input(target: targetAccount(type: AccountType.cash)),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.targetAccountTypeMismatch),
    );
    expect(
      () => service.evaluate(
        input(target: targetAccount(archived: true)),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.targetAccountArchived),
    );
    expect(
      () => service.evaluate(
        input(target: targetAccount(id: 'wallet-other')),
      ),
      failsWith(
        WalletTopUpRecommendationErrorCode.targetAccountIdentityMismatch,
      ),
    );
    expect(
      () => service.evaluate(
        input(funding: fundingAccount(archived: true)),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.fundingAccountArchived),
    );
    expect(
      () => service.evaluate(
        input(funding: fundingAccount(id: 'bank-other')),
      ),
      failsWith(
        WalletTopUpRecommendationErrorCode.fundingAccountIdentityMismatch,
      ),
    );
    expect(
      () => service.evaluate(
        input(funding: fundingAccount(currency: CurrencyCode.usd)),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.currencyMismatch),
    );
  });

  test('same target and funding account fails closed', () {
    final wallet = targetAccount();
    expect(
      () => service.evaluate(
        input(
          configuredProfile: profile(fundingId: 'wallet-1'),
          target: wallet,
          funding: wallet,
        ),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.fundingAccountMustDiffer),
    );
  });

  test('invalid numeric and amount-mode configuration fails closed', () {
    expect(
      () => service.evaluate(
        input(configuredProfile: profile(threshold: double.nan)),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.invalidThreshold),
    );
    expect(
      () => service.evaluate(
        input(configuredProfile: profile(targetBalance: 100)),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.invalidTargetBalance),
    );
    expect(
      () => service.evaluate(
        input(
          configuredProfile: profile(
            mode: WalletTopUpAmountMode.fixedAmount,
            fixedAmount: 0.4,
          ),
        ),
      ),
      failsWith(WalletTopUpRecommendationErrorCode.invalidFixedAmount),
    );
    expect(
      () => service.evaluate(input(currentBalance: double.infinity)),
      failsWith(
        WalletTopUpRecommendationErrorCode.invalidCurrentAvailableBalance,
      ),
    );
    expect(
      () => service.evaluate(input(fundingBalance: double.nan)),
      failsWith(
        WalletTopUpRecommendationErrorCode.invalidFundingAvailableBalance,
      ),
    );
  });

  test('previous suggestion state and evaluation time fail closed when invalid', () {
    expect(
      () => service.evaluate(
        input(
          configuredProfile: profile(lastSuggestionId: 'orphan-id'),
        ),
      ),
      failsWith(
        WalletTopUpRecommendationErrorCode.incompletePreviousSuggestionState,
      ),
    );
    expect(
      () => service.evaluate(
        input(
          configuredProfile: profile(
            lastSuggestionId: 'previous',
            lastSuggestedAt: evaluatedAt.add(const Duration(minutes: 1)),
          ),
        ),
      ),
      failsWith(
        WalletTopUpRecommendationErrorCode.evaluationBeforePreviousSuggestion,
      ),
    );
  });
}
