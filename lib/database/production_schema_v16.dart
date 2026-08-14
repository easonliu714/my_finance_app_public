import 'package:sqflite/sqflite.dart';

import 'production_schema_v15.dart';

const int canonicalProductionSchemaVersion = 16;

Future<void> createCanonicalProductionV16Tables(
  DatabaseExecutor db,
) async {
  await createCanonicalProductionV15Tables(db);
  await _ensureColumn(
    db,
    table: 'cloud_invoice_drafts',
    column: 'account_resolution_status',
    definition: "TEXT NOT NULL DEFAULT 'selected'",
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cloud_invoice_drafts_account_resolution '
    'ON cloud_invoice_drafts(account_resolution_status, created_at DESC)',
  );
}

Future<void> _ensureColumn(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String definition,
}) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  if (!rows.any((row) => row['name'] == column)) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
