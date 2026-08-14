import 'package:sqflite/sqflite.dart';

const int canonicalProductionSchemaVersion = 13;

Future<void> createCanonicalProductionV13Tables(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      alias TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_name_alias_unique '
    'ON merchants(name, alias)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchants_visible_sort '
    'ON merchants(is_archived, name, alias, id)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS production_migration_markers (
      marker_key TEXT PRIMARY KEY,
      status TEXT NOT NULL,
      source_path TEXT,
      source_row_count INTEGER NOT NULL DEFAULT 0,
      copied_row_count INTEGER NOT NULL DEFAULT 0,
      skipped_row_count INTEGER NOT NULL DEFAULT 0,
      details TEXT NOT NULL DEFAULT '',
      started_at TEXT NOT NULL,
      completed_at TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_production_migration_markers_status '
    'ON production_migration_markers(status, completed_at)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_drafts (
      id TEXT PRIMARY KEY,
      operation_key TEXT NOT NULL UNIQUE,
      candidate_reference TEXT NOT NULL,
      account_id TEXT NOT NULL,
      account_name TEXT NOT NULL,
      amount REAL NOT NULL,
      invoice_date TEXT NOT NULL,
      time_precision TEXT NOT NULL,
      time_source TEXT NOT NULL,
      currency_code TEXT,
      merchant_id TEXT,
      invoice_number TEXT NOT NULL DEFAULT '',
      seller_identifier TEXT NOT NULL DEFAULT '',
      seller_name TEXT NOT NULL DEFAULT '',
      tax_amount REAL,
      line_items_json TEXT NOT NULL DEFAULT '[]',
      payload_version INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_drafts_candidate '
    'ON cloud_invoice_drafts(candidate_reference, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_drafts_account '
    'ON cloud_invoice_drafts(account_id, created_at DESC)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_metadata_links (
      id TEXT PRIMARY KEY,
      operation_key TEXT NOT NULL UNIQUE,
      transaction_id TEXT NOT NULL,
      candidate_reference TEXT NOT NULL,
      invoice_number TEXT NOT NULL DEFAULT '',
      seller_identifier TEXT NOT NULL DEFAULT '',
      seller_name TEXT NOT NULL DEFAULT '',
      invoice_date TEXT NOT NULL,
      time_precision TEXT NOT NULL,
      time_source TEXT NOT NULL,
      currency_code TEXT,
      currency_source TEXT NOT NULL,
      tax_amount REAL,
      merchant_id TEXT,
      line_items_json TEXT NOT NULL DEFAULT '[]',
      payload_version INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_metadata_transaction '
    'ON cloud_invoice_metadata_links(transaction_id, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_metadata_candidate '
    'ON cloud_invoice_metadata_links(candidate_reference, created_at DESC)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_operations (
      operation_key TEXT PRIMARY KEY,
      request_fingerprint TEXT NOT NULL,
      action TEXT NOT NULL,
      status TEXT NOT NULL,
      candidate_reference TEXT NOT NULL,
      transaction_id TEXT,
      account_id TEXT,
      merchant_id TEXT,
      draft_id TEXT,
      rollback_token TEXT UNIQUE,
      failure_message TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_operations_status '
    'ON cloud_invoice_operations(status, updated_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_operations_candidate '
    'ON cloud_invoice_operations(candidate_reference, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_operations_transaction '
    'ON cloud_invoice_operations(transaction_id, created_at DESC)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_before_images (
      rollback_token TEXT PRIMARY KEY,
      operation_key TEXT NOT NULL UNIQUE,
      transaction_fingerprint TEXT NOT NULL,
      transaction_json TEXT NOT NULL,
      payload_version INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_before_images_created '
    'ON cloud_invoice_before_images(created_at DESC)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_audits (
      id TEXT PRIMARY KEY,
      operation_key TEXT NOT NULL,
      action TEXT NOT NULL,
      status TEXT NOT NULL,
      candidate_reference TEXT NOT NULL,
      transaction_id TEXT,
      account_id TEXT,
      merchant_id TEXT,
      rollback_token TEXT,
      message TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_audits_operation '
    'ON cloud_invoice_audits(operation_key, created_at ASC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_audits_candidate '
    'ON cloud_invoice_audits(candidate_reference, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_audits_status '
    'ON cloud_invoice_audits(status, created_at DESC)',
  );
}
