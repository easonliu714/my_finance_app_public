import 'package:sqflite/sqflite.dart';

const String merchantIdentityObservationNoUpdateTrigger =
    'trg_merchant_identity_observations_no_update';
const String merchantIdentityObservationNoDeleteTrigger =
    'trg_merchant_identity_observations_no_delete';

/// P4.20.0-A candidate schema only.
///
/// This function is intentionally not wired into [AccountRepository] yet. It
/// provides an executable migration contract for the merchant-identity and
/// replaceable official-registry model before production schemaVersion is
/// advanced. Runtime installation is a separate gate.
Future<void> createMerchantIdentityV22CandidateTables(
  DatabaseExecutor db,
) async {
  await _ensureLegacyMerchantSellerIdentifierColumn(db);

  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_brands (
      id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      display_override TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_brands_visible '
    'ON merchant_brands(is_archived, display_name, id)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_brand_aliases (
      id TEXT PRIMARY KEY,
      merchant_brand_id TEXT NOT NULL,
      literal_alias TEXT NOT NULL,
      normalized_alias TEXT NOT NULL,
      source TEXT NOT NULL,
      valid_from TEXT,
      valid_to TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (merchant_brand_id) REFERENCES merchant_brands(id) ON DELETE CASCADE,
      UNIQUE (merchant_brand_id, normalized_alias)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_brand_alias_lookup '
    'ON merchant_brand_aliases(normalized_alias, merchant_brand_id)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_legal_entities (
      id TEXT PRIMARY KEY,
      jurisdiction TEXT NOT NULL DEFAULT 'TW',
      seller_identifier TEXT NOT NULL,
      legal_name TEXT NOT NULL DEFAULT '',
      entity_type TEXT NOT NULL DEFAULT 'unknown',
      registration_status TEXT NOT NULL DEFAULT '',
      registry_source TEXT NOT NULL DEFAULT '',
      registry_version TEXT NOT NULL DEFAULT '',
      first_observed_at TEXT NOT NULL,
      last_observed_at TEXT NOT NULL,
      CHECK (length(seller_identifier) = 8),
      CHECK (seller_identifier NOT GLOB '*[^0-9]*'),
      CHECK (entity_type IN ('company', 'business', 'branch', 'unknown')),
      UNIQUE (jurisdiction, seller_identifier)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_legal_entities_name '
    'ON merchant_legal_entities(legal_name, seller_identifier)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_branches_or_outlets (
      id TEXT PRIMARY KEY,
      legal_entity_id TEXT,
      outlet_label TEXT NOT NULL DEFAULT '',
      official_branch_identifier TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '',
      valid_from TEXT,
      valid_to TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (legal_entity_id) REFERENCES merchant_legal_entities(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_outlets_legal_entity '
    'ON merchant_branches_or_outlets(legal_entity_id, outlet_label, id)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_brand_legal_links (
      id TEXT PRIMARY KEY,
      merchant_brand_id TEXT NOT NULL,
      legal_entity_id TEXT NOT NULL,
      branch_or_outlet_id TEXT,
      decision TEXT NOT NULL,
      evidence_source TEXT NOT NULL,
      effective_from TEXT,
      effective_to TEXT,
      created_at TEXT NOT NULL,
      CHECK (decision IN ('proposed', 'confirmed', 'rejected')),
      FOREIGN KEY (merchant_brand_id) REFERENCES merchant_brands(id) ON DELETE RESTRICT,
      FOREIGN KEY (legal_entity_id) REFERENCES merchant_legal_entities(id) ON DELETE RESTRICT,
      FOREIGN KEY (branch_or_outlet_id) REFERENCES merchant_branches_or_outlets(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_brand_legal_by_brand '
    'ON merchant_brand_legal_links(merchant_brand_id, decision, effective_from)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_brand_legal_by_legal '
    'ON merchant_brand_legal_links(legal_entity_id, decision, effective_from)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS merchant_identity_observations (
      id TEXT PRIMARY KEY,
      literal_name TEXT NOT NULL DEFAULT '',
      normalized_name TEXT NOT NULL DEFAULT '',
      seller_identifier TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL,
      source_reference TEXT NOT NULL DEFAULT '',
      merchant_brand_id TEXT,
      legal_entity_id TEXT,
      branch_or_outlet_id TEXT,
      decision TEXT NOT NULL DEFAULT 'observed',
      observed_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK (decision IN ('observed', 'proposed', 'confirmed', 'rejected')),
      CHECK (seller_identifier = '' OR (length(seller_identifier) = 8 AND seller_identifier NOT GLOB '*[^0-9]*')),
      FOREIGN KEY (merchant_brand_id) REFERENCES merchant_brands(id) ON DELETE RESTRICT,
      FOREIGN KEY (legal_entity_id) REFERENCES merchant_legal_entities(id) ON DELETE RESTRICT,
      FOREIGN KEY (branch_or_outlet_id) REFERENCES merchant_branches_or_outlets(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_identity_observations_seller '
    'ON merchant_identity_observations(seller_identifier, observed_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_merchant_identity_observations_brand '
    'ON merchant_identity_observations(merchant_brand_id, observed_at DESC)',
  );
  await _createObservationImmutabilityTriggers(db);

  // Official registry cache is intentionally separated from user-owned
  // merchant identity/history. A failed or replaced registry snapshot can be
  // discarded without deleting merchant brands, links, or observations.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_registry_snapshots (
      version TEXT PRIMARY KEY,
      source_dataset TEXT NOT NULL,
      source_data_date TEXT NOT NULL DEFAULT '',
      content_sha256 TEXT NOT NULL,
      status TEXT NOT NULL,
      installed_at TEXT,
      created_at TEXT NOT NULL,
      CHECK (status IN ('staged', 'installed', 'superseded', 'rejected')),
      CHECK (length(content_sha256) = 64)
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_business_registry_snapshot_status '
    'ON business_registry_snapshots(status, installed_at DESC)',
  );

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
      CHECK (entity_type IN ('company', 'business', 'branch')),
      FOREIGN KEY (snapshot_version) REFERENCES business_registry_snapshots(version) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_business_registry_seller_lookup '
    'ON business_registry_entities(jurisdiction, seller_identifier, snapshot_version)',
  );

  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_registry_negative_lookups (
      seller_identifier TEXT NOT NULL,
      snapshot_version TEXT NOT NULL,
      checked_at TEXT NOT NULL,
      PRIMARY KEY (seller_identifier, snapshot_version),
      CHECK (length(seller_identifier) = 8),
      CHECK (seller_identifier NOT GLOB '*[^0-9]*'),
      FOREIGN KEY (snapshot_version) REFERENCES business_registry_snapshots(version) ON DELETE CASCADE
    )
  ''');

  await _migrateLegacyMerchantsIntoIdentityGraph(db);
}

Future<void> _ensureLegacyMerchantSellerIdentifierColumn(
  DatabaseExecutor db,
) async {
  final merchantTable = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'merchants'",
  );
  if (merchantTable.isEmpty) return;
  final columns = await db.rawQuery('PRAGMA table_info(merchants)');
  if (!columns.any((column) => column['name'] == 'seller_identifier')) {
    await db.execute(
      "ALTER TABLE merchants ADD COLUMN seller_identifier TEXT NOT NULL DEFAULT ''",
    );
  }
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_seller_identifier_unique '
    "ON merchants(seller_identifier) WHERE seller_identifier <> ''",
  );
}

Future<void> _migrateLegacyMerchantsIntoIdentityGraph(
  DatabaseExecutor db,
) async {
  final merchantTable = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'merchants'",
  );
  if (merchantTable.isEmpty) return;

  final rows = await db.rawQuery('''
    SELECT id, name, alias, note, is_archived, created_at, updated_at,
           seller_identifier
    FROM merchants
    WHERE TRIM(id) <> '' AND TRIM(name) <> ''
    ORDER BY id ASC
  ''');

  for (final row in rows) {
    final merchantId = row['id']?.toString() ?? '';
    final name = row['name']?.toString().trim() ?? '';
    final alias = row['alias']?.toString().trim() ?? '';
    final note = row['note']?.toString() ?? '';
    final archived = row['is_archived'] is int ? row['is_archived'] as int : 0;
    final createdAt = row['created_at']?.toString() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toIso8601String();
    final updatedAt = row['updated_at']?.toString() ?? createdAt;
    final sellerIdentifier = (row['seller_identifier']?.toString() ?? '')
        .replaceAll(RegExp(r'[^0-9]'), '');

    await db.insert(
      'merchant_brands',
      <String, Object?>{
        'id': merchantId,
        'display_name': name,
        'display_override': '',
        'note': note,
        'is_archived': archived,
        'created_at': createdAt,
        'updated_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (alias.isNotEmpty) {
      await db.insert(
        'merchant_brand_aliases',
        <String, Object?>{
          'id': 'legacy-alias-$merchantId',
          'merchant_brand_id': merchantId,
          'literal_alias': alias,
          'normalized_alias': normalizeMerchantIdentityName(alias),
          'source': 'legacy_merchant',
          'valid_from': null,
          'valid_to': null,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (sellerIdentifier.length != 8) continue;
    final legalEntityId = 'tw-seller-$sellerIdentifier';
    await db.insert(
      'merchant_legal_entities',
      <String, Object?>{
        'id': legalEntityId,
        'jurisdiction': 'TW',
        'seller_identifier': sellerIdentifier,
        'legal_name': '',
        'entity_type': 'unknown',
        'registration_status': '',
        'registry_source': '',
        'registry_version': '',
        'first_observed_at': createdAt,
        'last_observed_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'merchant_brand_legal_links',
      <String, Object?>{
        'id': 'legacy-link-$merchantId-$sellerIdentifier',
        'merchant_brand_id': merchantId,
        'legal_entity_id': legalEntityId,
        'branch_or_outlet_id': null,
        'decision': 'confirmed',
        'evidence_source': 'p4_19_11_explicit_binding',
        'effective_from': createdAt,
        'effective_to': null,
        'created_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'merchant_identity_observations',
      <String, Object?>{
        'id': 'legacy-observation-$merchantId-$sellerIdentifier',
        'literal_name': name,
        'normalized_name': normalizeMerchantIdentityName(name),
        'seller_identifier': sellerIdentifier,
        'source': 'migration',
        'source_reference': 'merchants/$merchantId',
        'merchant_brand_id': merchantId,
        'legal_entity_id': legalEntityId,
        'branch_or_outlet_id': null,
        'decision': 'confirmed',
        'observed_at': updatedAt,
        'created_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Future<void> _createObservationImmutabilityTriggers(
  DatabaseExecutor db,
) async {
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS $merchantIdentityObservationNoUpdateTrigger
    BEFORE UPDATE ON merchant_identity_observations
    BEGIN
      SELECT RAISE(ABORT, 'merchant identity observations are immutable');
    END
  ''');
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS $merchantIdentityObservationNoDeleteTrigger
    BEFORE DELETE ON merchant_identity_observations
    BEGIN
      SELECT RAISE(ABORT, 'merchant identity observations are immutable');
    END
  ''');
}

String normalizeMerchantIdentityName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s·・_\-－—–]'), '')
    .replaceAll('臺', '台');
