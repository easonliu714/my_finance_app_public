import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v22.dart';
import 'business_registry_pack.dart';

enum BusinessRegistryInstallStatus {
  installed,
  alreadyInstalled,
  rejected,
}

class BusinessRegistryInstallResult {
  const BusinessRegistryInstallResult({
    required this.status,
    required this.version,
    required this.entityCount,
    required this.validationErrors,
  });

  final BusinessRegistryInstallStatus status;
  final String version;
  final int entityCount;
  final List<String> validationErrors;

  bool get isSuccess =>
      status == BusinessRegistryInstallStatus.installed ||
      status == BusinessRegistryInstallStatus.alreadyInstalled;
}

enum BusinessRegistryLookupStatus {
  hit,
  notFound,
  noInstalledRegistry,
  invalidSellerIdentifier,
}

class BusinessRegistryLookupResult {
  const BusinessRegistryLookupResult({
    required this.status,
    this.snapshotVersion = '',
    this.sourceDataDate = '',
    this.coverage = '',
    this.entities = const <BusinessRegistryEntity>[],
    this.negativeCacheHit = false,
  });

  final BusinessRegistryLookupStatus status;
  final String snapshotVersion;
  final String sourceDataDate;
  final String coverage;
  final List<BusinessRegistryEntity> entities;
  final bool negativeCacheHit;

  bool get isHit => status == BusinessRegistryLookupStatus.hit;
  BusinessRegistryEntity? get primaryEntity =>
      entities.isEmpty ? null : entities.first;
}

class BusinessRegistrySnapshotInfo {
  const BusinessRegistrySnapshotInfo({
    required this.version,
    required this.sourceDataset,
    required this.sourceDataDate,
    required this.contentSha256,
    required this.coverage,
    required this.installedAt,
  });

  final String version;
  final String sourceDataset;
  final String sourceDataDate;
  final String contentSha256;
  final String coverage;
  final DateTime? installedAt;
}

/// Local-first official business-registry store.
///
/// Normal invoice lookup never performs network I/O. External acquisition is
/// a separate controlled operation that must first produce a validated pack;
/// installation here is atomic and retains the previous installed snapshot if
/// validation or any database write fails.
class BusinessRegistryRepository {
  const BusinessRegistryRepository({this.database});

  final DatabaseExecutor? database;

  Future<DatabaseExecutor> get _db async {
    final resolved =
        database ?? await ProductionDatabaseCoordinator.instance.database;
    await createCanonicalProductionV22Tables(resolved);
    return resolved;
  }

