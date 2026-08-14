import 'package:sqflite/sqflite.dart';

const walletTopUpExecutionNoUpdateTrigger =
    'trg_wallet_top_up_executions_no_update';
const walletTopUpExecutionNoDeleteTrigger =
    'trg_wallet_top_up_executions_no_delete';

Future<void> createWalletTopUpExecutionTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS wallet_top_up_executions (
      id TEXT PRIMARY KEY,
      source_transaction_id TEXT NOT NULL UNIQUE,
      profile_id TEXT NOT NULL,
      evaluation_identity TEXT NOT NULL DEFAULT '',
      generated_transfer_transaction_id TEXT UNIQUE,
      target_account_id TEXT NOT NULL,
      funding_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      balance_after_expense REAL NOT NULL,
      funding_balance_before_top_up REAL NOT NULL,
      threshold_amount REAL NOT NULL,
      top_up_amount REAL NOT NULL DEFAULT 0,
      outcome TEXT NOT NULL,
      reason_code TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (target_account_id <> funding_account_id),
      CHECK (threshold_amount >= 0),
      CHECK (top_up_amount >= 0),
      CHECK (outcome IN ('posted', 'notNeeded', 'cooldownSuppressed', 'fundingInsufficient')),
      CHECK ((outcome = 'posted' AND generated_transfer_transaction_id IS NOT NULL AND top_up_amount > 0) OR (outcome <> 'posted' AND generated_transfer_transaction_id IS NULL)),
      FOREIGN KEY (source_transaction_id) REFERENCES transactions(id) ON DELETE RESTRICT,
      FOREIGN KEY (generated_transfer_transaction_id) REFERENCES transactions(id) ON DELETE RESTRICT,
      FOREIGN KEY (profile_id) REFERENCES wallet_top_up_profiles(id) ON DELETE RESTRICT,
      FOREIGN KEY (target_account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (funding_account_id) REFERENCES accounts(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_wallet_top_up_executions_profile_time ON wallet_top_up_executions(profile_id, created_at DESC)');
  await createWalletTopUpExecutionImmutabilityTriggers(db);
}

Future<void> createWalletTopUpExecutionImmutabilityTriggers(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS $walletTopUpExecutionNoUpdateTrigger
    BEFORE UPDATE ON wallet_top_up_executions
    BEGIN
      SELECT RAISE(ABORT, 'wallet_top_up_executions are immutable');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS $walletTopUpExecutionNoDeleteTrigger
    BEFORE DELETE ON wallet_top_up_executions
    BEGIN
      SELECT RAISE(ABORT, 'wallet_top_up_executions are immutable');
    END
  ''');
}

Future<void> dropWalletTopUpExecutionImmutabilityTriggers(
  DatabaseExecutor db,
) async {
  await db.execute('DROP TRIGGER IF EXISTS $walletTopUpExecutionNoUpdateTrigger');
  await db.execute('DROP TRIGGER IF EXISTS $walletTopUpExecutionNoDeleteTrigger');
}
