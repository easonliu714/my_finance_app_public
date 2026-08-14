import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('createCreditCardInstallmentTables', () {
    test('creates required v12 tables columns and indexes idempotently', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      await createCreditCardInstallmentTables(db);

      expect(await _tableExists(db, 'credit_card_installment_plans'), isTrue);
      expect(await _tableExists(db, 'credit_card_installment_schedule_items'), isTrue);
      expect(await _columnNames(db, 'credit_card_installment_plans'), containsAll(<String>[
        'id',
        'scenario',
        'card_id',
        'principal',
        'term_count',
        'source_transaction_id',
        'source_statement_id',
        'source_type',
        'expense_recognition_mode',
        'principal_accounting_mode',
        'financing_account_id',
        'financing_account_name_snapshot',
        'repayment_account_id',
        'status',
      ]));
      expect(await _columnNames(db, 'credit_card_installment_schedule_items'), containsAll(<String>['id', 'plan_id', 'period_number', 'principal', 'fee', 'total_payment', 'generated_transaction_id', 'status']));
      expect(await _indexNames(db), containsAll(<String>[
        'idx_installment_plans_card_status',
        'idx_installment_plans_source_transaction',
        'idx_installment_plans_source_statement',
        'idx_installment_plans_source_type_status',
        'idx_installment_plans_financing_account_status',
        'idx_installment_plans_repayment_account_status',
        'idx_installment_schedule_plan_period_unique',
        'idx_installment_schedule_plan_status',
      ]));
    });

    test('v12 upgrade creates missing installment tables before adding columns', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await upgradeCreditCardInstallmentTablesToV12(db);
      await upgradeCreditCardInstallmentTablesToV12(db);

      expect(await _tableExists(db, 'credit_card_installment_plans'), isTrue);
      expect(await _tableExists(db, 'credit_card_installment_schedule_items'), isTrue);
      expect(await _columnNames(db, 'credit_card_installment_plans'), containsAll(<String>[
        'source_type',
        'expense_recognition_mode',
        'principal_accounting_mode',
        'financing_account_id',
        'financing_account_name_snapshot',
        'repayment_account_id',
      ]));
      expect(await _indexNames(db), containsAll(<String>[
        'idx_installment_plans_card_status',
        'idx_installment_schedule_plan_period_unique',
      ]));
    });

    test('enforces unique schedule period per plan only', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      await _insertPlan(db, id: 'plan-1');
      await _insertPlan(db, id: 'plan-2');
      await _insertScheduleItem(db, id: 'plan-1-1', planId: 'plan-1', periodNumber: 1);

      expect(() => _insertScheduleItem(db, id: 'duplicate', planId: 'plan-1', periodNumber: 1), throwsA(isA<DatabaseException>()));
      await _insertScheduleItem(db, id: 'plan-2-1', planId: 'plan-2', periodNumber: 1);
      expect(await db.query('credit_card_installment_schedule_items'), hasLength(2));
    });

    test('supports card status source and BNPL account lookup queries', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      await _insertPlan(db, id: 'active-card-1', cardId: 'card-1', status: 'active', sourceTransactionId: 'tx-1');
      await _insertPlan(db, id: 'cancelled-card-1', cardId: 'card-1', status: 'cancelled');
      await _insertPlan(db, id: 'active-card-2', cardId: 'card-2', status: 'active');
      await _insertPlan(db, id: 'post-statement', scenario: 'postStatementSpecifiedAmount', cardId: 'card-3', sourceStatementId: 'statement-1');
      await _insertPlan(db, id: 'manual-bnpl', cardId: 'bnpl-card', sourceType: 'manual_bnpl', principalAccountingMode: 'finance_liability', financingAccountId: 'finance-1', repaymentAccountId: 'bank-1');

      final activeCardOne = await db.query('credit_card_installment_plans', where: 'card_id = ? AND status = ?', whereArgs: <Object?>['card-1', 'active']);
      final sourceTransaction = await db.query('credit_card_installment_plans', where: 'source_transaction_id = ? AND status = ?', whereArgs: <Object?>['tx-1', 'active']);
      final sourceStatement = await db.query('credit_card_installment_plans', where: 'source_statement_id = ? AND status = ?', whereArgs: <Object?>['statement-1', 'active']);
      final manualBnpl = await db.query('credit_card_installment_plans', where: 'source_type = ? AND financing_account_id = ?', whereArgs: <Object?>['manual_bnpl', 'finance-1']);

      expect(activeCardOne.map((row) => row['id']), ['active-card-1']);
      expect(sourceTransaction.map((row) => row['id']), ['active-card-1']);
      expect(sourceStatement.map((row) => row['id']), ['post-statement']);
      expect(manualBnpl.map((row) => row['id']), ['manual-bnpl']);
    });

    test('upgrades v11 table to v12 and backfills source fields', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createLegacyV11InstallmentTables(db);
      await _insertLegacyV11Plan(db, id: 'purchase', sourceTransactionId: 'tx-1');
      await _insertLegacyV11Plan(db, id: 'statement', scenario: 'postStatementSpecifiedAmount', sourceStatementId: 'statement-1');
      await _insertLegacyV11Plan(db, id: 'manual');

      await upgradeCreditCardInstallmentTablesToV12(db);
      await upgradeCreditCardInstallmentTablesToV12(db);

      expect(await _columnNames(db, 'credit_card_installment_plans'), containsAll(<String>['source_type', 'expense_recognition_mode', 'principal_accounting_mode', 'financing_account_id', 'repayment_account_id']));
      final rows = await db.query('credit_card_installment_plans', orderBy: 'id ASC');
      final byId = {for (final row in rows) row['id'] as String: row};
      expect(byId['purchase']?['source_type'], 'purchase_transaction');
      expect(byId['purchase']?['expense_recognition_mode'], 'immediate');
      expect(byId['purchase']?['principal_accounting_mode'], 'defer_card_charge');
      expect(byId['statement']?['source_type'], 'statement_balance');
      expect(byId['statement']?['expense_recognition_mode'], 'per_period');
      expect(byId['statement']?['principal_accounting_mode'], 'offset_statement_balance');
      expect(byId['manual']?['source_type'], 'manual_bnpl');
      expect(byId['manual']?['principal_accounting_mode'], 'finance_liability');
    });

    test('does not affect existing core tables', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
      await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY, amount REAL NOT NULL)');
      await db.execute('CREATE TABLE credit_card_statement_events (id TEXT PRIMARY KEY, card_id TEXT NOT NULL)');
      await db.insert('accounts', <String, Object?>{'id': 'account-1', 'name': 'Account'});
      await db.insert('transactions', <String, Object?>{'id': 'tx-1', 'amount': 100});
      await db.insert('credit_card_statement_events', <String, Object?>{'id': 'statement-1', 'card_id': 'card-1'});

      await createCreditCardInstallmentTables(db);
      expect(await db.query('accounts'), hasLength(1));
      expect(await db.query('transactions'), hasLength(1));
      expect(await db.query('credit_card_statement_events'), hasLength(1));
      await db.insert('accounts', <String, Object?>{'id': 'account-2', 'name': 'Second'});
      expect(await db.query('accounts'), hasLength(2));
    });
  });
}

