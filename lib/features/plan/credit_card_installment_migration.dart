import 'package:sqflite/sqflite.dart';

Future<void> createCreditCardInstallmentTables(DatabaseExecutor db) async {
  await _createCreditCardInstallmentPlansTable(db);
  await _createCreditCardInstallmentScheduleTable(db);
  await upgradeCreditCardInstallmentTablesToV12(db);
}

Future<void> upgradeCreditCardInstallmentTablesToV12(DatabaseExecutor db) async {
  await _createCreditCardInstallmentPlansTable(db);
  await _createCreditCardInstallmentScheduleTable(db);
  await _ensureCreditCardInstallmentPlanColumn(db, 'source_type', "TEXT NOT NULL DEFAULT 'purchase_transaction'");
  await _ensureCreditCardInstallmentPlanColumn(db, 'expense_recognition_mode', "TEXT NOT NULL DEFAULT 'immediate'");
  await _ensureCreditCardInstallmentPlanColumn(db, 'principal_accounting_mode', "TEXT NOT NULL DEFAULT 'defer_card_charge'");
  await _ensureCreditCardInstallmentPlanColumn(db, 'financing_account_id', 'TEXT');
  await _ensureCreditCardInstallmentPlanColumn(db, 'financing_account_name_snapshot', "TEXT NOT NULL DEFAULT ''");
  await _ensureCreditCardInstallmentPlanColumn(db, 'repayment_account_id', 'TEXT');

  await _backfillInstallmentSourceFields(db);
  await _createCreditCardInstallmentIndexes(db);
}

Future<void> _createCreditCardInstallmentPlansTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS credit_card_installment_plans (
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
      source_type TEXT NOT NULL DEFAULT 'purchase_transaction',
      expense_recognition_mode TEXT NOT NULL DEFAULT 'immediate',
      principal_accounting_mode TEXT NOT NULL DEFAULT 'defer_card_charge',
      financing_account_id TEXT,
      financing_account_name_snapshot TEXT NOT NULL DEFAULT '',
      repayment_account_id TEXT,
      status TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

Future<void> _createCreditCardInstallmentScheduleTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS credit_card_installment_schedule_items (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL,
      period_number INTEGER NOT NULL,
      statement_date TEXT NOT NULL,
      principal REAL NOT NULL,
      fee REAL NOT NULL DEFAULT 0,
      total_payment REAL NOT NULL,
      remaining_principal_after_payment REAL NOT NULL DEFAULT 0,
      revolving_exposure_offset REAL NOT NULL DEFAULT 0,
      revolving_exposure_after_offset REAL NOT NULL DEFAULT 0,
      generated_transaction_id TEXT,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

Future<void> _createCreditCardInstallmentIndexes(DatabaseExecutor db) async {
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_plans_card_status
    ON credit_card_installment_plans(card_id, status, created_at DESC)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_plans_source_transaction
    ON credit_card_installment_plans(source_transaction_id, status)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_plans_source_statement
    ON credit_card_installment_plans(source_statement_id, status)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_plans_source_type_status
    ON credit_card_installment_plans(source_type, status, created_at DESC)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_plans_financing_account_status
    ON credit_card_installment_plans(financing_account_id, status, created_at DESC)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_plans_repayment_account_status
    ON credit_card_installment_plans(repayment_account_id, status, created_at DESC)
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_installment_schedule_plan_period_unique
    ON credit_card_installment_schedule_items(plan_id, period_number)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_installment_schedule_plan_status
    ON credit_card_installment_schedule_items(plan_id, status, statement_date)
  ''');
}

Future<void> _ensureCreditCardInstallmentPlanColumn(DatabaseExecutor db, String columnName, String columnDefinition) async {
  final rows = await db.rawQuery('PRAGMA table_info(credit_card_installment_plans)');
  if (rows.any((row) => row['name'] == columnName)) return;
  await db.execute('ALTER TABLE credit_card_installment_plans ADD COLUMN $columnName $columnDefinition');
}

Future<void> _backfillInstallmentSourceFields(DatabaseExecutor db) async {
  await db.execute('''
    UPDATE credit_card_installment_plans
    SET
      source_type = 'statement_balance',
      expense_recognition_mode = 'per_period',
      principal_accounting_mode = 'offset_statement_balance'
    WHERE source_statement_id IS NOT NULL
       OR scenario = 'postStatementSpecifiedAmount'
  ''');
  await db.execute('''
    UPDATE credit_card_installment_plans
    SET
      source_type = 'purchase_transaction',
      expense_recognition_mode = 'immediate',
      principal_accounting_mode = 'defer_card_charge'
    WHERE (source_statement_id IS NULL OR source_statement_id = '')
      AND scenario != 'postStatementSpecifiedAmount'
      AND source_transaction_id IS NOT NULL
      AND source_transaction_id != ''
  ''');
  await db.execute('''
    UPDATE credit_card_installment_plans
    SET
      source_type = 'manual_bnpl',
      expense_recognition_mode = 'immediate',
      principal_accounting_mode = 'finance_liability'
    WHERE (source_statement_id IS NULL OR source_statement_id = '')
      AND scenario != 'postStatementSpecifiedAmount'
      AND (source_transaction_id IS NULL OR source_transaction_id = '')
  ''');
}
