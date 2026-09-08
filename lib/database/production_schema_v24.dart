import 'package:sqflite/sqflite.dart';

import 'production_schema_v23.dart' show createCanonicalProductionV23Tables;

const int canonicalProductionSchemaVersion = 24;

/// Complete FIA public-row detail is replaceable Registry cache only.
/// Transactions and user-owned merchant history never duplicate these fields.
Future<void> createCanonicalProductionV24Tables(DatabaseExecutor db) async {
  await createCanonicalProductionV23Tables(db);
  await upgradeBusinessRegistryOfficialDetailsToV24(db);
}

Future<void> upgradeBusinessRegistryOfficialDetailsToV24(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_registry_official_details (
      snapshot_version TEXT NOT NULL,
      jurisdiction TEXT NOT NULL DEFAULT 'TW',
      seller_identifier TEXT NOT NULL,
      official_json TEXT NOT NULL,
      PRIMARY KEY (snapshot_version, jurisdiction, seller_identifier),
      CHECK (length(seller_identifier) = 8),
      CHECK (seller_identifier NOT GLOB '*[^0-9]*'),
      FOREIGN KEY (snapshot_version)
        REFERENCES business_registry_snapshots(version) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_business_registry_official_detail_lookup '
    'ON business_registry_official_details('
    'jurisdiction, seller_identifier, snapshot_version)',
  );
}
