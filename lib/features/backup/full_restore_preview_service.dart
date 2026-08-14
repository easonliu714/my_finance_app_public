import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'full_backup_scope.dart';
import 'full_backup_service.dart';

class FullRestoreBackupPreview {
  const FullRestoreBackupPreview({
    required this.filePath,
    required this.fileName,
    required this.isValid,
    required this.message,
    required this.metadata,
    required this.tableRowCounts,
    this.tableImpacts = const <FullRestoreTableImpact>[],
  });

  final String filePath;
  final String fileName;
  final bool isValid;
  final String message;
  final FullRestoreBackupMetadata? metadata;
  final Map<String, int> tableRowCounts;
  final List<FullRestoreTableImpact> tableImpacts;

  FullRestoreBackupPreview copyWithTableImpacts(
    List<FullRestoreTableImpact> impacts,
  ) => FullRestoreBackupPreview(
        filePath: filePath,
        fileName: fileName,
        isValid: isValid,
        message: message,
        metadata: metadata,
        tableRowCounts: tableRowCounts,
        tableImpacts: impacts,
      );
}

class FullRestoreBackupMetadata {
  const FullRestoreBackupMetadata({
    required this.appName,
    required this.appVersion,
    required this.phase,
    required this.exportFormatVersion,
    required this.databaseSchemaVersion,
    required this.createdAt,
    required this.sourcePlatform,
    required this.exportMode,
    this.backupScopeVersion,
    this.coverageComplete,
  });

  final String appName;
  final String appVersion;
  final String phase;
  final int? exportFormatVersion;
  final int? databaseSchemaVersion;
  final String createdAt;
  final String sourcePlatform;
  final String exportMode;
  final int? backupScopeVersion;
  final bool? coverageComplete;
}

enum FullRestoreImpactLevel { none, low, medium, high }

class FullRestoreTableImpact {
  const FullRestoreTableImpact({
    required this.tableName,
    required this.currentCount,
    required this.backupCount,
    required this.delta,
    required this.level,
  });

  final String tableName;
  final int currentCount;
  final int backupCount;
  final int delta;
  final FullRestoreImpactLevel level;
}

class FullRestorePreviewService {
  const FullRestorePreviewService({
    this.impactService = const FullRestoreImpactPreviewService(),
  });

  final FullRestoreImpactPreviewService impactService;

  Future<List<FullRestoreBackupPreview>> scanSourceDirectory(
    Directory sourceDirectory, {
    DatabaseExecutor? currentDb,
  }) async {
    if (!sourceDirectory.existsSync()) return const [];
    final files = sourceDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final previews = <FullRestoreBackupPreview>[];
    for (final file in files) {
      previews.add(await previewFile(file, currentDb: currentDb));
    }
    return previews;
  }

  Future<FullRestoreBackupPreview> previewFile(
    File file, {
    DatabaseExecutor? currentDb,
  }) async {
    final fileName = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    try {
      return await _previewJsonString(
        await file.readAsString(),
        filePath: file.path,
        fileName: fileName,
        currentDb: currentDb,
      );
    } catch (error) {
      return _invalid(file.path, fileName, '無法解析備份檔：$error');
    }
  }

  Future<FullRestoreBackupPreview> previewBytes(
    Uint8List bytes, {
    required String sourceUri,
    required String fileName,
    DatabaseExecutor? currentDb,
  }) async {
    try {
      return await _previewJsonString(
        utf8.decode(bytes),
        filePath: sourceUri,
        fileName: fileName,
        currentDb: currentDb,
      );
    } catch (error) {
      return _invalid(sourceUri, fileName, '無法解析備份檔：$error');
    }
  }

