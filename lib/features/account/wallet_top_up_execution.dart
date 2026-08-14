import 'account_record.dart';

enum WalletTopUpExecutionOutcome {
  posted,
  notNeeded,
  cooldownSuppressed,
  fundingInsufficient,
}

enum WalletTopUpExecutionReasonCode {
  none,
  balanceAtOrAboveThreshold,
  cooldownSuppressed,
  fundingInsufficient,
}

class WalletTopUpExecutionRecord {
  const WalletTopUpExecutionRecord({
    required this.id,
    required this.sourceTransactionId,
    required this.profileId,
    required this.evaluationIdentity,
    required this.targetAccountId,
    required this.fundingAccountId,
    required this.currency,
    required this.balanceAfterExpense,
    required this.fundingBalanceBeforeTopUp,
    required this.threshold,
    required this.topUpAmount,
    required this.outcome,
    required this.reasonCode,
    required this.createdAt,
    this.generatedTransferTransactionId,
  });

  final String id;
  final String sourceTransactionId;
  final String profileId;
  final String evaluationIdentity;
  final String? generatedTransferTransactionId;
  final String targetAccountId;
  final String fundingAccountId;
  final CurrencyCode currency;
  final double balanceAfterExpense;
  final double fundingBalanceBeforeTopUp;
  final double threshold;
  final double topUpAmount;
  final WalletTopUpExecutionOutcome outcome;
  final WalletTopUpExecutionReasonCode reasonCode;
  final DateTime createdAt;

  bool get posted => outcome == WalletTopUpExecutionOutcome.posted;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'source_transaction_id': sourceTransactionId,
        'profile_id': profileId,
        'evaluation_identity': evaluationIdentity,
        'generated_transfer_transaction_id': generatedTransferTransactionId,
        'target_account_id': targetAccountId,
        'funding_account_id': fundingAccountId,
        'currency_code': currency.code,
        'balance_after_expense': balanceAfterExpense,
        'funding_balance_before_top_up': fundingBalanceBeforeTopUp,
        'threshold_amount': threshold,
        'top_up_amount': topUpAmount,
        'outcome': outcome.name,
        'reason_code': reasonCode.name,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory WalletTopUpExecutionRecord.fromMap(Map<String, Object?> map) {
    return WalletTopUpExecutionRecord(
      id: map['id'] as String,
      sourceTransactionId: map['source_transaction_id'] as String,
      profileId: map['profile_id'] as String,
      evaluationIdentity: map['evaluation_identity'] as String? ?? '',
      generatedTransferTransactionId:
          map['generated_transfer_transaction_id'] as String?,
      targetAccountId: map['target_account_id'] as String,
      fundingAccountId: map['funding_account_id'] as String,
      currency: currencyFromCode(map['currency_code'] as String?),
      balanceAfterExpense:
          (map['balance_after_expense'] as num).toDouble(),
      fundingBalanceBeforeTopUp:
          (map['funding_balance_before_top_up'] as num).toDouble(),
      threshold: (map['threshold_amount'] as num).toDouble(),
      topUpAmount: (map['top_up_amount'] as num).toDouble(),
      outcome: WalletTopUpExecutionOutcome.values.byName(
        map['outcome'] as String,
      ),
      reasonCode: WalletTopUpExecutionReasonCode.values.byName(
        map['reason_code'] as String? ?? 'none',
      ),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}

class StoredValueAutoTopUpInsertResult {
  const StoredValueAutoTopUpInsertResult({
    required this.sourceInserted,
    required this.replayed,
    this.execution,
  });

  final bool sourceInserted;
  final bool replayed;
  final WalletTopUpExecutionRecord? execution;

  bool get posted => execution?.posted == true;
}

class WalletTopUpExecutionMutationBlocked implements Exception {
  const WalletTopUpExecutionMutationBlocked(this.message);

  final String message;

  @override
  String toString() => message;
}
