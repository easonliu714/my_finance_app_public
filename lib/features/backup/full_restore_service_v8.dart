import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v22_merchant_identity.dart';
import 'full_backup_scope.dart';
import 'full_restore_service.dart';
import 'full_restore_service_v7.dart';

/// P4.20.0 backup/restore authority for schema V22.
///
/// User-owned merchant identity/history is restored with the accounting data.
/// Replaceable official business-registry cache is intentionally outside the
/// backup scope and therefore remains independently rebuildable.
class FullRestoreServiceV8 extends FullRestoreServiceV7 {
  const FullRestoreServiceV8({super.backupService});

  @override
  Future<FullRestoreResult> restoreFromJson(
    Database db,
    String jsonText, {
    required String confirmationText,
    DateTime? preRestoreBackupCreatedAt,
    String sourcePlatform = 'android',
    Future<String> Function(Map<String, Object?> envelope)?
        persistPreRestoreBackup,
  }) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      throw const FullRestoreException(
        '備份檔格式錯誤：root 必須是 JSON object',
      );
    }
    return restoreFromEnvelope(
      db,
      decoded,
      confirmationText: confirmationText,
      preRestoreBackupCreatedAt: preRestoreBackupCreatedAt,
      sourcePlatform: sourcePlatform,
      persistPreRestoreBackup: persistPreRestoreBackup,
    );
  }

  @override
  Future<FullRestoreResult> restoreFromEnvelope(
    Database db,
    Map<String, Object?> envelope, {
    required String confirmationText,
    DateTime? preRestoreBackupCreatedAt,
    String sourcePlatform = 'android',
    Future<String> Function(Map<String, Object?> envelope)?
        persistPreRestoreBackup,
  }) async {
    final normalized = _normalizeToScopeV8(envelope);
    final hasObservationTable = await _tableExists(
      db,
      'merchant_identity_observations',
    );
    if (hasObservationTable) {
      await _dropObservationImmutabilityTriggers(db);
    }
    try {
      return await super.restoreFromEnvelope(
        db,
        normalized,
        confirmationText: confirmationText,
        preRestoreBackupCreatedAt: preRestoreBackupCreatedAt,
        sourcePlatform: sourcePlatform,
        persistPreRestoreBackup: persistPreRestoreBackup,
      );
    } finally {
      if (hasObservationTable) {
        await _createObservationImmutabilityTriggers(db);
      }
    }
  }

  Map<String, Object?> _normalizeToScopeV8(
    Map<String, Object?> envelope,
  ) {
    final metadataRaw = envelope['metadata'];
    final dataRaw = envelope['data'];
    if (metadataRaw is! Map || dataRaw is! Map) return envelope;

    final metadata = Map<String, Object?>.from(metadataRaw);
    final data = Map<String, Object?>.from(dataRaw);
    final rawScope = metadata['backup_scope_version'];
    final scopeVersion = rawScope is int ? rawScope : 0;
    final exportFormat = metadata['export_format_version'];
    final isLegacyV1 = exportFormat == 1;

    if (scopeVersion >= FullBackupScope.backupScopeVersion && !isLegacyV1) {
      return envelope;
    }

    for (final tableName in FullBackupScope.backupTableNames) {
      data.putIfAbsent(tableName, () => const <Object?>[]);
    }
    _populateLegacyMerchantIdentityRows(data);

    metadata['backup_scope_version'] = FullBackupScope.backupScopeVersion;
    metadata['included_tables'] = FullBackupScope.backupTableNames;
    metadata['unknown_tables'] = const <Object?>[];
    metadata['missing_required_tables'] = const <Object?>[];
    metadata['coverage_complete'] = true;

    return <String, Object?>{
      ...envelope,
      'metadata': metadata,
      'data': data,
    };
  }

  void _populateLegacyMerchantIdentityRows(Map<String, Object?> data) {
    final rawMerchants = data['merchants'];
    if (rawMerchants is! List) return;

    final brands = <Object?>[];
    final aliases = <Object?>[];
    final legalEntities = <Object?>[];
    final links = <Object?>[];
    final observations = <Object?>[];
    final seenSellerIdentifiers = <String>{};

    for (final raw in rawMerchants) {
      if (raw is! Map) continue;
      final row = Map<String, Object?>.from(raw);
      final merchantId = row['id']?.toString().trim() ?? '';
      final name = row['name']?.toString().trim() ?? '';
      if (merchantId.isEmpty || name.isEmpty) continue;

      final alias = row['alias']?.toString().trim() ?? '';
      final note = row['note']?.toString() ?? '';
      final archived = _asInt(row['is_archived']);
      final createdAt = _timestamp(
        row['created_at'],
        fallback: '1970-01-01T00:00:00.000Z',
      );
      final updatedAt = _timestamp(row['updated_at'], fallback: createdAt);
      final sellerIdentifier = (row['seller_identifier']?.toString() ?? '')
          .replaceAll(RegExp(r'[^0-9]'), '');

      brands.add(<String, Object?>{
        'id': merchantId,
        'display_name': name,
        'display_override': '',
        'note': note,
        'is_archived': archived,
        'created_at': createdAt,
        'updated_at': updatedAt,
      });

      if (alias.isNotEmpty) {
        aliases.add(<String, Object?>{
          'id': 'legacy-alias-$merchantId',
          'merchant_brand_id': merchantId,
          'literal_alias': alias,
          'normalized_alias': normalizeMerchantIdentityName(alias),
          'source': 'legacy_backup_restore',
          'valid_from': null,
          'valid_to': null,
          'created_at': createdAt,
        });
      }

      if (sellerIdentifier.length != 8) continue;
      final legalId = 'tw-seller-$sellerIdentifier';
      if (seenSellerIdentifiers.add(sellerIdentifier)) {
        legalEntities.add(<String, Object?>{
          'id': legalId,
          'jurisdiction': 'TW',
          'seller_identifier': sellerIdentifier,
          'legal_name': '',
          'entity_type': 'unknown',
          'registration_status': '',
          'registry_source': '',
          'registry_version': '',
          'first_observed_at': createdAt,
          'last_observed_at': updatedAt,
        });
      }
      links.add(<String, Object?>{
        'id': 'legacy-link-$merchantId-$sellerIdentifier',
        'merchant_brand_id': merchantId,
        'legal_entity_id': legalId,
        'branch_or_outlet_id': null,
        'decision': 'confirmed',
        'evidence_source': 'legacy_backup_explicit_binding',
        'effective_from': createdAt,
        'effective_to': null,
        'created_at': updatedAt,
      });
      observations.add(<String, Object?>{
        'id': 'legacy-observation-$merchantId-$sellerIdentifier',
        'literal_name': name,
        'normalized_name': normalizeMerchantIdentityName(name),
        'seller_identifier': sellerIdentifier,
        'source': 'backup_restore_migration',
        'source_reference': 'merchants/$merchantId',
        'merchant_brand_id': merchantId,
        'legal_entity_id': legalId,
        'branch_or_outlet_id': null,
        'decision': 'confirmed',
        'observed_at': updatedAt,
        'created_at': updatedAt,
      });
    }

    data['merchant_brands'] = brands;
    data['merchant_brand_aliases'] = aliases;
    data['merchant_legal_entities'] = legalEntities;
    data['merchant_branches_or_outlets'] = const <Object?>[];
    data['merchant_brand_legal_links'] = links;
    data['merchant_identity_observations'] = observations;
  }

  Future<void> _dropObservationImmutabilityTriggers(
    DatabaseExecutor db,
  ) async {
    await db.execute(
      'DROP TRIGGER IF EXISTS $merchantIdentityObservationNoUpdateTrigger',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS $merchantIdentityObservationNoDeleteTrigger',
    );
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

  Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _timestamp(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
