import 'package:sqflite/sqflite.dart';

import '../account/account_event_record.dart';
import '../account/account_ledger_calculator.dart';
import '../account/account_record.dart';
import '../account/debit_card_repository.dart';
import 'debit_card_settlement.dart';
import 'debit_card_settlement_confirmation.dart';
import 'transaction_record.dart';
import 'transaction_type.dart';

enum DebitCardSettlementConfirmationWriteStage {
  beforeTransferInsert,
  afterTransferInsert,
  afterSettlementUpdate,
  afterAuditInsert,
}

typedef DebitCardSettlementConfirmationWriteStageHook = Future<void> Function(
  DebitCardSettlementConfirmationWriteStage stage,
);

class DebitCardSettlementConfirmationService {
  const DebitCardSettlementConfirmationService({
    required this.databaseProvider,
    this.ledgerCalculator = const AccountLedgerCalculator(),
    this.writeStageHook,
  });

  final Future<Database> Function() databaseProvider;
  final AccountLedgerCalculator ledgerCalculator;
  final DebitCardSettlementConfirmationWriteStageHook? writeStageHook;

  Future<DebitCardSettlementConfirmationReceipt> confirm(
    DebitCardSettlementConfirmationRequest request,
  ) async {
    _validateRequest(request);
    final fingerprint = await request.payloadFingerprint();
    final db = await databaseProvider();

    return db.transaction((txn) async {
      final replay = await _resolveReplay(
        txn,
        request: request,
        fingerprint: fingerprint,
      );
      if (replay != null) return replay;

      final settlement = await _requireSettlement(
        txn,
        request.normalizedSettlementId,
      );
      if (settlement.status != DebitCardSettlementStatus.pending) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.settlementNotPending,
          'Only a pending settlement can be confirmed.',
        );
      }
      if (settlement.settlementTransferTransactionId?.trim().isNotEmpty ==
          true) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.settlementConflict,
          'A pending settlement must not already have a transfer identity.',
        );
      }

      await _assertUnusedTransferIdentity(txn, request);

      final sourceTransaction = await _requireSourceTransaction(
        txn,
        settlement.transactionId,
      );
      final accounts = await _listAccounts(txn);
      final debitCard = _findAccount(accounts, settlement.debitCardAccountId);
      if (debitCard == null) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.debitCardAccountNotFound,
          'Debit-card account does not exist.',
        );
      }
      if (debitCard.isArchived) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.debitCardAccountArchived,
          'Archived debit-card accounts cannot confirm a settlement.',
        );
      }
      if (debitCard.type != AccountType.debitCard) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.debitCardAccountInvalid,
          'Settlement owner must be a debit-card account.',
        );
      }

      final linkedBank = _findAccount(accounts, settlement.linkedBankAccountId);
      if (linkedBank == null) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.linkedBankAccountNotFound,
          'Linked bank account does not exist.',
        );
      }
      if (linkedBank.isArchived) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.linkedBankAccountArchived,
          'Archived linked bank accounts cannot confirm a settlement.',
        );
      }
      if (linkedBank.type != AccountType.bank) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.linkedBankAccountInvalid,
          'Settlement funding account must be a bank account.',
        );
      }

      final profile = await DebitCardRepository(txn).getProfile(debitCard.id);
      if (profile == null) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.profileNotFound,
          'Debit-card profile does not exist.',
        );
      }
      if (!profile.isEnabled) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.profileDisabled,
          'Debit-card profile is disabled.',
        );
      }
      if (profile.debitCardAccountId != debitCard.id ||
          profile.linkedBankAccountId != linkedBank.id) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.profileMismatch,
          'Debit-card profile does not match the settlement relationship.',
        );
      }

      _validateFinancialContext(
        settlement: settlement,
        sourceTransaction: sourceTransaction,
        debitCard: debitCard,
        linkedBank: linkedBank,
        profileCurrency: profile.currency,
      );

      final bankEvents = await _listAccountEvents(
        txn,
        linkedBank.displayName,
      );
      final bankTransactions = await _listAccountTransactions(
        txn,
        linkedBank.displayName,
      );
      final pendingSettlements = await _listPendingSettlements(
        txn,
        linkedBankAccountId: linkedBank.id,
        currency: linkedBank.currency,
      );
      if (!pendingSettlements.any((item) => item.id == settlement.id)) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.concurrentModification,
          'The target settlement is no longer part of the pending reservation set.',
        );
      }

      final ledgerBalanceBefore = ledgerCalculator.currentBalance(
        account: linkedBank,
        accounts: accounts,
        events: bankEvents,
        transactions: bankTransactions,
      );
      const planner = DebitCardSettlementPlanner();
      final reservedBefore = planner.reservedAmount(
        settlements: pendingSettlements,
        linkedBankAccountId: linkedBank.id,
        currency: linkedBank.currency,
      );
      final availableBefore = planner.availableBalance(
        currentBankBalance: ledgerBalanceBefore,
        settlements: pendingSettlements,
        linkedBankAccountId: linkedBank.id,
        currency: linkedBank.currency,
      );
      final amount = linkedBank.currency.roundAmount(settlement.amount);
      final ledgerBalanceAfter = linkedBank.currency.roundAmount(
        ledgerBalanceBefore - amount,
      );
      final reservedAfter = linkedBank.currency.roundAmount(
        reservedBefore - amount,
      );
      if (reservedAfter < 0) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.concurrentModification,
          'Pending reservations no longer contain the settlement amount.',
        );
      }
      final availableAfter = linkedBank.currency.roundAmount(
        ledgerBalanceAfter - reservedAfter,
      );
      if (availableAfter != availableBefore) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.concurrentModification,
          'Settlement confirmation would double-count the linked-bank amount.',
        );
      }

      final transferTransaction = TransactionRecord(
        id: request.normalizedTransferTransactionId,
        type: TransactionType.transfer,
        amount: amount,
        category: '簽帳金融卡扣款',
        occurredAt: request.confirmedAt.toUtc(),
        accountName: linkedBank.displayName,
        memberName: sourceTransaction.memberName,
        merchantName: sourceTransaction.merchantName,
        tagName: '扣款',
        note: '簽帳金融卡扣款確認｜${settlement.id}',
        currency: settlement.currency,
        exchangeRateToBase: sourceTransaction.exchangeRateToBase,
        fromAccountName: linkedBank.displayName,
        toAccountName: debitCard.displayName,
      );
      final confirmedSettlement = settlement.confirm(
        request.confirmedAt.toUtc(),
        settlementTransferTransactionId: transferTransaction.id,
      );
      final audit = DebitCardSettlementConfirmationAuditRecord(
        requestId: request.normalizedRequestId,
        payloadFingerprint: fingerprint,
        settlementId: settlement.id,
        sourceTransactionId: sourceTransaction.id,
        transferTransactionId: transferTransaction.id,
        debitCardAccountId: debitCard.id,
        linkedBankAccountId: linkedBank.id,
        amount: amount,
        currency: settlement.currency,
        ledgerBalanceBefore: ledgerBalanceBefore,
        reservedBefore: reservedBefore,
        availableBefore: availableBefore,
        ledgerBalanceAfter: ledgerBalanceAfter,
        reservedAfter: reservedAfter,
        availableAfter: availableAfter,
        confirmedAt: request.confirmedAt.toUtc(),
        statusBefore: DebitCardSettlementStatus.pending.name,
        statusAfter: DebitCardSettlementStatus.confirmed.name,
      );

      await _notify(
        DebitCardSettlementConfirmationWriteStage.beforeTransferInsert,
      );
      await txn.insert(
        'transactions',
        transferTransaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _notify(
        DebitCardSettlementConfirmationWriteStage.afterTransferInsert,
      );
      final updatedRows = await txn.update(
        'debit_card_settlements',
        confirmedSettlement.toMap(),
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[
          settlement.id,
          DebitCardSettlementStatus.pending.name,
        ],
      );
      if (updatedRows != 1) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.concurrentModification,
          'Settlement status changed before confirmation could commit.',
        );
      }
      await _notify(
        DebitCardSettlementConfirmationWriteStage.afterSettlementUpdate,
      );
      await txn.insert(
        'debit_card_settlement_confirmation_audits',
        audit.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _notify(
        DebitCardSettlementConfirmationWriteStage.afterAuditInsert,
      );

      return DebitCardSettlementConfirmationReceipt(
        sourceTransaction: sourceTransaction,
        transferTransaction: transferTransaction,
        settlement: confirmedSettlement,
        audit: audit,
      );
    });
  }

  Future<bool> isConfirmedTransfer(String transactionId) async {
    final normalizedId = transactionId.trim();
    if (normalizedId.isEmpty) return false;
    final db = await databaseProvider();
    final rows = await db.query(
      'debit_card_settlement_confirmation_audits',
      columns: const <String>['transfer_transaction_id'],
      where: 'transfer_transaction_id = ?',
      whereArgs: <Object?>[normalizedId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> requireMutableTransfer(String transactionId) async {
    if (await isConfirmedTransfer(transactionId)) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.confirmedTransferImmutable,
        'Confirmed debit-card settlement transfers cannot be edited or deleted directly.',
      );
    }
  }

  void _validateRequest(DebitCardSettlementConfirmationRequest request) {
    if (request.normalizedRequestId.isEmpty ||
        request.normalizedSettlementId.isEmpty ||
        request.normalizedTransferTransactionId.isEmpty) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.invalidRequest,
        'Confirmation request identifiers must not be empty.',
      );
    }
  }

  void _validateFinancialContext({
    required DebitCardPendingSettlement settlement,
    required TransactionRecord sourceTransaction,
    required AccountRecord debitCard,
    required AccountRecord linkedBank,
    required CurrencyCode profileCurrency,
  }) {
    if (sourceTransaction.type != TransactionType.expense ||
        sourceTransaction.accountName != debitCard.displayName) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.sourceTransactionNotFound,
        'Settlement source must be an expense posted to the debit-card identity.',
      );
    }
    if (settlement.currency != sourceTransaction.currency ||
        settlement.currency != debitCard.currency ||
        settlement.currency != linkedBank.currency ||
        settlement.currency != profileCurrency) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.currencyMismatch,
        'Settlement, source transaction, profile, and accounts must share one currency.',
      );
    }
    if (settlement.currency.roundAmount(sourceTransaction.amount) !=
        settlement.currency.roundAmount(settlement.amount)) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.amountMismatch,
        'Settlement amount does not match its source expense.',
      );
    }
  }

  Future<DebitCardSettlementConfirmationReceipt?> _resolveReplay(
    DatabaseExecutor db, {
    required DebitCardSettlementConfirmationRequest request,
    required String fingerprint,
  }) async {
    final requestRows = await db.query(
      'debit_card_settlement_confirmation_audits',
      where: 'request_id = ?',
      whereArgs: <Object?>[request.normalizedRequestId],
      limit: 1,
    );
    if (requestRows.isNotEmpty) {
      final audit = DebitCardSettlementConfirmationAuditRecord.fromMap(
        requestRows.single,
      );
      if (audit.payloadFingerprint != fingerprint) {
        throw const DebitCardSettlementConfirmationException(
          DebitCardSettlementConfirmationErrorCode.replayConflict,
          'Request ID was already used with a different confirmation payload.',
        );
      }
      return _loadReplayReceipt(db, audit);
    }

    final settlementRows = await db.query(
      'debit_card_settlement_confirmation_audits',
      where: 'settlement_id = ?',
      whereArgs: <Object?>[request.normalizedSettlementId],
      limit: 1,
    );
    if (settlementRows.isNotEmpty) {
      final audit = DebitCardSettlementConfirmationAuditRecord.fromMap(
        settlementRows.single,
      );
      if (audit.payloadFingerprint == fingerprint &&
          audit.requestId == request.normalizedRequestId) {
        return _loadReplayReceipt(db, audit);
      }
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.settlementConflict,
        'Settlement was already confirmed by another request.',
      );
    }
    return null;
  }

  Future<DebitCardSettlementConfirmationReceipt> _loadReplayReceipt(
    DatabaseExecutor db,
    DebitCardSettlementConfirmationAuditRecord audit,
  ) async {
    final sourceRows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[audit.sourceTransactionId],
      limit: 1,
    );
    final transferRows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[audit.transferTransactionId],
      limit: 1,
    );
    final settlementRows = await db.query(
      'debit_card_settlements',
      where: 'id = ?',
      whereArgs: <Object?>[audit.settlementId],
      limit: 1,
    );
    if (sourceRows.isEmpty || transferRows.isEmpty || settlementRows.isEmpty) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.replayConflict,
        'Confirmation audit exists but its financial rows are incomplete.',
      );
    }
    final settlement = DebitCardPendingSettlement.fromMap(
      settlementRows.single,
    );
    if (settlement.status != DebitCardSettlementStatus.confirmed ||
        settlement.settlementTransferTransactionId !=
            audit.transferTransactionId) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.replayConflict,
        'Confirmation audit and settlement state are inconsistent.',
      );
    }
    return DebitCardSettlementConfirmationReceipt(
      sourceTransaction: TransactionRecord.fromMap(sourceRows.single),
      transferTransaction: TransactionRecord.fromMap(transferRows.single),
      settlement: settlement,
      audit: audit,
      replayed: true,
    );
  }

  Future<void> _assertUnusedTransferIdentity(
    DatabaseExecutor db,
    DebitCardSettlementConfirmationRequest request,
  ) async {
    final transactionRows = await db.query(
      'transactions',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[request.normalizedTransferTransactionId],
      limit: 1,
    );
    final auditRows = await db.query(
      'debit_card_settlement_confirmation_audits',
      columns: const <String>['request_id'],
      where: 'transfer_transaction_id = ?',
      whereArgs: <Object?>[request.normalizedTransferTransactionId],
      limit: 1,
    );
    if (transactionRows.isNotEmpty || auditRows.isNotEmpty) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.transferTransactionConflict,
        'Settlement transfer transaction ID is already in use.',
      );
    }
  }

  Future<DebitCardPendingSettlement> _requireSettlement(
    DatabaseExecutor db,
    String settlementId,
  ) async {
    final rows = await db.query(
      'debit_card_settlements',
      where: 'id = ?',
      whereArgs: <Object?>[settlementId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.settlementNotFound,
        'Settlement does not exist.',
      );
    }
    return DebitCardPendingSettlement.fromMap(rows.single);
  }

  Future<TransactionRecord> _requireSourceTransaction(
    DatabaseExecutor db,
    String transactionId,
  ) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[transactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const DebitCardSettlementConfirmationException(
        DebitCardSettlementConfirmationErrorCode.sourceTransactionNotFound,
        'Source expense transaction does not exist.',
      );
    }
    return TransactionRecord.fromMap(rows.single);
  }

  Future<List<AccountRecord>> _listAccounts(DatabaseExecutor db) async {
    final rows = await db.query('accounts');
    return rows.map(AccountRecord.fromMap).toList(growable: false);
  }

  Future<List<AccountEventRecord>> _listAccountEvents(
    DatabaseExecutor db,
    String accountName,
  ) async {
    final rows = await db.query(
      'account_events',
      where: 'account_name = ?',
      whereArgs: <Object?>[accountName],
      orderBy: 'occurred_at ASC, created_at ASC',
    );
    return rows.map(AccountEventRecord.fromMap).toList(growable: false);
  }

  Future<List<TransactionRecord>> _listAccountTransactions(
    DatabaseExecutor db,
    String accountName,
  ) async {
    final rows = await db.query(
      'transactions',
      where: 'account_name = ? OR from_account_name = ? OR to_account_name = ?',
      whereArgs: <Object?>[accountName, accountName, accountName],
      orderBy: 'occurred_at ASC, created_at ASC',
    );
    return rows.map(TransactionRecord.fromMap).toList(growable: false);
  }

  Future<List<DebitCardPendingSettlement>> _listPendingSettlements(
    DatabaseExecutor db, {
    required String linkedBankAccountId,
    required CurrencyCode currency,
  }) async {
    final rows = await db.query(
      'debit_card_settlements',
      where: 'linked_bank_account_id = ? AND currency_code = ? AND status = ?',
      whereArgs: <Object?>[
        linkedBankAccountId,
        currency.code,
        DebitCardSettlementStatus.pending.name,
      ],
      orderBy: 'expected_settlement_date ASC, authorized_at ASC',
    );
    return rows
        .map(DebitCardPendingSettlement.fromMap)
        .toList(growable: false);
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

  Future<void> _notify(
    DebitCardSettlementConfirmationWriteStage stage,
  ) async {
    await writeStageHook?.call(stage);
  }
}
