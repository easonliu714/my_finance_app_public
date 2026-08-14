import 'package:sqflite/sqflite.dart';

Future<void> createDebitCardSettlementConfirmationAuditTable(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS debit_card_settlement_confirmation_audits (
      request_id TEXT PRIMARY KEY,
      payload_fingerprint TEXT NOT NULL,
      settlement_id TEXT NOT NULL UNIQUE,
      source_transaction_id TEXT NOT NULL,
      transfer_transaction_id TEXT NOT NULL UNIQUE,
      debit_card_account_id TEXT NOT NULL,
      linked_bank_account_id TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      ledger_balance_before REAL NOT NULL,
      reserved_before REAL NOT NULL,
      available_before REAL NOT NULL,
      ledger_balance_after REAL NOT NULL,
      reserved_after REAL NOT NULL,
      available_after REAL NOT NULL,
      confirmed_at TEXT NOT NULL,
      status_before TEXT NOT NULL,
      status_after TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (length(trim(request_id)) > 0),
      CHECK (length(payload_fingerprint) = 64),
      CHECK (amount > 0),
      CHECK (debit_card_account_id <> linked_bank_account_id),
      CHECK (status_before = 'pending'),
      CHECK (status_after = 'confirmed'),
      FOREIGN KEY (settlement_id)
        REFERENCES debit_card_settlements(id) ON DELETE RESTRICT,
      FOREIGN KEY (source_transaction_id)
        REFERENCES transactions(id) ON DELETE RESTRICT,
      FOREIGN KEY (transfer_transaction_id)
        REFERENCES transactions(id) ON DELETE RESTRICT,
      FOREIGN KEY (debit_card_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (linked_bank_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_confirmation_audits_bank_time
    ON debit_card_settlement_confirmation_audits(
      linked_bank_account_id,
      confirmed_at DESC
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_confirmation_audits_card_time
    ON debit_card_settlement_confirmation_audits(
      debit_card_account_id,
      confirmed_at DESC
    )
  ''');
}
