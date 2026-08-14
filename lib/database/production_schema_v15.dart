import 'package:sqflite/sqflite.dart';

import 'production_schema_v14.dart';

const int canonicalProductionSchemaVersion = 15;

Future<void> createCanonicalProductionV15Tables(
  DatabaseExecutor db,
) async {
  await createCanonicalProductionV14Tables(db);
  await _ensureColumn(
    db,
    table: 'cloud_invoice_drafts',
    column: 'currency_source',
    definition: "TEXT NOT NULL DEFAULT 'unknown'",
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS cloud_invoice_detail_enrichments (
      invoice_number TEXT PRIMARY KEY,
      selector_profile_version INTEGER NOT NULL,
      fetched_at TEXT NOT NULL,
      exact_timestamp TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      official_status TEXT,
      seller_identifier TEXT,
      seller_name TEXT,
      expected_total REAL NOT NULL,
      detail_total REAL NOT NULL,
      invoice_identity_matches INTEGER NOT NULL,
      detail_total_internally_consistent INTEGER NOT NULL,
      detail_total_matches_csv INTEGER NOT NULL,
      seller_identifier_consistent INTEGER NOT NULL,
      line_items_json TEXT NOT NULL,
      payload_version INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_detail_enrichments_fetched '
    'ON cloud_invoice_detail_enrichments(fetched_at DESC)',
  );
}

Future<void> _ensureColumn(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String definition,
}) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  final exists = rows.any((row) => row['name'] == column);
  if (!exists) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