Future<bool> _tableExists(Database db, String tableName) async => (await db.query('sqlite_master', where: 'type = ? AND name = ?', whereArgs: <Object?>['table', tableName])).isNotEmpty;

Future<Set<String>> _columnNames(Database db, String tableName) async => (await db.rawQuery('PRAGMA table_info($tableName)')).map((row) => row['name'] as String).toSet();

Future<Set<String>> _indexNames(Database db) async => (await db.query('sqlite_master', where: 'type = ?', whereArgs: <Object?>['index'])).map((row) => row['name'] as String).toSet();

Future<void> _insertPlan(Database db, {required String id, String scenario = 'purchaseTime', String cardId = 'card-1', String status = 'active', String? sourceTransactionId, String? sourceStatementId, String sourceType = 'purchase_transaction', String expenseRecognitionMode = 'immediate', String principalAccountingMode = 'defer_card_charge', String? financingAccountId, String? repaymentAccountId}) {
  return db.insert('credit_card_installment_plans', <String, Object?>{
    'id': id,
    'scenario': scenario,
    'card_id': cardId,
    'card_name_snapshot': 'Test Card',
    'currency_code': 'TWD',
    'principal': 12000,
    'term_count': 6,
    'first_statement_date': '2026-07-05',
    'fee_mode': 'totalFee',
    'total_fee': 0,
    'annual_rate': 0,
    'remainder_policy': 'firstPeriod',
    'original_unpaid_balance': 0,
    'source_transaction_id': sourceTransactionId,
    'source_statement_id': sourceStatementId,
    'source_type': sourceType,
    'expense_recognition_mode': expenseRecognitionMode,
    'principal_accounting_mode': principalAccountingMode,
    'financing_account_id': financingAccountId,
    'financing_account_name_snapshot': financingAccountId == null ? '' : 'Finance Account',
    'repayment_account_id': repaymentAccountId,
    'status': status,
    'note': '',
  });
}

Future<void> _insertScheduleItem(Database db, {required String id, required String planId, required int periodNumber}) {
  return db.insert('credit_card_installment_schedule_items', <String, Object?>{
    'id': id,
    'plan_id': planId,
    'period_number': periodNumber,
    'statement_date': '2026-07-05',
    'principal': 2000,
    'fee': 0,
    'total_payment': 2000,
    'remaining_principal_after_payment': 10000,
    'revolving_exposure_offset': 0,
    'revolving_exposure_after_offset': 0,
    'status': 'pending',
  });
}

Future<void> _createLegacyV11InstallmentTables(Database db) async {
  await db.execute('''
    CREATE TABLE credit_card_installment_plans (
      id TEXT PRIMARY KEY,
      scenario TEXT NOT NULL,
      card_id TEXT NOT NULL,
      card_name_snapshot TEXT NOT NULL,
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      principal REAL NOT NULL,
      term_count INTEGER NOT NULL,
      first_statement_date TEXT NOT NULL,
      fee_mode TEXT NOT NULL,
      total_fee REAL NOT NULL DEFAULT 0,
      annual_rate REAL NOT NULL DEFAULT 0,
      remainder_policy TEXT NOT NULL,
      original_unpaid_balance REAL NOT NULL DEFAULT 0,
      source_transaction_id TEXT,
      source_statement_id TEXT,
      status TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

Future<void> _insertLegacyV11Plan(Database db, {required String id, String scenario = 'purchaseTime', String? sourceTransactionId, String? sourceStatementId}) {
  return db.insert('credit_card_installment_plans', <String, Object?>{
    'id': id,
    'scenario': scenario,
    'card_id': 'card-1',
    'card_name_snapshot': 'Test Card',
    'currency_code': 'TWD',
    'principal': 12000,
    'term_count': 6,
    'first_statement_date': '2026-07-05',
    'fee_mode': 'totalFee',
    'total_fee': 0,
    'annual_rate': 0,
    'remainder_policy': 'firstPeriod',
    'original_unpaid_balance': 0,
    'source_transaction_id': sourceTransactionId,
    'source_statement_id': sourceStatementId,
    'status': 'active',
    'note': '',
  });
}
