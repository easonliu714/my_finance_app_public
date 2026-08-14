import 'dart:convert';

import 'account_record.dart';

enum WalletTopUpAmountMode {
  targetBalance,
  fixedAmount,
}

enum WalletTopUpNoSuggestionReason {
  balanceAtOrAboveThreshold,
  cooldownSuppressed,
}

enum WalletTopUpRecommendationErrorCode {
  profileDisabled,
  targetAccountIdentityMismatch,
  targetAccountTypeMismatch,
  targetAccountArchived,
  fundingAccountIdentityMismatch,
  fundingAccountArchived,
  fundingAccountMustDiffer,
  currencyMismatch,
  invalidThreshold,
  invalidTargetBalance,
  invalidFixedAmount,
  invalidCooldown,
  invalidCurrentAvailableBalance,
  invalidFundingAvailableBalance,
  incompletePreviousSuggestionState,
  evaluationBeforePreviousSuggestion,
  suggestionAmountNotPositive,
}

class WalletTopUpRecommendationException implements Exception {
  const WalletTopUpRecommendationException(this.code, this.message);

  final WalletTopUpRecommendationErrorCode code;
  final String message;

  @override
  String toString() =>
      'WalletTopUpRecommendationException($code): $message';
}

class WalletTopUpProfile {
  const WalletTopUpProfile({
    required this.targetAccountId,
    required this.fundingAccountId,
    required this.currency,
    required this.threshold,
    required this.amountMode,
    this.targetBalance = 0,
    this.fixedAmount = 0,
    this.isEnabled = true,
    this.cooldown = Duration.zero,
    this.lastSuggestionId,
    this.lastSuggestedAt,
  });

  final String targetAccountId;
  final String fundingAccountId;
  final CurrencyCode currency;
  final double threshold;
  final WalletTopUpAmountMode amountMode;
  final double targetBalance;
  final double fixedAmount;
  final bool isEnabled;
  final Duration cooldown;
  final String? lastSuggestionId;
  final DateTime? lastSuggestedAt;
}

class WalletTopUpEvaluationInput {
  const WalletTopUpEvaluationInput({
    required this.profile,
    required this.targetAccount,
    required this.fundingAccount,
    required this.currentAvailableBalance,
    required this.fundingAvailableBalance,
    required this.evaluatedAt,
  });

  final WalletTopUpProfile profile;
  final AccountRecord targetAccount;
  final AccountRecord fundingAccount;
  final double currentAvailableBalance;
  final double fundingAvailableBalance;
  final DateTime evaluatedAt;
}

sealed class WalletTopUpEvaluationResult {
  const WalletTopUpEvaluationResult();
}

class WalletTopUpNoSuggestion extends WalletTopUpEvaluationResult {
  const WalletTopUpNoSuggestion({
    required this.reason,
    required this.currentAvailableBalance,
    required this.threshold,
    this.suppressedSuggestionId,
  });

  final WalletTopUpNoSuggestionReason reason;
  final double currentAvailableBalance;
  final double threshold;
  final String? suppressedSuggestionId;
}

class WalletTopUpSuggestion extends WalletTopUpEvaluationResult {
  const WalletTopUpSuggestion({
    required this.suggestionId,
    required this.targetAccountId,
    required this.fundingAccountId,
    required this.currency,
    required this.amountMode,
    required this.currentAvailableBalance,
    required this.fundingAvailableBalance,
    required this.threshold,
    required this.suggestedAmount,
    required this.fundingSufficient,
    required this.evaluatedAt,
  });

  final String suggestionId;
  final String targetAccountId;
  final String fundingAccountId;
  final CurrencyCode currency;
  final WalletTopUpAmountMode amountMode;
  final double currentAvailableBalance;
  final double fundingAvailableBalance;
  final double threshold;
  final double suggestedAmount;
  final bool fundingSufficient;
  final DateTime evaluatedAt;

  double get fundingShortfall => currency.roundAmount(
        fundingSufficient ? 0 : suggestedAmount - fundingAvailableBalance,
      );
}

class WalletTopUpRecommendationService {
  const WalletTopUpRecommendationService();

