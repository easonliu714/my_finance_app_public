import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v13.dart';

const String legacyMerchantMigrationMarker =
    'merchant_master_to_canonical_v13';

class LegacyMerchantMigrationReport {
  const LegacyMerchantMigrationReport({
    required this.sourcePath,
    required this.sourceRows,
    required this.copiedRows,
    required this.skippedRows,
    required this.alreadyCompleted,
  });

  final String sourcePath;
  final int sourceRows;
  final int copiedRows;
  final int skippedRows;
  final bool alreadyCompleted;
}

class LegacyMerchantMigrationService {
  const LegacyMerchantMigrationService();

  Future<LegacyMerchantMigrationReport> migrate(
    Database canonical, {
    String? legacyDatabasePath,
  }) async {
    await createCanonicalProductionV13Tables(canonical);

    final existingMarker = await canonical.query(
      'production_migration_markers',
      where: 'marker_key = ? AND status = ?',
      whereArgs: [legacyMerchantMigrationMarker, 'completed'],
      limit: 1,
    );
    if (existingMarker.isNotEmpty) {
      return LegacyMerchantMigrationReport(
        sourcePath: existingMarker.first['source_path'] as String? ?? '',
        sourceRows:
            (existingMarker.first['source_row_count'] as num? ?? 0).toInt(),
        copiedRows:
            (existingMarker.first['copied_row_count'] as num? ?? 0).toInt(),
        skippedRows:
            (existingMarker.first['skipped_row_count'] as num? ?? 0).toInt(),
        alreadyCompleted: true,
      );
    }

    final sourcePath = legacyDatabasePath ??
        p.join(await getDatabasesPath(), 'merchant_master.db');
    if (!await databaseExists(sourcePath)) {
      final now = DateTime.now().toUtc().toIso8601String();
      await canonical.transaction((txn) async {
        await _writeCompletedMarker(
          txn,
          sourcePath: sourcePath,
          sourceRows: 0,
          copiedRows: 0,
          skippedRows: 0,
          details: 'legacy database not found',
          startedAt: now,
          completedAt: now,
        );
      });
      return LegacyMerchantMigrationReport(
        sourcePath: sourcePath,
        sourceRows: 0,
        copiedRows: 0,
        skippedRows: 0,
        alreadyCompleted: false,
      );
    }

    Database? legacy;
    try {
      legacy = await openReadOnlyDatabase(sourcePath);
      await _validateLegacySchema(legacy);
      final rows = await legacy.query(
        'merchants',
        orderBy: 'name COLLATE NOCASE ASC, alias COLLATE NOCASE ASC, id ASC',
      );
      final startedAt = DateTime.now().toUtc().toIso8601String();
      var copied = 0;
      var skipped = 0;
      var conflicts = 0;

      await canonical.transaction((txn) async {
        for (final row in rows) {
          final normalized = _normalizeLegacyRow(row);
          if (normalized == null) {
            skipped += 1;
            continue;
          }

          final byId = await txn.query(
            'merchants',
            where: 'id = ?',
            whereArgs: [normalized['id']],
            limit: 1,
          );
          if (byId.isNotEmpty) {
            if (!_sameMerchant(byId.first, normalized)) conflicts += 1;
            skipped += 1;
            continue;
          }

          final byIdentity = await txn.query(
            'merchants',
            where: 'name = ? AND alias = ?',
            whereArgs: [normalized['name'], normalized['alias']],
            limit: 1,
          );
          if (byIdentity.isNotEmpty) {
            skipped += 1;
            continue;
          }

          await txn.insert('merchants', normalized);
          copied += 1;
        }

        final completedAt = DateTime.now().toUtc().toIso8601String();
        await _writeCompletedMarker(
          txn,
          sourcePath: sourcePath,
          sourceRows: rows.length,
          copiedRows: copied,
          skippedRows: skipped,
          details: conflicts == 0
              ? 'copy-only migration completed'
              : 'copy-only migration completed; $conflicts canonical conflicts preserved',
          startedAt: startedAt,
          completedAt: completedAt,
        );
      });

      return LegacyMerchantMigrationReport(
        sourcePath: sourcePath,
        sourceRows: rows.length,
        copiedRows: copied,
        skippedRows: skipped,
        alreadyCompleted: false,
      );
    } finally {
      await legacy?.close();
    }
  }

  Future<void> _validateLegacySchema(Database legacy) async {
    final table = await legacy.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name = 'merchants'",
      limit: 1,
    );
    if (table.isEmpty) {
      throw StateError('LEGACY_MERCHANT_TABLE_NOT_FOUND');
    }

    final columns = await legacy.rawQuery('PRAGMA table_info(merchants)');
    final names = columns.map((column) => column['name']).toSet();
    const required = <String>{
      'id',
      'name',
      'alias',
      'note',
      'is_archived',
      'created_at',
      'updated_at',
    };
    if (!names.containsAll(required)) {
      final missing = required.difference(names).toList()..sort();
      throw StateError('LEGACY_MERCHANT_SCHEMA_UNSUPPORTED:${missing.join(',')}');
    }
  }

  Map<String, Object?>? _normalizeLegacyRow(Map<String, Object?> row) {
    final id = (row['id'] as String? ?? '').trim();
    final name = (row['name'] as String? ?? '').trim();
    if (id.isEmpty || name.isEmpty) return null;

    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        .toIso8601String();
    final createdAt = _normalizedTimestamp(row['created_at'], epoch);
    final updatedAt = _normalizedTimestamp(row['updated_at'], createdAt);
    return <String, Object?>{
      'id': id,
      'name': name,
      'alias': (row['alias'] as String? ?? '').trim(),
      'note': (row['note'] as String? ?? '').trim(),
      'is_archived': (row['is_archived'] as num? ?? 0).toInt() == 0 ? 0 : 1,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  String _normalizedTimestamp(Object? value, String fallback) {
    final text = value as String?;
    if (text == null || DateTime.tryParse(text) == null) return fallback;
    return DateTime.parse(text).toUtc().toIso8601String();
  }

  bool _sameMerchant(
    Map<String, Object?> canonical,
    Map<String, Object?> legacy,
  ) {
    const keys = <String>[
      'id',
      'name',
      'alias',
      'note',
      'is_archived',
      'created_at',
      'updated_at',
    ];
    for (final key in keys) {
      if (canonical[key]?.toString() != legacy[key]?.toString()) return false;
    }
    return true;
  }

  Future<void> _writeCompletedMarker(
    DatabaseExecutor db, {
    required String sourcePath,
    required int sourceRows,
    required int copiedRows,
    required int skippedRows,
    required String details,
    required String startedAt,
    required String completedAt,
  }) async {
    await db.insert(
      'production_migration_markers',
      <String, Object?>{
        'marker_key': legacyMerchantMigrationMarker,
        'status': 'completed',
        'source_path': sourcePath,
        'source_row_count': sourceRows,
        'copied_row_count': copiedRows,
        'skipped_row_count': skippedRows,
        'details': details,
        'started_at': startedAt,
        'completed_at': completedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
