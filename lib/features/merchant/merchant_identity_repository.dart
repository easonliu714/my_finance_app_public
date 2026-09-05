import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v22.dart';
import 'business_registry_pack.dart';
import 'merchant_record.dart';

class ConfirmedMerchantIdentity {
  const ConfirmedMerchantIdentity({
    required this.merchantBrandId,
    required this.displayName,
    required this.sellerIdentifier,
    required this.legalEntityId,
    this.legalName = '',
    this.registrySource = '',
    this.registryVersion = '',
  });

  final String merchantBrandId;
  final String displayName;
  final String sellerIdentifier;
  final String legalEntityId;
  final String legalName;
  final String registrySource;
  final String registryVersion;
}

class MerchantIdentityRepository {
  const MerchantIdentityRepository({this.database});

  final DatabaseExecutor? database;

  Future<DatabaseExecutor> get _db async {
    final resolved =
        database ?? await ProductionDatabaseCoordinator.instance.database;
    await createCanonicalProductionV22Tables(resolved);
    return resolved;
  }

  Future<ConfirmedMerchantIdentity?> findConfirmedBySellerIdentifier(
    String sellerIdentifier,
  ) async {
    final seller = _normalizeSeller(sellerIdentifier);
    if (seller.length != 8) return null;
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        b.id AS merchant_brand_id,
        b.display_name,
        b.display_override,
        le.id AS legal_entity_id,
        le.seller_identifier,
        le.legal_name,
        le.registry_source,
        le.registry_version
      FROM merchant_legal_entities le
      JOIN merchant_brand_legal_links l
        ON l.legal_entity_id = le.id
      JOIN merchant_brands b
        ON b.id = l.merchant_brand_id
      WHERE le.jurisdiction = 'TW'
        AND le.seller_identifier = ?
        AND l.decision = 'confirmed'
        AND (l.effective_to IS NULL OR TRIM(l.effective_to) = '')
        AND b.is_archived = 0
      ORDER BY l.created_at DESC, l.id DESC
      LIMIT 1
    ''', <Object?>[seller]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final override = row['display_override']?.toString().trim() ?? '';
    final display = override.isEmpty
        ? row['display_name']?.toString().trim() ?? ''
        : override;
    return ConfirmedMerchantIdentity(
      merchantBrandId: row['merchant_brand_id']?.toString() ?? '',
      displayName: display,
      sellerIdentifier: row['seller_identifier']?.toString() ?? '',
      legalEntityId: row['legal_entity_id']?.toString() ?? '',
      legalName: row['legal_name']?.toString() ?? '',
      registrySource: row['registry_source']?.toString() ?? '',
      registryVersion: row['registry_version']?.toString() ?? '',
    );
  }

  Future<ConfirmedMerchantIdentity> recordConfirmedBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
    BusinessRegistryEntity? officialEntity,
    String registryVersion = '',
  }) async {
    final seller = _normalizeSeller(sellerIdentifier);
    if (!RegExp(r'^\d{8}$').hasMatch(seller)) {
      throw ArgumentError.value(
        sellerIdentifier,
        'sellerIdentifier',
        'must resolve to exactly 8 digits',
      );
    }
    final brandId = merchant.id.trim();
    final brandName = merchant.displayName.trim();
    if (brandId.isEmpty || brandName.isEmpty) {
      throw ArgumentError('Merchant brand id/name must not be blank');
    }

    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final legalId = 'tw-seller-$seller';
    final observationId = await _stableId(
      'invoice-observation',
      '$sourceReference|$seller|$brandId|${literalMerchantText.trim()}',
    );
    final registryObservationId = officialEntity == null
        ? ''
        : await _stableId(
            'registry-observation',
            '$registryVersion|$seller|${officialEntity.entityType.name}|${officialEntity.legalName}',
          );

    await _runTransaction(db, (txn) async {
      await txn.insert(
        'merchant_brands',
        <String, Object?>{
          'id': brandId,
          'display_name': merchant.name.trim(),
          'display_override': merchant.alias.trim().isEmpty
              ? ''
              : merchant.displayName.trim(),
          'note': merchant.note.trim(),
          'is_archived': merchant.isArchived ? 1 : 0,
          'created_at': merchant.createdAt.toUtc().toIso8601String(),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final legalRows = await txn.query(
        'merchant_legal_entities',
        where: 'jurisdiction = ? AND seller_identifier = ?',
        whereArgs: <Object?>['TW', seller],
        limit: 1,
      );
      if (legalRows.isEmpty) {
        await txn.insert('merchant_legal_entities', <String, Object?>{
          'id': legalId,
          'jurisdiction': 'TW',
          'seller_identifier': seller,
          'legal_name': officialEntity?.legalName.trim() ?? '',
          'entity_type': officialEntity?.entityType.name ?? 'unknown',
          'registration_status':
              officialEntity?.registrationStatus.trim() ?? '',
          'registry_source': officialEntity?.sourceDataset.trim() ?? '',
          'registry_version': registryVersion.trim(),
          'first_observed_at': now,
          'last_observed_at': now,
        });
      } else if (officialEntity != null) {
        await txn.update(
          'merchant_legal_entities',
          <String, Object?>{
            'legal_name': officialEntity.legalName.trim(),
            'entity_type': officialEntity.entityType.name,
            'registration_status': officialEntity.registrationStatus.trim(),
            'registry_source': officialEntity.sourceDataset.trim(),
            'registry_version': registryVersion.trim(),
            'last_observed_at': now,
          },
          where: 'id = ?',
          whereArgs: <Object?>[legalRows.first['id']?.toString() ?? legalId],
        );
      }

      final conflicts = await txn.query(
        'merchant_brand_legal_links',
        where:
            "legal_entity_id = ? AND decision = 'confirmed' AND merchant_brand_id <> ? AND (effective_to IS NULL OR TRIM(effective_to) = '')",
        whereArgs: <Object?>[legalId, brandId],
        limit: 1,
      );
      if (conflicts.isNotEmpty) {
        throw StateError('MERCHANT_IDENTITY_CONFIRMED_BRAND_CONFLICT');
      }

      final sameLink = await txn.query(
        'merchant_brand_legal_links',
        where:
            "legal_entity_id = ? AND merchant_brand_id = ? AND decision = 'confirmed' AND (effective_to IS NULL OR TRIM(effective_to) = '')",
        whereArgs: <Object?>[legalId, brandId],
        limit: 1,
      );
      if (sameLink.isEmpty) {
        await txn.insert('merchant_brand_legal_links', <String, Object?>{
          'id': await _stableId(
            'confirmed-link',
            '$brandId|$seller',
          ),
          'merchant_brand_id': brandId,
          'legal_entity_id': legalId,
          'branch_or_outlet_id': null,
          'decision': 'confirmed',
          'evidence_source': evidenceSource.trim(),
          'effective_from': now,
          'effective_to': null,
          'created_at': now,
        });
      }

      await txn.insert(
        'merchant_identity_observations',
        <String, Object?>{
          'id': observationId,
          'literal_name': literalMerchantText.trim(),
          'normalized_name': normalizeMerchantIdentityName(
            literalMerchantText,
          ),
          'seller_identifier': seller,
          'source': evidenceSource.trim(),
          'source_reference': sourceReference.trim(),
          'merchant_brand_id': brandId,
          'legal_entity_id': legalId,
          'branch_or_outlet_id': null,
          'decision': 'confirmed',
          'observed_at': now,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      if (officialEntity != null) {
        await txn.insert(
          'merchant_identity_observations',
          <String, Object?>{
            'id': registryObservationId,
            'literal_name': officialEntity.legalName.trim(),
            'normalized_name': normalizeMerchantIdentityName(
              officialEntity.legalName,
            ),
            'seller_identifier': seller,
            'source': 'official_registry',
            'source_reference':
                '${officialEntity.sourceDataset}|${registryVersion.trim()}',
            'merchant_brand_id': brandId,
            'legal_entity_id': legalId,
            'branch_or_outlet_id': null,
            'decision': 'observed',
            'observed_at': now,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    return (await findConfirmedBySellerIdentifier(seller))!;
  }

  String _normalizeSeller(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  Future<String> _stableId(String prefix, String material) async {
    final digest = await Sha256().hash(utf8.encode(material));
    final hex = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${hex.substring(0, 32)}';
  }

  Future<T> _runTransaction<T>(
    DatabaseExecutor db,
    Future<T> Function(DatabaseExecutor txn) action,
  ) async {
    if (db is Database) {
      return db.transaction<T>((txn) => action(txn));
    }
    return action(db);
  }
}