  WalletTopUpEvaluationResult evaluate(WalletTopUpEvaluationInput input) {
    final normalized = _validateAndNormalize(input);

    if (normalized.currentAvailableBalance >= normalized.threshold) {
      return WalletTopUpNoSuggestion(
        reason: WalletTopUpNoSuggestionReason.balanceAtOrAboveThreshold,
        currentAvailableBalance: normalized.currentAvailableBalance,
        threshold: normalized.threshold,
      );
    }

    final suggestedAmount = _calculateSuggestedAmount(normalized);
    if (suggestedAmount <= 0) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.suggestionAmountNotPositive,
        'Suggested amount must remain positive after currency rounding.',
      );
    }

    final suggestionId = _buildSuggestionId(
      input: input,
      normalized: normalized,
      suggestedAmount: suggestedAmount,
    );

    final lastSuggestionId = input.profile.lastSuggestionId;
    final lastSuggestedAt = input.profile.lastSuggestedAt;
    if (lastSuggestionId == suggestionId && lastSuggestedAt != null) {
      if (input.evaluatedAt.difference(lastSuggestedAt) <
          input.profile.cooldown) {
        return WalletTopUpNoSuggestion(
          reason: WalletTopUpNoSuggestionReason.cooldownSuppressed,
          currentAvailableBalance: normalized.currentAvailableBalance,
          threshold: normalized.threshold,
          suppressedSuggestionId: suggestionId,
        );
      }
    }

    final fundingSufficient =
        normalized.fundingAvailableBalance >= suggestedAmount;
    return WalletTopUpSuggestion(
      suggestionId: suggestionId,
      targetAccountId: input.profile.targetAccountId,
      fundingAccountId: input.profile.fundingAccountId,
      currency: input.profile.currency,
      amountMode: input.profile.amountMode,
      currentAvailableBalance: normalized.currentAvailableBalance,
      fundingAvailableBalance: normalized.fundingAvailableBalance,
      threshold: normalized.threshold,
      suggestedAmount: suggestedAmount,
      fundingSufficient: fundingSufficient,
      evaluatedAt: input.evaluatedAt,
    );
  }

  _NormalizedWalletTopUpInput _validateAndNormalize(
    WalletTopUpEvaluationInput input,
  ) {
    final profile = input.profile;
    if (!profile.isEnabled) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.profileDisabled,
        'Wallet top-up profile is disabled.',
      );
    }
    if (input.targetAccount.id != profile.targetAccountId) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.targetAccountIdentityMismatch,
        'Target account does not match the profile owner.',
      );
    }
    if (input.targetAccount.type != AccountType.eWallet &&
        input.targetAccount.type != AccountType.storedValue) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.targetAccountTypeMismatch,
        'Target account must be an electronic wallet or stored-value account.',
      );
    }
    if (input.targetAccount.isArchived) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.targetAccountArchived,
        'Archived target accounts cannot receive top-up suggestions.',
      );
    }
    if (input.fundingAccount.id != profile.fundingAccountId) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.fundingAccountIdentityMismatch,
        'Funding account does not match the profile.',
      );
    }
    if (input.fundingAccount.isArchived) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.fundingAccountArchived,
        'Archived funding accounts cannot fund top-up suggestions.',
      );
    }
    if (profile.targetAccountId == profile.fundingAccountId) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.fundingAccountMustDiffer,
        'Funding and target accounts must be different.',
      );
    }
    if (input.targetAccount.currency != profile.currency ||
        input.fundingAccount.currency != profile.currency) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.currencyMismatch,
        'Profile, target account, and funding account currencies must match.',
      );
    }
    if (!profile.threshold.isFinite || profile.threshold < 0) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.invalidThreshold,
        'Threshold must be a finite non-negative value.',
      );
    }
    if (profile.cooldown.isNegative) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.invalidCooldown,
        'Cooldown cannot be negative.',
      );
    }
    final hasLastSuggestionId =
        profile.lastSuggestionId != null && profile.lastSuggestionId!.isNotEmpty;
    final hasLastSuggestedAt = profile.lastSuggestedAt != null;
    if (hasLastSuggestionId != hasLastSuggestedAt) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.incompletePreviousSuggestionState,
        'Previous suggestion ID and timestamp must be supplied together.',
      );
    }
    if (hasLastSuggestedAt &&
        input.evaluatedAt.isBefore(profile.lastSuggestedAt!)) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.evaluationBeforePreviousSuggestion,
        'Evaluation time cannot be before the previous suggestion time.',
      );
    }
    if (!input.currentAvailableBalance.isFinite) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.invalidCurrentAvailableBalance,
        'Current available balance must be finite.',
      );
    }
    if (!input.fundingAvailableBalance.isFinite) {
      throw const WalletTopUpRecommendationException(
        WalletTopUpRecommendationErrorCode.invalidFundingAvailableBalance,
        'Funding available balance must be finite.',
      );
    }

    final currency = profile.currency;
    final threshold = currency.roundAmount(profile.threshold);
    final currentAvailableBalance =
        currency.roundAmount(input.currentAvailableBalance);
    final fundingAvailableBalance =
        currency.roundAmount(input.fundingAvailableBalance);

    switch (profile.amountMode) {
      case WalletTopUpAmountMode.targetBalance:
        if (!profile.targetBalance.isFinite) {
          throw const WalletTopUpRecommendationException(
            WalletTopUpRecommendationErrorCode.invalidTargetBalance,
            'Target balance must be finite.',
          );
        }
        final targetBalance = currency.roundAmount(profile.targetBalance);
        if (targetBalance <= threshold) {
          throw const WalletTopUpRecommendationException(
            WalletTopUpRecommendationErrorCode.invalidTargetBalance,
            'Target balance must be greater than the threshold.',
          );
        }
        return _NormalizedWalletTopUpInput(
          currency: currency,
          amountMode: profile.amountMode,
          threshold: threshold,
          targetBalance: targetBalance,
          fixedAmount: 0,
          currentAvailableBalance: currentAvailableBalance,
          fundingAvailableBalance: fundingAvailableBalance,
        );
      case WalletTopUpAmountMode.fixedAmount:
        if (!profile.fixedAmount.isFinite) {
          throw const WalletTopUpRecommendationException(
            WalletTopUpRecommendationErrorCode.invalidFixedAmount,
            'Fixed amount must be finite.',
          );
        }
        final fixedAmount = currency.roundAmount(profile.fixedAmount);
        if (fixedAmount <= 0) {
          throw const WalletTopUpRecommendationException(
            WalletTopUpRecommendationErrorCode.invalidFixedAmount,
            'Fixed amount must remain positive after currency rounding.',
          );
        }
        return _NormalizedWalletTopUpInput(
          currency: currency,
          amountMode: profile.amountMode,
          threshold: threshold,
          targetBalance: 0,
          fixedAmount: fixedAmount,
          currentAvailableBalance: currentAvailableBalance,
          fundingAvailableBalance: fundingAvailableBalance,
        );
    }
  }

  double _calculateSuggestedAmount(_NormalizedWalletTopUpInput input) {
    switch (input.amountMode) {
      case WalletTopUpAmountMode.targetBalance:
        return input.currency.roundAmount(
          input.targetBalance - input.currentAvailableBalance,
        );
      case WalletTopUpAmountMode.fixedAmount:
        return input.fixedAmount;
    }
  }

  String _buildSuggestionId({
    required WalletTopUpEvaluationInput input,
    required _NormalizedWalletTopUpInput normalized,
    required double suggestedAmount,
  }) {
    final currency = input.profile.currency;
    final canonical = <String>[
      input.profile.targetAccountId,
      input.profile.fundingAccountId,
      currency.code,
      input.profile.amountMode.name,
      _canonicalAmount(currency, normalized.threshold),
      _canonicalAmount(currency, normalized.targetBalance),
      _canonicalAmount(currency, normalized.fixedAmount),
      _canonicalAmount(currency, normalized.currentAvailableBalance),
      _canonicalAmount(currency, suggestedAmount),
    ].join('|');
    return 'wallet-top-up-${_fnv1a64(canonical)}';
  }
}

class _NormalizedWalletTopUpInput {
  const _NormalizedWalletTopUpInput({
    required this.currency,
    required this.amountMode,
    required this.threshold,
    required this.targetBalance,
    required this.fixedAmount,
    required this.currentAvailableBalance,
    required this.fundingAvailableBalance,
  });

  final CurrencyCode currency;
  final WalletTopUpAmountMode amountMode;
  final double threshold;
  final double targetBalance;
  final double fixedAmount;
  final double currentAvailableBalance;
  final double fundingAvailableBalance;
}

String _canonicalAmount(CurrencyCode currency, double value) {
  return currency.roundAmount(value).toStringAsFixed(currency.decimalDigits);
}

String _fnv1a64(String value) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xffffffffffffffff;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
