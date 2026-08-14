import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../account/account_record.dart';
import '../account/stored_value_auto_top_up_service.dart';
import '../account/wallet_top_up_execution.dart';
import 'transaction_record.dart';
import 'transaction_repository.dart';
import 'transaction_store.dart';
import 'transaction_type.dart';

class AutoTopUpTransactionStore implements TransactionStore {
  AutoTopUpTransactionStore._();

  static final AutoTopUpTransactionStore instance =
      AutoTopUpTransactionStore._();

  final TransactionRepository _base = TransactionRepository.instance;

  Future<Database> get _database =>
      ProductionDatabaseCoordinator.instance.database;

  @override
  Future<void> insert(TransactionRecord record) async {
    final db = await _database;
    if (await _isDebitCardExpense(db, record)) {
      await _base.insert(record);
      return;
    }
    await StoredValueAutoTopUpService(db).insertSourceTransaction(record);
  }

  @override
  Future<void> update(TransactionRecord record) async {
    await _requireMutable(record.id);
    await _base.update(record);
  }

  @override
  Future<void> deleteById(String id) async {
    await _requireMutable(id);
    await _base.deleteById(id);
  }

  @override
  Future<void> deleteByRepaymentGroupId(String repaymentGroupId) {
    return _base.deleteByRepaymentGroupId(repaymentGroupId);
  }

  @override
  Future<void> deleteLoanRepaymentCluster(TransactionRecord record) {
    return _base.deleteLoanRepaymentCluster(record);
  }

  @override
  Future<List<TransactionRecord>> listRecent({int limit = 50}) {
    return _base.listRecent(limit: limit);
  }

  @override
  Future<double> monthlyIncome(DateTime month) {
    return _base.monthlyIncome(month);
  }

  @override
  Future<double> monthlyExpense(DateTime month) {
    return _base.monthlyExpense(month);
  }

  Future<void> _requireMutable(String transactionId) async {
    final db = await _database;
    if (!await _tableExists(db, 'wallet_top_up_executions')) return;
    final normalizedId = transactionId.trim();
    final rows = await db.query(
      'wallet_top_up_executions',
      columns: const <String>['source_transaction_id'],
      where:
          'source_transaction_id = ? OR generated_transfer_transaction_id = ?',
      whereArgs: <Object?>[normalizedId, normalizedId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const WalletTopUpExecutionMutationBlocked(
        'Rule-generated stored-value source and transfer transactions cannot be edited or deleted directly.',
      );
    }
  }

  Future<bool> _isDebitCardExpense(
    DatabaseExecutor db,
    TransactionRecord record,
  ) async {
    if (record.type != TransactionType.expense ||
        !await _tableExists(db, 'accounts')) {
      return false;
    }
    final rows = await db.query(
      'accounts',
      where: 'type = ?',
      whereArgs: <Object?>[AccountType.debitCard.name],
    );
    for (final row in rows) {
      final account = AccountRecord.fromMap(row);
      if (account.displayName == record.accountName.trim()) return true;
    }
    return false;
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
