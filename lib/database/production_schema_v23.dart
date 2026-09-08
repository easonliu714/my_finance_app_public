import 'package:sqflite/sqflite.dart';

import 'production_schema_v22.dart' show createCanonicalProductionV22Tables;

const int canonicalProductionSchemaVersion = 23;

/// Expands only the replaceable official-registry cache taxonomy.
/// User-owned merchant identity tables remain unchanged.
Future<void> createCanonicalProductionV23Tables(DatabaseExecutor db) async {
  await createCanonicalProductionV22Tables(db);
  await upgradeBusinessRegistryEntityTypeToV23(db);
}

Future<void> upgradeBusinessRegistryEntityTypeToV23(
  DatabaseExecutor db,
) async {
  var rows = await db.rawQuery(
    "SELECT sql FROM sqlite_master "
    "WHERE type = 'table' AND name = 'business_registry_entities'",
  );
  if (rows.isEmpty) {
    await createCanonicalProductionV22Tables(db);
    rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master "
      "WHERE type = 'table' AND name = 'business_registry_entities'",
    );
  }
  final currentSql =
      rows.isEmpty ? '' : rows.first['sql']?.toString() ?? '';
  if (currentSql.contains("'unknown'")) {
    await _ensureBusinessRegistryV23Index(db);
    return;
  }

  await db.execute(
    'DROP INDEX IF EXISTS idx_business_registry_seller_lookup',
  );
  await db.execute(
    'ALTER TABLE business_registry_entities '
    'RENAME TO business_registry_entities_v22',
  );
  await _createBusinessRegistryEntitiesV23(db);
  await db.execute('''
    INSERT INTO business_registry_entities (
      snapshot_version, jurisdiction, seller_identifier, entity_type,
      legal_name, registration_status, parent_seller_identifier, source_dataset
    )
    SELECT
      snapshot_version, jurisdiction, seller_identifier, entity_type,
      legal_name, registration_status, parent_seller_identifier, source_dataset
    FROM business_registry_entities_v22
  ''');
  await db.execute('DROP TABLE business_registry_entities_v22');
  await _ensureBusinessRegistryV23Index(db);
}

Future<void> _createBusinessRegistryEntitiesV23(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_registry_entities (
      snapshot_version TEXT NOT NULL,
      jurisdiction TEXT NOT NULL DEFAULT 'TW',
      seller_identifier TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      legal_name TEXT NOT NULL,
      registration_status TEXT NOT NULL DEFAULT '',
      parent_seller_identifier TEXT NOT NULL DEFAULT '',
      source_dataset TEXT NOT NULL,
      PRIMARY KEY (snapshot_version, jurisdiction, seller_identifier, entity_type),
      CHECK (length(seller_identifier) = 8),
      CHECK (seller_identifier NOT GLOB '*[^0-9]*'),
      CHECK (entity_type IN ('company', 'business', 'branch', 'unknown')),
      FOREIGN KEY (snapshot_version)
        REFERENCES business_registry_snapshots(version) ON DELETE CASCADE
    )
  ''');
}

Future<void> _ensureBusinessRegistryV23Index(DatabaseExecutor db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_business_registry_seller_lookup '
    'ON business_registry_entities('
    'jurisdiction, seller_identifier, snapshot_version)',
  );
}
