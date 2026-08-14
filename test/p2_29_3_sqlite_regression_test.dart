import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('P2.29.3 SQLite regression', () {
    test('clean install creates installment schema idempotently', () async {
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
        'source_transaction_id',
        'source_statement_id',
        'source_type',
        'expense_recognition_mode',
        'principal_accounting_mode',
        'financing_account_id',
        'repayment_account_id',
        'status',
      ]));
      expect(await _columnNames(db, 'credit_card_installment_schedule_items'), containsAll(<String>[
        'id',
        'plan_id',
        'period_number',
        'statement_date',
        'principal',
        'fee',
        'total_payment',
        'remaining_principal_after_payment',
        'status',
      ]));
      expect(await _indexNames(db), containsAll(<String>[
        'idx_installment_plans_card_status',
        'idx_installment_plans_source_transaction',
        'idx_installment_plans_source_statement',
        'idx_installment_plans_source_type_status',
        'idx_installment_schedule_plan_period_unique',
        'idx_installment_schedule_plan_status',
      ]));
    });

    test('v11 upgrade preserves existing Phase 2 core tables and data', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await _createPhase2CoreTables(db);
      await _createLegacyV11InstallmentTable(db);
      await _insertCoreRows(db);
      await _insertLegacyInstallmentRows(db);

      await upgradeCreditCardInstallmentTablesToV12(db);
      await upgradeCreditCardInstallmentTablesToV12(db);

      expect(await db.query('transactions'), hasLength(1));
      expect(await db.query('accounts'), hasLength(1));
      expect(await db.query('account_events'), hasLength(1));
      expect(await db.query('credit_card_statement_events'), hasLength(1));
      expect(await db.query('credit_card_bank_rule_profiles'), hasLength(1));
      expect(await db.query('credit_card_bank_rule_assignments'), hasLength(1));

      final plans = await db.query('credit_card_installment_plans', orderBy: 'id ASC');
      final byId = {for (final plan in plans) plan['id'] as String: plan};
      expect(byId['manual-bnpl']?['source_type'], 'manual_bnpl');
      expect(byId['manual-bnpl']?['principal_accounting_mode'], 'finance_liability');
      expect(byId['purchase']?['source_type'], 'purchase_transaction');
      expect(byId['purchase']?['expense_recognition_mode'], 'immediate');
      expect(byId['statement']?['source_type'], 'statement_balance');
      expect(byId['statement']?['expense_recognition_mode'], 'per_period');
      expect(byId['statement']?['principal_accounting_mode'], 'offset_statement_balance');
    });
  });
}

Future<void> _createPhase2CoreTables(Database db) async {
  await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY, amount REAL NOT NULL, note TEXT NOT NULL DEFAULT "")');
  await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, suffix TEXT NOT NULL DEFAULT "")');
  await db.execute('CREATE TABLE account_events (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, amount REAL NOT NULL)');
  await db.execute('CREATE TABLE credit_card_statement_events (id TEXT PRIMARY KEY, card_id TEXT NOT NULL, total_balance REAL NOT NULL DEFAULT 0)');
  await db.execute('CREATE TABLE credit_card_bank_rule_profiles (id TEXT PRIMARY KEY, name TEXT NOT NULL, annual_interest_rate REAL NOT NULL DEFAULT 0)');
  await db.execute('CREATE TABLE credit_card_bank_rule_assignments (card_id TEXT PRIMARY KEY, profile_id TEXT)');
}

Future<void> _insertCoreRows(Database db) async {
  await db.insert('transactions', <String, Object?>{'id': 'tx-1', 'amount': 1000, 'note': 'core transaction'});
  await db.insert('accounts', <String, Object?>{'id': 'card-1', 'name': '信用卡', 'suffix': ''});
  await db.insert('account_events', <String, Object?>{'id': 'event-1', 'account_id': 'card-1', 'amount': 0});
  await db.insert('credit_card_statement_events', <String, Object?>{'id': 'statement-1', 'card_id': 'card-1', 'total_balance': 12000});
  await db.insert('credit_card_bank_rule_profiles', <String, Object?>{'id': 'rule-1', 'name': 'Default', 'annual_interest_rate': 15});
  await db.insert('credit_card_bank_rule_assignments', <String, Object?>{'card_id': 'card-1', 'profile_id': 'rule-1'});
}

Future<void> _createLegacyV11InstallmentTable(Database db) async {
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

Future<void> _insertLegacyInstallmentRows(Database db) async {
  await _insertLegacyPlan(db, id: 'manual-bnpl');
  await _insertLegacyPlan(db, id: 'purchase', sourceTransactionId: 'tx-1');
  await _insertLegacyPlan(db, id: 'statement', scenario: 'postStatementSpecifiedAmount', sourceStatementId: 'statement-1');
}

Future<void> _insertLegacyPlan(
  Database db, {
  required String id,
  String scenario = 'purchaseTime',
  String? sourceTransactionId,
  String? sourceStatementId,
}) {
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

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.query('sqlite_master', where: 'type = ? AND name = ?', whereArgs: <Object?>['table', tableName]);
  return rows.isNotEmpty;
}

Future<Set<String>> _columnNames(Database db, String tableName) async {
  return (await db.rawQuery('PRAGMA table_info($tableName)')).map((row) => row['name'] as String).toSet();
}

Future<Set<String>> _indexNames(Database db) async {
  return (await db.query('sqlite_master', where: 'type = ?', whereArgs: <Object?>['index'])).map((row) => row['name'] as String).toSet();
}
