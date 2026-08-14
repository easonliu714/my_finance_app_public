import 'package:sqflite/sqflite.dart';

import 'production_schema_v17.dart';

const int canonicalProductionSchemaVersion = 18;

Future<void> createCanonicalProductionV18Tables(
  DatabaseExecutor db,
) async {
  await createCanonicalProductionV17Tables(db);
  await _createDebitCardAuthorizationAuditsTable(db);
}

Future<void> _createDebitCardAuthorizationAuditsTable(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS debit_card_authorization_audits (
      request_id TEXT PRIMARY KEY,
      payload_fingerprint TEXT NOT NULL,
      transaction_id TEXT NOT NULL UNIQUE,
      settlement_id TEXT NOT NULL UNIQUE,
      debit_card_account_id TEXT NOT NULL,
      linked_bank_account_id TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      ledger_balance_before REAL NOT NULL,
      reserved_before REAL NOT NULL,
      available_before REAL NOT NULL,
      available_after REAL NOT NULL,
      authorized_at TEXT NOT NULL,
      expected_settlement_date TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (length(trim(request_id)) > 0),
      CHECK (length(payload_fingerprint) = 64),
      CHECK (amount > 0),
      CHECK (debit_card_account_id <> linked_bank_account_id),
      FOREIGN KEY (transaction_id)
        REFERENCES transactions(id) ON DELETE RESTRICT,
      FOREIGN KEY (settlement_id)
        REFERENCES debit_card_settlements(id) ON DELETE RESTRICT,
      FOREIGN KEY (debit_card_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (linked_bank_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_authorization_audits_card_time
    ON debit_card_authorization_audits(
      debit_card_account_id,
      authorized_at DESC
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_authorization_audits_bank_time
    ON debit_card_authorization_audits(
      linked_bank_account_id,
      authorized_at DESC
    )
  ''');
}