  Future<BusinessRegistryInstallResult> install(
    BusinessRegistryPack pack,
  ) async {
    final validation = await pack.validate();
    if (!validation.isValid) {
      return BusinessRegistryInstallResult(
        status: BusinessRegistryInstallStatus.rejected,
        version: pack.version,
        entityCount: pack.entities.length,
        validationErrors: validation.errors,
      );
    }

    final db = await _db;
    final existing = await db.query(
      'business_registry_snapshots',
      where: 'version = ?',
      whereArgs: <Object?>[pack.version],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final sameSha = existing.first['content_sha256']?.toString() ==
          pack.contentSha256;
      final status = existing.first['status']?.toString() ?? '';
      if (sameSha && status == 'installed') {
        return BusinessRegistryInstallResult(
          status: BusinessRegistryInstallStatus.alreadyInstalled,
          version: pack.version,
          entityCount: pack.entities.length,
          validationErrors: const <String>[],
        );
      }
      throw StateError('BUSINESS_REGISTRY_VERSION_CONFLICT');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await _runTransaction(db, (txn) async {
      await txn.insert('business_registry_snapshots', <String, Object?>{
        'version': pack.version,
        'source_dataset': _snapshotSourceDataset(pack),
        'source_data_date': pack.sourceDataDate,
        'content_sha256': pack.contentSha256,
        'status': 'staged',
        'installed_at': null,
        'created_at': now,
      });

      for (final entity in pack.entities) {
        await txn.insert('business_registry_entities', <String, Object?>{
          'snapshot_version': pack.version,
          'jurisdiction': 'TW',
          'seller_identifier': entity.sellerIdentifier,
          'entity_type': entity.entityType.name,
          'legal_name': entity.legalName.trim(),
          'registration_status': entity.registrationStatus.trim(),
          'parent_seller_identifier': entity.parentSellerIdentifier.trim(),
          'source_dataset': entity.sourceDataset.trim(),
        });
      }

      await txn.update(
        'business_registry_snapshots',
        <String, Object?>{'status': 'superseded'},
        where: "status = 'installed' AND version <> ?",
        whereArgs: <Object?>[pack.version],
      );
      await txn.update(
        'business_registry_snapshots',
        <String, Object?>{
          'status': 'installed',
          'installed_at': now,
        },
        where: 'version = ?',
        whereArgs: <Object?>[pack.version],
      );
    });

    return BusinessRegistryInstallResult(
      status: BusinessRegistryInstallStatus.installed,
      version: pack.version,
      entityCount: pack.entities.length,
      validationErrors: const <String>[],
    );
  }

  Future<BusinessRegistrySnapshotInfo?> installedSnapshot() async {
    final db = await _db;
    final rows = await db.query(
      'business_registry_snapshots',
      where: 'status = ?',
      whereArgs: const <Object?>['installed'],
      orderBy: 'installed_at DESC, created_at DESC, version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _snapshotFromRow(rows.first);
  }

  Future<BusinessRegistryLookupResult> lookup(
    String sellerIdentifier,
  ) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(seller)) {
      return const BusinessRegistryLookupResult(
        status: BusinessRegistryLookupStatus.invalidSellerIdentifier,
      );
    }

    final snapshot = await installedSnapshot();
    if (snapshot == null) {
      return const BusinessRegistryLookupResult(
        status: BusinessRegistryLookupStatus.noInstalledRegistry,
      );
    }

    final db = await _db;
    final rows = await db.query(
      'business_registry_entities',
      where: 'snapshot_version = ? AND jurisdiction = ? AND seller_identifier = ?',
      whereArgs: <Object?>[snapshot.version, 'TW', seller],
      orderBy: 'entity_type ASC, legal_name ASC',
    );
    if (rows.isNotEmpty) {
      return BusinessRegistryLookupResult(
        status: BusinessRegistryLookupStatus.hit,
        snapshotVersion: snapshot.version,
        sourceDataDate: snapshot.sourceDataDate,
        coverage: snapshot.coverage,
        entities: List<BusinessRegistryEntity>.unmodifiable(
          rows.map(_entityFromRow),
        ),
      );
    }

    final cached = await db.query(
      'business_registry_negative_lookups',
      where: 'seller_identifier = ? AND snapshot_version = ?',
      whereArgs: <Object?>[seller, snapshot.version],
      limit: 1,
    );
    if (cached.isEmpty) {
      await db.insert(
        'business_registry_negative_lookups',
        <String, Object?>{
          'seller_identifier': seller,
          'snapshot_version': snapshot.version,
          'checked_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return BusinessRegistryLookupResult(
      status: BusinessRegistryLookupStatus.notFound,
      snapshotVersion: snapshot.version,
      sourceDataDate: snapshot.sourceDataDate,
      coverage: snapshot.coverage,
      negativeCacheHit: cached.isNotEmpty,
    );
  }

  String _snapshotSourceDataset(BusinessRegistryPack pack) =>
      '${pack.sourceAuthority}|${pack.coverage}|${pack.sourceDataset}';

  BusinessRegistrySnapshotInfo _snapshotFromRow(Map<String, Object?> row) {
    final encodedSource = row['source_dataset']?.toString() ?? '';
    final parts = encodedSource.split('|');
    final coverage = parts.length >= 3 ? parts[1] : '';
    final sourceDataset = parts.length >= 3
        ? parts.sublist(2).join('|')
        : encodedSource;
    return BusinessRegistrySnapshotInfo(
      version: row['version']?.toString() ?? '',
      sourceDataset: sourceDataset,
      sourceDataDate: row['source_data_date']?.toString() ?? '',
      contentSha256: row['content_sha256']?.toString() ?? '',
      coverage: coverage,
      installedAt: DateTime.tryParse(row['installed_at']?.toString() ?? ''),
    );
  }

  BusinessRegistryEntity _entityFromRow(Map<String, Object?> row) {
    final type = row['entity_type']?.toString() ?? '';
    return BusinessRegistryEntity(
      sellerIdentifier: row['seller_identifier']?.toString() ?? '',
      entityType: BusinessRegistryEntityType.values.firstWhere(
        (item) => item.name == type,
      ),
      legalName: row['legal_name']?.toString() ?? '',
      registrationStatus: row['registration_status']?.toString() ?? '',
      parentSellerIdentifier:
          row['parent_seller_identifier']?.toString() ?? '',
      sourceDataset: row['source_dataset']?.toString() ?? '',
    );
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
