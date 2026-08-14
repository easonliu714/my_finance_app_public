import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v21.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/stored_value_auto_top_up_service.dart';
import 'package:my_finance_app/features/account/wallet_top_up_execution.dart';
import 'package:my_finance_app/features/account/wallet_top_up_persistence.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation.dart';
import 'package:my_finance_app/features/account/wallet_top_up_repository.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh Schema V21 creates immutable execution ledger', () async {
    final db = await _openDatabase();
    addTearDown(db.close);

    expect(canonicalProductionSchemaVersion, 21);
    final names = await _schemaObjects(db);
    expect(
      names,
      containsAll(<String>{
        'wallet_top_up_executions',
        'trg_wallet_top_up_executions_no_update',
        'trg_wallet_top_up_executions_no_delete',
      }),
    );
  });

  test('balance 99 below 100 atomically posts fixed 500 transfer', () async {
    final db = await _openDatabase(walletBalance: 600, fundingBalance: 2000);
    addTearDown(db.close);
    await _saveFixedProfile(db);
    final service = StoredValueAutoTopUpService(
      db,
      clock: () => DateTime.utc(2026, 7, 4, 13),
    );

    final result = await service.insertSourceTransaction(
      _expense(id: 'expense-99', amount: 501),
    );

    expect(result.sourceInserted, isTrue);
    expect(result.replayed, isFalse);
    expect(result.posted, isTrue);
    expect(result.execution?.balanceAfterExpense, 99);
    expect(result.execution?.threshold, 100);
    expect(result.execution?.topUpAmount, 500);
    expect(result.execution?.fundingAccountId, _funding.id);

    final transactions = await db.query(
      'transactions',
      orderBy: 'occurred_at ASC',
    );
    expect(transactions, hasLength(2));
    final transfer = TransactionRecord.fromMap(transactions.last);
    expect(transfer.type, TransactionType.transfer);
    expect(transfer.amount, 500);
    expect(transfer.fromAccountName, _funding.displayName);
    expect(transfer.toAccountName, _wallet.displayName);
    expect(transfer.tagName, '低餘額規則');
  });

  test('balance exactly 100 records not-needed and creates no transfer',
      () async {
    final db = await _openDatabase(walletBalance: 600, fundingBalance: 2000);
    addTearDown(db.close);
    await _saveFixedProfile(db);
    final service = StoredValueAutoTopUpService(
      db,
      clock: () => DateTime.utc(2026, 7, 4, 13),
    );

    final result = await service.insertSourceTransaction(
      _expense(id: 'expense-100', amount: 500),
    );

    expect(result.posted, isFalse);
    expect(
      result.execution?.outcome,
      WalletTopUpExecutionOutcome.notNeeded,
    );
    expect(result.execution?.balanceAfterExpense, 100);
    expect(await _count(db, 'transactions'), 1);
  });

  test('source replay is idempotent and does not duplicate transfer', () async {
    final db = await _openDatabase(walletBalance: 600, fundingBalance: 2000);
    addTearDown(db.close);
    await _saveFixedProfile(db);
    final service = StoredValueAutoTopUpService(
      db,
      clock: () => DateTime.utc(2026, 7, 4, 13),
    );
    final source = _expense(id: 'expense-replay', amount: 501);

    final first = await service.insertSourceTransaction(source);
    final replay = await service.insertSourceTransaction(source);

    expect(first.posted, isTrue);
    expect(replay.replayed, isTrue);
    expect(replay.execution?.id, first.execution?.id);
    expect(await _count(db, 'transactions'), 2);
    expect(await _count(db, 'wallet_top_up_executions'), 1);
  });

  test('insufficient linked funding fails closed without partial transfer',
      () async {
    final db = await _openDatabase(walletBalance: 600, fundingBalance: 300);
    addTearDown(db.close);
    await _saveFixedProfile(db);
    final service = StoredValueAutoTopUpService(
      db,
      clock: () => DateTime.utc(2026, 7, 4, 13),
    );

    final result = await service.insertSourceTransaction(
      _expense(id: 'expense-insufficient', amount: 501),
    );

    expect(result.posted, isFalse);
    expect(
      result.execution?.outcome,
      WalletTopUpExecutionOutcome.fundingInsufficient,
    );
    expect(result.execution?.topUpAmount, 500);
    expect(result.execution?.fundingBalanceBeforeTopUp, 300);
    expect(await _count(db, 'transactions'), 1);
  });

  test('execution ledger is append-only', () async {
    final db = await _openDatabase(walletBalance: 600, fundingBalance: 2000);
    addTearDown(db.close);
    await _saveFixedProfile(db);
    final service = StoredValueAutoTopUpService(
      db,
      clock: () => DateTime.utc(2026, 7, 4, 13),
    );
    final result = await service.insertSourceTransaction(
      _expense(id: 'expense-immutable', amount: 501),
    );

    await expectLater(
      db.update(
        'wallet_top_up_executions',
        <String, Object?>{'reason_code': 'changed'},
        where: 'id = ?',
        whereArgs: <Object?>[result.execution!.id],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'wallet_top_up_executions',
        where: 'id = ?',
        whereArgs: <Object?>[result.execution!.id],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('execution insert failure rolls back source and generated transfer',
      () async {
    final db = await _openDatabase(walletBalance: 600, fundingBalance: 2000);
    addTearDown(db.close);
    await _saveFixedProfile(db);
    await db.execute('''
      CREATE TRIGGER fail_wallet_top_up_execution
      BEFORE INSERT ON wallet_top_up_executions
      BEGIN
        SELECT RAISE(ABORT, 'injected execution failure');
      END
    ''');
    final service = StoredValueAutoTopUpService(
      db,
      clock: () => DateTime.utc(2026, 7, 4, 13),
    );

    await expectLater(
      service.insertSourceTransaction(
        _expense(id: 'expense-rollback', amount: 501),
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await _count(db, 'transactions'), 0);
    expect(await _count(db, 'wallet_top_up_executions'), 0);
  });
}

const _wallet = AccountRecord(
  id: 'stored-value-1',
  name: '交通儲值卡',
  type: AccountType.storedValue,
  initialBalance: 0,
  sortOrder: 10,
);

const _funding = AccountRecord(
  id: 'bank-1',
  name: '連結銀行帳戶',
  type: AccountType.bank,
  initialBalance: 0,
  sortOrder: 20,
);

Future<Database> _openDatabase({
  double walletBalance = 0,
  double fundingBalance = 0,
}) async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
    onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
  );
  await _createCoreTables(db);
  await createCanonicalProductionV21Tables(db);
  await db.insert('accounts', _wallet.toMap());
  await db.insert('accounts', _funding.toMap());
  await db.insert(
    'account_events',
    _initialEvent(_wallet, walletBalance).toMap(),
  );
  await db.insert(
    'account_events',
    _initialEvent(_funding, fundingBalance).toMap(),
  );
  return db;
}

Future<void> _saveFixedProfile(Database db) async {
  final now = DateTime.utc(2026, 7, 4, 12);
  await WalletTopUpRepository(db).upsertProfile(
    StoredWalletTopUpProfile(
      id: 'profile-fixed-500',
      targetAccountId: _wallet.id,
      fundingAccountId: _funding.id,
      currency: CurrencyCode.twd,
      threshold: 100,
      amountMode: WalletTopUpAmountMode.fixedAmount,
      targetBalance: 0,
      fixedAmount: 500,
      cooldown: Duration.zero,
      isEnabled: true,
      createdAt: now,
      updatedAt: now,
    ),
    now: now,
  );
}

AccountEventRecord _initialEvent(AccountRecord account, double amount) {
  return AccountEventRecord(
    id: '${account.id}-initial',
    accountId: account.id,
    accountName: account.displayName,
    eventType: 'initial_balance',
    amount: amount,
    currency: account.currency,
    exchangeRateToBase: account.currency.defaultRateToTwd,
    occurredAt: DateTime.utc(2026, 1, 1),
    note: 'test opening balance',
  );
}

TransactionRecord _expense({required String id, required double amount}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    category: '交通',
    occurredAt: DateTime.utc(2026, 7, 4, 12, 30),
    accountName: _wallet.displayName,
    memberName: '自己',
    merchantName: '交通扣款',
    tagName: '消費',
    note: '',
  );
}

Future<void> _createCoreTables(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      suffix TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      credit_limit REAL NOT NULL DEFAULT 0,
      statement_day INTEGER NOT NULL DEFAULT 1,
      payment_due_day INTEGER NOT NULL DEFAULT 1,
      payment_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_principal REAL NOT NULL DEFAULT 0,
      annual_interest_rate REAL NOT NULL DEFAULT 0,
      loan_term_months INTEGER NOT NULL DEFAULT 0,
      loan_repayment_method TEXT NOT NULL DEFAULT 'equalPrincipalAndInterest',
      loan_payment_due_day INTEGER NOT NULL DEFAULT 1,
      loan_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      loan_reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_start_date TEXT,
      loan_disbursement_account_name TEXT NOT NULL DEFAULT '',
      loan_handling_fee REAL NOT NULL DEFAULT 0,
      loan_disbursement_created INTEGER NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      account_name TEXT NOT NULL,
      member_name TEXT NOT NULL,
      merchant_name TEXT NOT NULL,
      tag_name TEXT NOT NULL,
      note TEXT NOT NULL,
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      exchange_rate_to_base REAL NOT NULL DEFAULT 1,
      base_amount REAL NOT NULL DEFAULT 0,
      from_account_name TEXT,
      to_account_name TEXT,
      repayment_group_id TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE account_events (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      account_name TEXT NOT NULL,
      event_type TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      exchange_rate_to_base REAL NOT NULL DEFAULT 1,
      base_amount REAL NOT NULL DEFAULT 0,
      occurred_at TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT ''
    )
  ''');
}

Future<Set<String>> _schemaObjects(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']).whereType<String>().toSet();
}

Future<int> _count(Database db, String tableName) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
  return (rows.single['c'] as num).toInt();
}