  Future<FullRestoreBackupPreview> _previewJsonString(
    String jsonText, {
    required String filePath,
    required String fileName,
    DatabaseExecutor? currentDb,
  }) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      return _invalid(filePath, fileName, '備份檔格式錯誤：JSON root 必須是 object。');
    }
    final metadataRaw = decoded['metadata'];
    final dataRaw = decoded['data'];
    if (metadataRaw is! Map || dataRaw is! Map) {
      return _invalid(filePath, fileName, '備份檔格式錯誤：缺少 metadata 或 data。');
    }
    final metadata = metadataRaw.cast<String, Object?>();
    final data = dataRaw.cast<String, Object?>();
    if (metadata['app_name'] != FullBackupService.appName ||
        metadata['export_mode'] != FullBackupService.exportModeFullBackup) {
      return _invalid(filePath, fileName, '不是 my_finance_app 完整備份檔。');
    }

    final exportVersion = _intValue(metadata['export_format_version']);
    if (exportVersion == null ||
        !FullBackupScope.supportedExportFormatVersions.contains(exportVersion)) {
      return _invalid(filePath, fileName, '不支援的備份格式版本。');
    }
    final schemaVersion = _intValue(metadata['database_schema_version']);
    if (schemaVersion == null) {
      return _invalid(filePath, fileName, '備份檔 schema version 格式錯誤。');
    }
    if (schemaVersion > FullBackupService.databaseSchemaVersion) {
      return _invalid(filePath, fileName, '備份檔 schema version 高於目前 App 支援版本。');
    }
    for (final tableName in FullBackupScope.requiredTableNames) {
      if (data[tableName] is! List) {
        return _invalid(filePath, fileName, '備份檔缺少必要核心表 $tableName。');
      }
    }
    if (exportVersion >= 2) {
      final error = _validateCoverage(metadata, data);
      if (error != null) return _invalid(filePath, fileName, error);
    }

    final counts = <String, int>{};
    for (final entry in data.entries) {
      if (entry.value is List) counts[entry.key] = (entry.value! as List).length;
    }
    final impacts = currentDb == null
        ? const <FullRestoreTableImpact>[]
        : await impactService.buildTableImpacts(
            currentDb: currentDb,
            backupTableCounts: counts,
          );
    return FullRestoreBackupPreview(
      filePath: filePath,
      fileName: fileName,
      isValid: true,
      message: exportVersion >= 2
          ? '完整備份範圍已驗證；本階段不會執行還原或覆蓋目前資料。'
          : '舊版 V1 備份可預覽；正式還原前仍會驗證並要求確認。',
      metadata: FullRestoreBackupMetadata(
        appName: _stringValue(metadata['app_name']),
        appVersion: _stringValue(metadata['app_version']),
        phase: _stringValue(metadata['phase']),
        exportFormatVersion: exportVersion,
        databaseSchemaVersion: schemaVersion,
        createdAt: _stringValue(metadata['created_at']),
        sourcePlatform: _stringValue(metadata['source_platform']),
        exportMode: _stringValue(metadata['export_mode']),
        backupScopeVersion: _intValue(metadata['backup_scope_version']),
        coverageComplete: metadata['coverage_complete'] is bool
            ? metadata['coverage_complete']! as bool
            : null,
      ),
      tableRowCounts: counts,
      tableImpacts: impacts,
    );
  }

  String? _validateCoverage(
    Map<String, Object?> metadata,
    Map<String, Object?> data,
  ) {
    final scopeVersion = _intValue(metadata['backup_scope_version']);
    if (scopeVersion == null ||
        !FullBackupScope.supportedBackupScopeVersions.contains(scopeVersion)) {
      return '不支援的完整備份範圍版本。';
    }
    if (metadata['coverage_complete'] != true) {
      return '完整備份範圍未通過完整性驗證。';
    }
    final unknown = metadata['unknown_tables'];
    final missing = metadata['missing_required_tables'];
    final included = metadata['included_tables'];
    if (unknown is! List || unknown.isNotEmpty) {
      return '完整備份包含未知資料表狀態。';
    }
    if (missing is! List || missing.isNotEmpty) {
      return '完整備份缺少必要資料表。';
    }
    if (included is! List) return '完整備份缺少 included_tables。';

    final expected = switch (scopeVersion) {
      2 => FullBackupScope.legacyScopeV2TableNames,
      3 => FullBackupScope.legacyScopeV3TableNames,
      4 => FullBackupScope.legacyScopeV4TableNames,
      5 => FullBackupScope.legacyScopeV5TableNames,
      6 => FullBackupScope.legacyScopeV6TableNames,
      _ => FullBackupService.backupTableNames,
    };
    if (!included.whereType<String>().toSet().containsAll(expected)) {
      return '完整備份受管資料表清單不完整。';
    }
    for (final tableName in expected) {
      if (!data.containsKey(tableName) || data[tableName] is! List) {
        return '完整備份 V2 缺少資料表陣列：$tableName。';
      }
    }
    return null;
  }

  FullRestoreBackupPreview _invalid(
    String filePath,
    String fileName,
    String message,
  ) => FullRestoreBackupPreview(
        filePath: filePath,
        fileName: fileName,
        isValid: false,
        message: message,
        metadata: null,
        tableRowCounts: const {},
      );

  String _stringValue(Object? value) => value?.toString() ?? '';

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class FullRestoreImpactPreviewService {
  const FullRestoreImpactPreviewService();

  Future<List<FullRestoreTableImpact>> buildTableImpacts({
    required DatabaseExecutor currentDb,
    required Map<String, int> backupTableCounts,
  }) async {
    final tableNames = backupTableCounts.keys.toList()..sort();
    final impacts = <FullRestoreTableImpact>[];
    for (final tableName in tableNames) {
      final currentCount = await _currentRowCount(currentDb, tableName);
      final backupCount = backupTableCounts[tableName] ?? 0;
      final delta = backupCount - currentCount;
      impacts.add(FullRestoreTableImpact(
        tableName: tableName,
        currentCount: currentCount,
        backupCount: backupCount,
        delta: delta,
        level: _impactLevel(
          currentCount: currentCount,
          backupCount: backupCount,
          delta: delta,
        ),
      ));
    }
    return impacts;
  }

  Future<int> _currentRowCount(
    DatabaseExecutor db,
    String tableName,
  ) async {
    if (!await _tableExists(db, tableName)) return 0;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    final count = rows.first['c'];
    if (count is int) return count;
    if (count is num) return count.toInt();
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  FullRestoreImpactLevel _impactLevel({
    required int currentCount,
    required int backupCount,
    required int delta,
  }) {
    if (delta == 0) return FullRestoreImpactLevel.none;
    final absDelta = delta.abs();
    final base = currentCount == 0 ? backupCount : currentCount;
    if (base == 0) return FullRestoreImpactLevel.none;
    final ratio = absDelta / base;
    if (ratio < 0.1 && absDelta <= 10) return FullRestoreImpactLevel.low;
    if (ratio < 0.5 && absDelta <= 100) {
      return FullRestoreImpactLevel.medium;
    }
    return FullRestoreImpactLevel.high;
  }
}
