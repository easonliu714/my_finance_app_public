import 'package:sqflite/sqflite.dart';

import 'production_schema_v13.dart';

const int canonicalProductionSchemaVersion = 14;

Future<void> createCanonicalProductionV14Tables(
  DatabaseExecutor db,
) async {
  await createCanonicalProductionV13Tables(db);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_draft_promotions (
      draft_id TEXT PRIMARY KEY,
      promotion_key TEXT NOT NULL UNIQUE,
      draft_operation_key TEXT NOT NULL,
      draft_fingerprint TEXT NOT NULL,
      transaction_id TEXT NOT NULL UNIQUE,
      category TEXT NOT NULL,
      member_name TEXT NOT NULL,
      tag_name TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_draft_promotions_transaction '
    'ON cloud_invoice_draft_promotions(transaction_id, created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_draft_promotions_operation '
    'ON cloud_invoice_draft_promotions(draft_operation_key, created_at DESC)',
  );
}
