import 'package:sqflite/sqflite.dart';

const String walletTopUpAuditNoUpdateTrigger =
    'trg_wallet_top_up_audits_no_update';
const String walletTopUpAuditNoDeleteTrigger =
    'trg_wallet_top_up_audits_no_delete';

Future<void> createWalletTopUpPersistenceTables(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS wallet_top_up_profiles (
      id TEXT PRIMARY KEY,
      target_account_id TEXT NOT NULL UNIQUE,
      funding_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      threshold_amount REAL NOT NULL,
      amount_mode TEXT NOT NULL,
      target_balance_amount REAL NOT NULL DEFAULT 0,
      fixed_amount REAL NOT NULL DEFAULT 0,
      cooldown_seconds INTEGER NOT NULL DEFAULT 0,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (length(trim(id)) > 0),
      CHECK (target_account_id <> funding_account_id),
      CHECK (threshold_amount >= 0),
      CHECK (amount_mode IN ('targetBalance', 'fixedAmount')),
      CHECK (target_balance_amount >= 0),
      CHECK (fixed_amount >= 0),
      CHECK (
        (amount_mode = 'targetBalance' AND
          target_balance_amount > threshold_amount AND fixed_amount = 0)
        OR
        (amount_mode = 'fixedAmount' AND
          fixed_amount > 0 AND target_balance_amount = 0)
      ),
      CHECK (cooldown_seconds >= 0),
      CHECK (is_enabled IN (0, 1)),
      FOREIGN KEY (target_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (funding_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_wallet_top_up_profiles_funding_enabled
    ON wallet_top_up_profiles(funding_account_id, is_enabled)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS wallet_top_up_suggestions (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      target_account_id TEXT NOT NULL,
      funding_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      amount_mode TEXT NOT NULL,
      current_available_balance REAL NOT NULL,
      funding_available_balance REAL NOT NULL,
      threshold_amount REAL NOT NULL,
      suggested_amount REAL NOT NULL,
      funding_shortfall REAL NOT NULL DEFAULT 0,
      funding_sufficient INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      evaluated_at TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (length(trim(id)) > 0),
      CHECK (amount_mode IN ('targetBalance', 'fixedAmount')),
      CHECK (target_account_id <> funding_account_id),
      CHECK (threshold_amount >= 0),
      CHECK (suggested_amount > 0),
      CHECK (funding_shortfall >= 0),
      CHECK (funding_sufficient IN (0, 1)),
      CHECK (status IN ('pending', 'dismissed', 'superseded')),
      FOREIGN KEY (profile_id)
        REFERENCES wallet_top_up_profiles(id) ON DELETE RESTRICT,
      FOREIGN KEY (target_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (funding_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_wallet_top_up_suggestions_profile_status_time
    ON wallet_top_up_suggestions(profile_id, status, evaluated_at DESC)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS wallet_top_up_audits (
      id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      profile_id TEXT NOT NULL,
      suggestion_id TEXT,
      details_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (length(trim(id)) > 0),
      CHECK (
        event_type IN (
          'profileCreated',
          'profileUpdated',
          'profileEnabled',
          'profileDisabled',
          'suggestionCreated',
          'suggestionDismissed',
          'suggestionSuperseded'
        )
      ),
      FOREIGN KEY (profile_id)
        REFERENCES wallet_top_up_profiles(id) ON DELETE RESTRICT,
      FOREIGN KEY (suggestion_id)
        REFERENCES wallet_top_up_suggestions(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_wallet_top_up_audits_profile_time
    ON wallet_top_up_audits(profile_id, created_at DESC)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_wallet_top_up_audits_suggestion_time
    ON wallet_top_up_audits(suggestion_id, created_at DESC)
  ''');
  await createWalletTopUpAuditImmutabilityTriggers(db);
}

Future<void> createWalletTopUpAuditImmutabilityTriggers(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS $walletTopUpAuditNoUpdateTrigger
    BEFORE UPDATE ON wallet_top_up_audits
    BEGIN
      SELECT RAISE(ABORT, 'wallet_top_up_audits are immutable');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS $walletTopUpAuditNoDeleteTrigger
    BEFORE DELETE ON wallet_top_up_audits
    BEGIN
      SELECT RAISE(ABORT, 'wallet_top_up_audits are immutable');
    END
  ''');
}

Future<void> dropWalletTopUpAuditImmutabilityTriggers(
  DatabaseExecutor db,
) async {
  await db.execute('DROP TRIGGER IF EXISTS $walletTopUpAuditNoUpdateTrigger');
  await db.execute('DROP TRIGGER IF EXISTS $walletTopUpAuditNoDeleteTrigger');
}
