import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../app_build_metadata.dart';
import 'full_backup_scope.dart';

class FullBackupService {
  const FullBackupService();

  static const int exportFormatVersion =
      FullBackupScope.exportFormatVersion;
  static const int databaseSchemaVersion =
      FullBackupScope.databaseSchemaVersion;
  static const String appName = AppBuildMetadata.appName;
  static const String appVersion = AppBuildMetadata.appVersion;
  static const String phase = AppBuildMetadata.phase;
  static const String exportModeFullBackup = 'full_backup';

  static const List<String> backupTableNames =
      FullBackupScope.backupTableNames;

  Future<Map<String, Object?>> buildFullBackupEnvelope(
    DatabaseExecutor db, {
    DateTime? createdAt,
    String sourcePlatform = 'android',
  }) async {
    final coverage = await FullBackupScope.inspect(db);
    if (!coverage.isComplete) {
      throw FullBackupCoverageException(coverage.blockingMessage());
    }

    final timestamp = (createdAt ?? DateTime.now().toUtc()).toUtc();
    final data = <String, Object?>{};
    for (final tableName in backupTableNames) {
      data[tableName] = await _readTableRows(db, tableName);
    }
    return <String, Object?>{
      'metadata': <String, Object?>{
        'export_format_version': exportFormatVersion,
        'app_name': appName,
        'app_version': appVersion,
        'phase': phase,
        'database_schema_version': databaseSchemaVersion,
        'created_at': timestamp.toIso8601String(),
        'source_platform': sourcePlatform,
        'export_mode': exportModeFullBackup,
        ...coverage.toMetadata(),
      },
      'data': data,
    };
  }


  // B3 V29: compare only managed-table DDL, indexes and triggers. This is
  // read-only SQLite metadata; public Registry cache DDL is intentionally
  // excluded, and no financial row or backup payload is copied here.
  Future<List<Map<String, Object?>>> captureManagedSchema(
    DatabaseExecutor db,
  ) async {
    final managedTables = backupTableNames.toSet();
    final rows = await db.rawQuery(
      'SELECT type, name, tbl_name, sql FROM sqlite_master '
      "WHERE type IN ('table', 'index', 'trigger') "
      "AND name NOT LIKE 'sqlite_%' "
      'ORDER BY type ASC, name ASC',
    );
    return rows
        .where((row) => managedTables.contains(row['tbl_name']))
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<bool> managedSchemaMatches(
    DatabaseExecutor db,
    List<Map<String, Object?>> expected,
  ) async {
    return _snapshotValueEquals(expected, await captureManagedSchema(db));
  }

  // B3 V27: after external custody persistence, re-read every managed table
  // under the SAME SQLite restore transaction before dropping immutable-row
  // guards or deleting anything. A stale backup cannot authorize destruction
  // of writes made while custody I/O was pending. Public cache is excluded.
  Future<bool> managedSnapshotMatches(
    DatabaseExecutor db,
    Map<String, Object?> snapshot,
  ) async {
    final metadata = snapshot['metadata'];
    final data = snapshot['data'];
    if (metadata is! Map || data is! Map) return false;
    final coverage = await FullBackupScope.inspect(db);
    if (!coverage.isComplete) return false;
    final expectedPresent = metadata['included_present_tables'];
    if (!_snapshotValueEquals(
      expectedPresent, coverage.includedPresentTables,
    )) {
      return false;
    }
    for (final tableName in backupTableNames) {
      final expected = data[tableName];
      if (expected is! List) return false;
      final actual = await _readTableRows(db, tableName);
      if (!_snapshotValueEquals(expected, actual)) return false;
    }
    return true;
  }

  // Compare typed SQLite cells without JSON re-encoding or an additional
  // whole-database allocation. Also supports BLOB bytes represented as lists.
  bool _snapshotValueEquals(Object? expected, Object? actual) {
    if (expected is Map && actual is Map) {
      if (expected.length != actual.length) return false;
      for (final key in expected.keys) {
        if (!actual.containsKey(key) ||
            !_snapshotValueEquals(expected[key], actual[key])) {
          return false;
        }
      }
      return true;
    }
    if (expected is List && actual is List) {
      if (expected.length != actual.length) return false;
      for (var i = 0; i < expected.length; i++) {
        if (!_snapshotValueEquals(expected[i], actual[i])) return false;
      }
      return true;
    }
    return expected == actual;
  }

  Future<String> buildFullBackupJson(
    DatabaseExecutor db, {
    DateTime? createdAt,
    String sourcePlatform = 'android',
  }) async {
    final envelope = await buildFullBackupEnvelope(
      db,
      createdAt: createdAt,
      sourcePlatform: sourcePlatform,
    );
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  Future<File> writeFullBackupFile(
    DatabaseExecutor db, {
    Directory? baseDirectory,
    DateTime? createdAt,
    String sourcePlatform = 'android',
  }) async {
    final timestamp = (createdAt ?? DateTime.now().toUtc()).toUtc();
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(p.join(root.path, 'backups'));
    if (!backupDirectory.existsSync()) {
      backupDirectory.createSync(recursive: true);
    }
    final file = File(p.join(backupDirectory.path, _backupFileName(timestamp)));
    final json = await buildFullBackupJson(
      db,
      createdAt: timestamp,
      sourcePlatform: sourcePlatform,
    );
    return file.writeAsString(json, flush: true);
  }

  Future<List<Map<String, Object?>>> _readTableRows(
    DatabaseExecutor db,
    String tableName,
  ) async {
    if (!await _tableExists(db, tableName)) return <Map<String, Object?>>[];
    final orderBy = await _preferredOrderBy(db, tableName);
    return db.query(tableName, orderBy: orderBy);
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

  Future<String?> _preferredOrderBy(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final names = columns
        .map((column) => column['name'])
        .whereType<String>()
        .toSet();
    if (names.contains('id')) return 'id ASC';
    if (names.contains('card_id')) return 'card_id ASC';
    if (names.contains('invoice_number')) return 'invoice_number ASC';
    if (names.contains('operation_key')) return 'operation_key ASC';
    if (names.contains('rollback_token')) return 'rollback_token ASC';
    if (names.contains('created_at')) return 'created_at ASC';
    return null;
  }

  String _backupFileName(DateTime timestamp) {
    final safeTimestamp = timestamp
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return '${appName}_backup_v${exportFormatVersion}_$safeTimestamp.json';
  }
}
