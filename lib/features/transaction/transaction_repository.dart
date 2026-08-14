import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../account/account_record.dart';
import 'debit_card_purchase_authorization.dart';
import 'debit_card_purchase_authorization_service.dart';
import 'debit_card_settlement_confirmation.dart';
import 'transaction_record.dart';
import 'transaction_store.dart';
import 'transaction_type.dart';

class TransactionRepository implements TransactionStore {
  TransactionRepository._();

  static final TransactionRepository instance = TransactionRepository._();

  /// Uses the canonical shared production connection.
  ///
  /// This repository must not independently create, version, or upgrade
  /// `my_finance_app.db`.
  Future<Database> get database =>
      ProductionDatabaseCoordinator.instance.database;

  Future<void> _ensureTransactionCurrencyColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = columns.map((column) => column['name']).toSet();
    if (!names.contains('currency_code')) {
      await db.execute(
        "ALTER TABLE transactions ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'TWD'",
      );
    }
    if (!names.contains('exchange_rate_to_base')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN exchange_rate_to_base REAL NOT NULL DEFAULT 1',
      );
    }
    if (!names.contains('base_amount')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN base_amount REAL NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _ensureRepaymentGroupColumn(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = columns.map((column) => column['name']).toSet();
    if (!names.contains('repayment_group_id')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN repayment_group_id TEXT',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_repayment_group '
      'ON transactions(repayment_group_id)',
    );
  }

  @override
  Future<void> insert(TransactionRecord record) async {
    final db = await database;
    await _ensureTransactionCurrencyColumns(db);
    await _ensureRepaymentGroupColumn(db);

    final debitCard = await _findDebitCardExpenseAccount(db, record);
    if (debitCard != null) {
      final service = DebitCardPurchaseAuthorizationService(
        databaseProvider: () async => db,
      );
      await service.authorize(
        DebitCardPurchaseAuthorizationRequest(
          requestId: 'debit-purchase:${record.id}',
          settlementId: 'debit-settlement:${record.id}',
          debitCardAccountId: debitCard.id,
          transaction: record,
          requestedAt: DateTime.now().toUtc(),
        ),
      );
      return;
    }

    await db.insert(
      'transactions',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> update(TransactionRecord record) async {
    final db = await database;
    await _ensureTransactionCurrencyColumns(db);
    await _ensureRepaymentGroupColumn(db);
    await _requireMutableTransaction(db, record.id);
    await db.update(
      'transactions',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  @override
  Future<void> deleteById(String id) async {
    final db = await database;
    await _requireMutableTransaction(db, id);
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId) async {
    final db = await database;
    await _ensureRepaymentGroupColumn(db);
    await db.delete(
      'transactions',
      where: 'repayment_group_id = ?',
      whereArgs: [repaymentGroupId],
    );
  }

  @override
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record) async {
    final db = await database;
    await _ensureRepaymentGroupColumn(db);
    final groupId = record.repaymentGroupId?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      await db.delete(
        'transactions',
        where: 'repayment_group_id = ?',
        whereArgs: [groupId],
      );
      return;
    }
    final period = _periodFromNote(record.note);
    if (period == null) {
      await _requireMutableTransaction(db, record.id);
      await db.delete('transactions', where: 'id = ?', whereArgs: [record.id]);
      return;
    }
    final occurredStart = DateTime(
      record.occurredAt.year,
      record.occurredAt.month,
      record.occurredAt.day,
    ).toIso8601String();
    final occurredEnd = DateTime(
      record.occurredAt.year,
      record.occurredAt.month,
      record.occurredAt.day + 1,
    ).toIso8601String();
    final likePeriod = '%第 $period 期%';
    await db.delete(
      'transactions',
      where: '''
        occurred_at >= ? AND occurred_at < ?
        AND tag_name = ?
        AND note LIKE ?
        AND (
          (type = ? AND category = ?)
          OR (type = ? AND category = ?)
        )
      ''',
      whereArgs: [
        occurredStart,
        occurredEnd,
        '還款',
        likePeriod,
        TransactionType.loan.name,
        '還本',
        TransactionType.expense.name,
        '利息支出',
      ],
    );
  }

  @override
  Future<List<TransactionRecord>> listRecent({int limit = 50}) async {
    final db = await database;
    await _ensureTransactionCurrencyColumns(db);
    await _ensureRepaymentGroupColumn(db);
    final rows = await db.query(
      'transactions',
      orderBy: 'occurred_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<double> monthlyIncome(DateTime month) async =>
      _monthlySum(month, 'income');

  @override
  Future<double> monthlyExpense(DateTime month) async =>
      _monthlySum(month, 'expense');

  Future<double> _monthlySum(DateTime month, String type) async {
    final db = await database;
    await _ensureTransactionCurrencyColumns(db);
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(
        SUM(CASE WHEN base_amount = 0 THEN amount ELSE base_amount END),
        0
      ) AS total
      FROM transactions
      WHERE type = ? AND occurred_at >= ? AND occurred_at < ?
      ''',
      [type, start.toIso8601String(), end.toIso8601String()],
    );
    return (rows.first['total'] as num).toDouble();
  }

  Future<AccountRecord?> _findDebitCardExpenseAccount(
    DatabaseExecutor db,
    TransactionRecord record,
  ) async {
    if (record.type != TransactionType.expense ||
        !await _tableExists(db, 'accounts')) {
      return null;
    }
    final rows = await db.query(
      'accounts',
      where: 'type = ?',
      whereArgs: <Object?>[AccountType.debitCard.name],
    );
    for (final row in rows) {
      final account = AccountRecord.fromMap(row);
      if (account.displayName == record.accountName.trim()) return account;
    }
    return null;
  }

  Future<void> _requireMutableTransaction(
    DatabaseExecutor db,
    String transactionId,
  ) async {
    final normalizedId = transactionId.trim();
    if (await _tableExists(db, 'debit_card_authorization_audits')) {
      final rows = await db.query(
        'debit_card_authorization_audits',
        columns: const <String>['transaction_id'],
        where: 'transaction_id = ?',
        whereArgs: <Object?>[normalizedId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        throw const DebitCardPurchaseAuthorizationException(
DebitCardPurchaseAuthorizationErrorCode
    .authorizedTransactionImmutable,
'Authorized debit-card purchases cannot be edited or deleted directly.',
        );
      }
    }
    if (await _tableExists(
      db,
      'debit_card_settlement_confirmation_audits',
    )) {
      final rows = await db.query(
        'debit_card_settlement_confirmation_audits',
        columns: const <String>['transfer_transaction_id'],
        where: 'transfer_transaction_id = ?',
        whereArgs: <Object?>[normalizedId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        throw const DebitCardSettlementConfirmationException(
DebitCardSettlementConfirmationErrorCode.confirmedTransferImmutable,
'Confirmed debit-card settlement transfers cannot be edited or deleted directly.',
        );
      }
    }
  }

  Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}

int? _periodFromNote(String note) {
  final match = RegExp(r'第\s*(\d+)\s*期').firstMatch(note);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}
