import 'account_ledger_calculator.dart';
import 'account_record.dart';
import 'wallet_top_up_recommendation.dart';
import 'wallet_top_up_recommendation_read_source.dart';

enum WalletTopUpRecommendationReadErrorCode {
  targetAccountNotFound,
  fundingAccountNotFound,
}

class WalletTopUpRecommendationReadException implements Exception {
  const WalletTopUpRecommendationReadException(this.code, this.message);

  final WalletTopUpRecommendationReadErrorCode code;
  final String message;

  @override
  String toString() =>
      'WalletTopUpRecommendationReadException($code): $message';
}

class WalletTopUpRecommendationReadService {
  const WalletTopUpRecommendationReadService({
    required this.source,
    this.ledgerCalculator = const AccountLedgerCalculator(),
    this.recommendationService = const WalletTopUpRecommendationService(),
  });

  final WalletTopUpRecommendationReadSource source;
  final AccountLedgerCalculator ledgerCalculator;
  final WalletTopUpRecommendationService recommendationService;

  Future<WalletTopUpEvaluationResult> evaluate({
    required WalletTopUpProfile profile,
    required DateTime evaluatedAt,
  }) async {
    final accounts = await source.listAccounts(includeArchived: true);
    final targetAccount = _findAccount(accounts, profile.targetAccountId);
    if (targetAccount == null) {
      throw WalletTopUpRecommendationReadException(
        WalletTopUpRecommendationReadErrorCode.targetAccountNotFound,
        'Target account ${profile.targetAccountId} does not exist.',
      );
    }

    final fundingAccount = _findAccount(accounts, profile.fundingAccountId);
    if (fundingAccount == null) {
      throw WalletTopUpRecommendationReadException(
        WalletTopUpRecommendationReadErrorCode.fundingAccountNotFound,
        'Funding account ${profile.fundingAccountId} does not exist.',
      );
    }

    final accountByDisplayName = <String, AccountRecord>{
      targetAccount.displayName: targetAccount,
      fundingAccount.displayName: fundingAccount,
    };
    final balanceByDisplayName = <String, double>{};

    for (final entry in accountByDisplayName.entries) {
      final accountName = entry.key;
      final events = await source.listAccountEvents(accountName);
      final transactions = await source.listAccountTransactions(accountName);
      balanceByDisplayName[accountName] = ledgerCalculator.currentBalance(
        account: entry.value,
        accounts: accounts,
        events: events,
        transactions: transactions,
      );
    }

    return recommendationService.evaluate(
      WalletTopUpEvaluationInput(
        profile: profile,
        targetAccount: targetAccount,
        fundingAccount: fundingAccount,
        currentAvailableBalance:
            balanceByDisplayName[targetAccount.displayName]!,
        fundingAvailableBalance:
            balanceByDisplayName[fundingAccount.displayName]!,
        evaluatedAt: evaluatedAt,
      ),
    );
  }

  AccountRecord? _findAccount(
    Iterable<AccountRecord> accounts,
    String id,
  ) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }
}
