import 'package:sqflite/sqflite.dart';

import '../account/account_event_record.dart';
import '../account/account_ledger_calculator.dart';
import '../account/account_record.dart';
import '../account/debit_card_account_profile.dart';
import '../account/debit_card_repository.dart';
import 'debit_card_purchase_authorization.dart';
import 'debit_card_settlement.dart';
import 'transaction_record.dart';
import 'transaction_type.dart';

enum DebitCardAuthorizationWriteStage {
  beforeTransactionInsert,
  afterTransactionInsert,
  afterSettlementInsert,
  afterAuditInsert,
}

typedef DebitCardAuthorizationWriteStageHook = Future<void> Function(
  DebitCardAuthorizationWriteStage stage,
);

class DebitCardPurchaseAuthorizationService {
  const DebitCardPurchaseAuthorizationService({
    required this.databaseProvider,
    this.ledgerCalculator = const AccountLedgerCalculator(),
    this.writeStageHook,
  });

  final Future<Database> Function() databaseProvider;
  final AccountLedgerCalculator ledgerCalculator;
  final DebitCardAuthorizationWriteStageHook? writeStageHook;

  Future<DebitCardPurchaseAuthorizationReceipt> authorize(
    DebitCardPurchaseAuthorizationRequest request,
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

      await _assertUnusedIdentifiers(txn, request);

      final accounts = await _listAccounts(txn);
      final debitCard = _findAccount(
        accounts,
        request.normalizedDebitCardAccountId,
      );
      if (debitCard == null) {
        throw DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.debitCardAccountNotFound,
          'Debit-card account ${request.normalizedDebitCardAccountId} does not exist.',
        );
      }
      if (debitCard.isArchived) {
        throw const DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.debitCardAccountArchived,
          'Archived debit-card accounts cannot authorize new purchases.',
        );
      }
      if (debitCard.type != AccountType.debitCard) {
        throw const DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.wrongAccountType,
          'Authorization owner must be a debit-card account.',
        );
      }

      final profile = await DebitCardRepository(txn).getProfile(debitCard.id);
      if (profile == null) {
        throw const DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.profileNotFound,
          'Debit-card profile does not exist.',
        );
      }
      if (!profile.isEnabled) {
        throw const DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.profileDisabled,
          'Debit-card profile is disabled.',
        );
      }

      final linkedBank = _findAccount(accounts, profile.linkedBankAccountId);
      if (linkedBank == null) {
        throw DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.linkedBankAccountNotFound,
          'Linked bank account ${profile.linkedBankAccountId} does not exist.',
        );
      }
      if (linkedBank.isArchived) {
        throw const DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.linkedBankAccountArchived,
          'Archived linked bank accounts cannot fund new purchases.',
        );
      }
      if (linkedBank.type != AccountType.bank) {
        throw const DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode.linkedBankAccountInvalid,
          'The debit-card link must target a bank account.',
        );
      }

      _validateFinancialContext(
        request: request,
        debitCard: debitCard,
        profile: profile,
        linkedBank: linkedBank,
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

      final ledgerBalance = ledgerCalculator.currentBalance(
        account: linkedBank,
        accounts: accounts,
        events: bankEvents,
        transactions: bankTransactions,
      );
      final businessCalendar =
          await DebitCardRepository(txn).loadBusinessCalendar();
      final planner = DebitCardSettlementPlanner(
        businessCalendar: businessCalendar,
      );
      final reservedBefore = planner.reservedAmount(
        settlements: pendingSettlements,
        linkedBankAccountId: linkedBank.id,
        currency: linkedBank.currency,
      );
      final availableBefore = planner.availableBalance(
        currentBankBalance: ledgerBalance,
        settlements: pendingSettlements,
        linkedBankAccountId: linkedBank.id,
        currency: linkedBank.currency,
      );
      final amount = request.transaction.currency.roundAmount(
        request.transaction.amount,
      );
      if (amount > availableBefore) {
        throw DebitCardPurchaseAuthorizationException(
          DebitCardPurchaseAuthorizationErrorCode
              .insufficientAvailableBalance,
          'Requested $amount ${request.transaction.currency.code}, but only '
          '$availableBefore ${request.transaction.currency.code} is available.',
          availableBalance: availableBefore,
          requestedAmount: amount,
        );
      }

      final settlement = planner.authorize(
        id: request.normalizedSettlementId,
        debitCardAccountId: debitCard.id,
        linkedBankAccountId: linkedBank.id,
        transactionId: request.transaction.id.trim(),
        amount: amount,
        currency: request.transaction.currency,
        authorizedAt: request.requestedAt,
        currentBankBalance: ledgerBalance,
        existingSettlements: pendingSettlements,
        settlementBusinessDays: profile.settlementBusinessDays,
      );
      final availableAfter = linkedBank.currency.roundAmount(
        availableBefore - amount,
      );
      final audit = DebitCardAuthorizationAuditRecord(
        requestId: request.normalizedRequestId,
        payloadFingerprint: fingerprint,
        transactionId: request.transaction.id.trim(),
        settlementId: settlement.id,
        debitCardAccountId: debitCard.id,
        linkedBankAccountId: linkedBank.id,
        amount: amount,
        currency: request.transaction.currency,
        ledgerBalanceBefore: ledgerBalance,
        reservedBefore: reservedBefore,
        availableBefore: availableBefore,
        availableAfter: availableAfter,
        authorizedAt: settlement.authorizedAt,
        expectedSettlementDate: settlement.expectedSettlementDate,
      );

      await _notify(DebitCardAuthorizationWriteStage.beforeTransactionInsert);
      await txn.insert(
        'transactions',
        request.transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _notify(DebitCardAuthorizationWriteStage.afterTransactionInsert);
      await txn.insert(
        'debit_card_settlements',
        settlement.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _notify(DebitCardAuthorizationWriteStage.afterSettlementInsert);
      await txn.insert(
        'debit_card_authorization_audits',
        audit.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _notify(DebitCardAuthorizationWriteStage.afterAuditInsert);

      return DebitCardPurchaseAuthorizationReceipt(
        transaction: request.transaction,
        settlement: settlement,
        audit: audit,
      );
    });
  }

  Future<bool> isAuthorizedTransaction(String transactionId) async {
    final normalizedId = transactionId.trim();
    if (normalizedId.isEmpty) return false;
    final db = await databaseProvider();
    final rows = await db.query(
      'debit_card_authorization_audits',
      columns: const <String>['transaction_id'],
      where: 'transaction_id = ?',
      whereArgs: <Object?>[normalizedId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> requireMutableTransaction(String transactionId) async {
    if (await isAuthorizedTransaction(transactionId)) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode
            .authorizedTransactionImmutable,
        'Authorized debit-card purchases cannot be edited or deleted directly.',
      );
    }
  }

  void _validateRequest(DebitCardPurchaseAuthorizationRequest request) {
    final transaction = request.transaction;
    final amount = transaction.currency.roundAmount(transaction.amount);
    if (request.normalizedRequestId.isEmpty ||
        request.normalizedSettlementId.isEmpty ||
        request.normalizedDebitCardAccountId.isEmpty ||
        transaction.id.trim().isEmpty ||
        transaction.type != TransactionType.expense ||
        !amount.isFinite ||
        amount <= 0 ||
        !transaction.exchangeRateToBase.isFinite ||
        transaction.exchangeRateToBase <= 0) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.invalidRequest,
        'Authorization request is incomplete or contains invalid financial values.',
      );
    }
  }

  void _validateFinancialContext({
    required DebitCardPurchaseAuthorizationRequest request,
    required AccountRecord debitCard,
    required DebitCardAccountProfile profile,
    required AccountRecord linkedBank,
  }) {
    final transaction = request.transaction;
    if (transaction.accountName.trim() != debitCard.displayName) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.invalidRequest,
        'Expense account does not match the debit-card account identity.',
      );
    }
    if (transaction.currency != debitCard.currency ||
        profile.currency != debitCard.currency ||
        linkedBank.currency != debitCard.currency) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.currencyMismatch,
        'Debit-card, linked-bank, profile, and transaction currencies must match.',
      );
    }
  }

  Future<DebitCardPurchaseAuthorizationReceipt?> _resolveReplay(
    DatabaseExecutor db, {
    required DebitCardPurchaseAuthorizationRequest request,
    required String fingerprint,
  }) async {
    final rows = await db.query(
      'debit_card_authorization_audits',
      where: 'request_id = ?',
      whereArgs: <Object?>[request.normalizedRequestId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final audit = DebitCardAuthorizationAuditRecord.fromMap(rows.single);
    if (audit.payloadFingerprint != fingerprint) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.replayConflict,
        'The request ID was already used with a different payload.',
      );
    }

    final transactionRows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[audit.transactionId],
      limit: 1,
    );
    final settlementRows = await db.query(
      'debit_card_settlements',
      where: 'id = ?',
      whereArgs: <Object?>[audit.settlementId],
      limit: 1,
    );
    if (transactionRows.isEmpty || settlementRows.isEmpty) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.replayConflict,
        'The authorization audit exists but its financial rows are incomplete.',
      );
    }

    return DebitCardPurchaseAuthorizationReceipt(
      transaction: TransactionRecord.fromMap(transactionRows.single),
      settlement: DebitCardPendingSettlement.fromMap(settlementRows.single),
      audit: audit,
      replayed: true,
    );
  }

  Future<void> _assertUnusedIdentifiers(
    DatabaseExecutor db,
    DebitCardPurchaseAuthorizationRequest request,
  ) async {
    final transactionRows = await db.query(
      'transactions',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[request.transaction.id.trim()],
      limit: 1,
    );
    if (transactionRows.isNotEmpty) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.transactionIdConflict,
        'The transaction ID is already in use.',
      );
    }

    final settlementRows = await db.query(
      'debit_card_settlements',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[request.normalizedSettlementId],
      limit: 1,
    );
    if (settlementRows.isNotEmpty) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.settlementIdConflict,
        'The settlement ID is already in use.',
      );
    }

    final auditIdentifierRows = await db.query(
      'debit_card_authorization_audits',
      columns: const <String>['request_id'],
      where: 'transaction_id = ? OR settlement_id = ?',
      whereArgs: <Object?>[
        request.transaction.id.trim(),
        request.normalizedSettlementId,
      ],
      limit: 1,
    );
    if (auditIdentifierRows.isNotEmpty) {
      throw const DebitCardPurchaseAuthorizationException(
        DebitCardPurchaseAuthorizationErrorCode.replayConflict,
        'Authorization identifiers are already linked to another request.',
      );
    }
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

  Future<void> _notify(DebitCardAuthorizationWriteStage stage) async {
    await writeStageHook?.call(stage);
  }
}
