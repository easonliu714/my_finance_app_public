import 'package:sqflite/sqflite.dart';

import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'account_event_record.dart';
import 'account_ledger_calculator.dart';
import 'account_record.dart';
import 'wallet_top_up_execution.dart';
import 'wallet_top_up_persistence.dart';
import 'wallet_top_up_recommendation.dart';

class StoredValueAutoTopUpService {
  const StoredValueAutoTopUpService(
    this.database, {
    this.ledgerCalculator = const AccountLedgerCalculator(),
    this.recommendationService = const WalletTopUpRecommendationService(),
    this.clock = DateTime.now,
  });

  final Database database;
  final AccountLedgerCalculator ledgerCalculator;
  final WalletTopUpRecommendationService recommendationService;
  final DateTime Function() clock;

  Future<StoredValueAutoTopUpInsertResult> insertSourceTransaction(
    TransactionRecord source,
  ) {
    return database.transaction((txn) async {
      final existingSource = await txn.query(
        'transactions',
        columns: const <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[source.id],
        limit: 1,
      );
      if (existingSource.isNotEmpty) {
        return StoredValueAutoTopUpInsertResult(
          sourceInserted: false,
          replayed: true,
          execution: await _findExecution(txn, source.id),
        );
      }

      await txn.insert(
        'transactions',
        source.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (source.type != TransactionType.expense) {
        return const StoredValueAutoTopUpInsertResult(
          sourceInserted: true,
          replayed: false,
        );
      }

      final accounts = (await txn.query('accounts'))
          .map(AccountRecord.fromMap)
          .toList(growable: false);
      final target = _findAccountByDisplayName(accounts, source.accountName);
      if (target == null ||
          target.isArchived ||
          (target.type != AccountType.storedValue &&
              target.type != AccountType.eWallet)) {
        return const StoredValueAutoTopUpInsertResult(
          sourceInserted: true,
          replayed: false,
        );
      }

      final profileRows = await txn.query(
        'wallet_top_up_profiles',
        where: 'target_account_id = ? AND is_enabled = 1',
        whereArgs: <Object?>[target.id],
        limit: 1,
      );
      if (profileRows.isEmpty) {
        return const StoredValueAutoTopUpInsertResult(
          sourceInserted: true,
          replayed: false,
        );
      }
      final profile = StoredWalletTopUpProfile.fromMap(profileRows.single);
      final funding = _findAccountById(accounts, profile.fundingAccountId);
      if (funding == null ||
          funding.isArchived ||
          funding.id == target.id ||
          funding.currency != target.currency ||
          profile.currency != target.currency) {
        throw const WalletTopUpRecommendationException(
          WalletTopUpRecommendationErrorCode.currencyMismatch,
          'The enabled stored-value rule references an invalid linked account.',
        );
      }

      final transactions = (await txn.query('transactions'))
          .map(TransactionRecord.fromMap)
          .toList(growable: false);
      final targetBalance = await _currentBalance(
        txn,
        account: target,
        accounts: accounts,
        transactions: transactions,
      );
      final fundingBalance = await _currentBalance(
        txn,
        account: funding,
        accounts: accounts,
        transactions: transactions,
      );
      final latest = await _latestEvaluation(txn, profile.id);
      final evaluatedAt = clock().toUtc();
      final evaluation = recommendationService.evaluate(
        WalletTopUpEvaluationInput(
          profile: profile.toDomainProfile(
            lastSuggestionId: latest?.evaluationIdentity,
            lastSuggestedAt: latest?.createdAt,
          ),
          targetAccount: target,
          fundingAccount: funding,
          currentAvailableBalance: targetBalance,
          fundingAvailableBalance: fundingBalance,
          evaluatedAt: evaluatedAt,
        ),
      );

      if (evaluation is WalletTopUpNoSuggestion) {
        final execution = _executionForNoSuggestion(
          source: source,
          profile: profile,
          targetBalance: targetBalance,
          fundingBalance: fundingBalance,
          evaluation: evaluation,
          createdAt: evaluatedAt,
        );
        await txn.insert(
          'wallet_top_up_executions',
          execution.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        return StoredValueAutoTopUpInsertResult(
          sourceInserted: true,
          replayed: false,
          execution: execution,
        );
      }

      final suggestion = evaluation as WalletTopUpSuggestion;
      if (!suggestion.fundingSufficient) {
        final execution = WalletTopUpExecutionRecord(
          id: _executionId(source.id),
          sourceTransactionId: source.id,
          profileId: profile.id,
          evaluationIdentity: suggestion.suggestionId,
          targetAccountId: target.id,
          fundingAccountId: funding.id,
          currency: profile.currency,
          balanceAfterExpense: targetBalance,
          fundingBalanceBeforeTopUp: fundingBalance,
          threshold: profile.threshold,
          topUpAmount: suggestion.suggestedAmount,
          outcome: WalletTopUpExecutionOutcome.fundingInsufficient,
          reasonCode: WalletTopUpExecutionReasonCode.fundingInsufficient,
          createdAt: evaluatedAt,
        );
        await txn.insert(
          'wallet_top_up_executions',
          execution.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        return StoredValueAutoTopUpInsertResult(
          sourceInserted: true,
          replayed: false,
          execution: execution,
        );
      }

      final transferId = _transferId(source.id);
      final transfer = TransactionRecord(
        id: transferId,
        type: TransactionType.transfer,
        amount: suggestion.suggestedAmount,
        category: '自動儲值',
        occurredAt: source.occurredAt.add(const Duration(milliseconds: 1)),
        accountName: funding.displayName,
        memberName: source.memberName,
        merchantName: '',
        tagName: '低餘額規則',
        note: 'App 本機自動儲值記帳；來源交易 ${source.id}；規則 ${profile.id}',
        currency: profile.currency,
        exchangeRateToBase: profile.currency.defaultRateToTwd,
        fromAccountName: funding.displayName,
        toAccountName: target.displayName,
      );
      await txn.insert(
        'transactions',
        transfer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      final execution = WalletTopUpExecutionRecord(
        id: _executionId(source.id),
        sourceTransactionId: source.id,
        profileId: profile.id,
        evaluationIdentity: suggestion.suggestionId,
        generatedTransferTransactionId: transfer.id,
        targetAccountId: target.id,
        fundingAccountId: funding.id,
        currency: profile.currency,
        balanceAfterExpense: targetBalance,
        fundingBalanceBeforeTopUp: fundingBalance,
        threshold: profile.threshold,
        topUpAmount: suggestion.suggestedAmount,
        outcome: WalletTopUpExecutionOutcome.posted,
        reasonCode: WalletTopUpExecutionReasonCode.none,
        createdAt: evaluatedAt,
      );
      await txn.insert(
        'wallet_top_up_executions',
        execution.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return StoredValueAutoTopUpInsertResult(
        sourceInserted: true,
        replayed: false,
        execution: execution,
      );
    });
  }

  Future<double> _currentBalance(
    DatabaseExecutor executor, {
    required AccountRecord account,
    required List<AccountRecord> accounts,
    required List<TransactionRecord> transactions,
  }) async {
    final eventRows = await executor.query(
      'account_events',
      where: 'account_name = ?',
      whereArgs: <Object?>[account.displayName],
    );
    return ledgerCalculator.currentBalance(
      account: account,
      accounts: accounts,
      events: eventRows.map(AccountEventRecord.fromMap),
      transactions: transactions.where(
        (transaction) => _belongsToAccount(transaction, account),
      ),
    );
  }

  bool _belongsToAccount(
    TransactionRecord transaction,
    AccountRecord account,
  ) {
    final accountName = account.displayName;
    if (transaction.type == TransactionType.transfer) {
      final fromName =
          (transaction.fromAccountName ?? transaction.accountName).trim();
      final toName = (transaction.toAccountName ?? '').trim();
      return fromName == accountName || toName == accountName;
    }
    return transaction.accountName.trim() == accountName;
  }

  Future<WalletTopUpExecutionRecord?> _findExecution(
    DatabaseExecutor executor,
    String sourceTransactionId,
  ) async {
    final rows = await executor.query(
      'wallet_top_up_executions',
      where: 'source_transaction_id = ?',
      whereArgs: <Object?>[sourceTransactionId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : WalletTopUpExecutionRecord.fromMap(rows.single);
  }

  Future<WalletTopUpExecutionRecord?> _latestEvaluation(
    DatabaseExecutor executor,
    String profileId,
  ) async {
    final rows = await executor.query(
      'wallet_top_up_executions',
      where: "profile_id = ? AND evaluation_identity <> ''",
      whereArgs: <Object?>[profileId],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : WalletTopUpExecutionRecord.fromMap(rows.single);
  }

  WalletTopUpExecutionRecord _executionForNoSuggestion({
    required TransactionRecord source,
    required StoredWalletTopUpProfile profile,
    required double targetBalance,
    required double fundingBalance,
    required WalletTopUpNoSuggestion evaluation,
    required DateTime createdAt,
  }) {
    final cooldown = evaluation.reason ==
        WalletTopUpNoSuggestionReason.cooldownSuppressed;
    return WalletTopUpExecutionRecord(
      id: _executionId(source.id),
      sourceTransactionId: source.id,
      profileId: profile.id,
      evaluationIdentity: evaluation.suppressedSuggestionId ?? '',
      targetAccountId: profile.targetAccountId,
      fundingAccountId: profile.fundingAccountId,
      currency: profile.currency,
      balanceAfterExpense: targetBalance,
      fundingBalanceBeforeTopUp: fundingBalance,
      threshold: profile.threshold,
      topUpAmount: 0,
      outcome: cooldown
          ? WalletTopUpExecutionOutcome.cooldownSuppressed
          : WalletTopUpExecutionOutcome.notNeeded,
      reasonCode: cooldown
          ? WalletTopUpExecutionReasonCode.cooldownSuppressed
          : WalletTopUpExecutionReasonCode.balanceAtOrAboveThreshold,
      createdAt: createdAt,
    );
  }

  AccountRecord? _findAccountByDisplayName(
    Iterable<AccountRecord> accounts,
    String displayName,
  ) {
    for (final account in accounts) {
      if (account.displayName == displayName.trim()) return account;
    }
    return null;
  }

  AccountRecord? _findAccountById(
    Iterable<AccountRecord> accounts,
    String id,
  ) {
    for (final account in accounts) {
      if (account.id == id.trim()) return account;
    }
    return null;
  }

  String _executionId(String sourceTransactionId) =>
      'wallet-top-up-execution-${sourceTransactionId.trim()}';

  String _transferId(String sourceTransactionId) =>
      'wallet-top-up-transfer-${sourceTransactionId.trim()}';
}
