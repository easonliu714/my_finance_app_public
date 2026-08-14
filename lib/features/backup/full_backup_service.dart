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
