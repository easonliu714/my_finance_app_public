import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'file_exchange_service.dart';
import 'full_backup_service.dart';
import 'full_restore_preview_service.dart';
import 'full_restore_service.dart';
import 'full_restore_service_v7.dart';
import 'readable_export_service.dart';
import 'readable_import_source_service.dart';
import 'restore_source_grant.dart';

class BackupMigrationActionResult {
  const BackupMigrationActionResult({required this.filePath, required this.message});

  final String filePath;
  final String message;
}

class FullRestoreCommitActionResult {
  const FullRestoreCommitActionResult({required this.message, required this.preRestoreBackupPath});

  final String message;
  final String? preRestoreBackupPath;
}

class SafeImportSourceResult {
  const SafeImportSourceResult({
    required this.directoryPath,
    required this.title,
    required this.message,
    required this.allowedExtensions,
    this.restorePreviews = const <FullRestoreBackupPreview>[],
    this.readableImportCandidates = const <ReadableImportSourceCandidate>[],
    this.restoreSourceGrant,
  });

  final String directoryPath;
  final String title;
  final String message;
  final List<String> allowedExtensions;
  final List<FullRestoreBackupPreview> restorePreviews;
  final List<ReadableImportSourceCandidate> readableImportCandidates;
  final RestoreSourceGrant? restoreSourceGrant;
}

class BackupMigrationActionService {
  const BackupMigrationActionService({
    this.fullBackupService = const FullBackupService(),
    this.fullRestoreService = const FullRestoreServiceV7(),
    this.readableExportService = const ReadableExportService(),
    this.restorePreviewService = const FullRestorePreviewService(),
    this.readableImportSourceService = const ReadableImportSourceService(),
    this.fileExchange = const PlatformFileExchangeService(),
  });

  final FullBackupService fullBackupService;
  final FullRestoreService fullRestoreService;
  final ReadableExportService readableExportService;
  final FullRestorePreviewService restorePreviewService;
  final ReadableImportSourceService readableImportSourceService;
  final FileExchangePort fileExchange;

  Future<BackupMigrationActionResult> createAndShareFullBackup(DatabaseExecutor db, {Directory? baseDirectory}) async {
    final file = await fullBackupService.writeFullBackupFile(db, baseDirectory: baseDirectory, sourcePlatform: Platform.operatingSystem);
    final shared = await fileExchange.shareFile(file: file, subject: 'My Finance App 完整備份', text: '完整備份檔案，請妥善保存。');
    return BackupMigrationActionResult(filePath: shared.path, message: shared.message);
  }

  Future<FullRestoreCommitActionResult> commitFullRestoreFromPreview(Database db, FullRestoreBackupPreview preview, {required String confirmationText, Directory? baseDirectory}) async {
    if (!preview.isValid || preview.metadata == null) {
      throw const FullRestoreException('此候選檔不可用，無法執行完整還原。');
    }
    final file = File(preview.filePath);
    if (!file.existsSync()) {
      throw FullRestoreException('找不到完整備份來源檔：${preview.filePath}');
    }
    final result = await fullRestoreService.restoreFromJson(
      db,
      await file.readAsString(),
      confirmationText: confirmationText,
      sourcePlatform: Platform.operatingSystem,
      preRestoreBackupCreatedAt: DateTime.now().toUtc(),
      persistPreRestoreBackup: (envelope) => _writePreRestoreBackupEnvelope(envelope, baseDirectory: baseDirectory),
    );
    final warningSuffix = result.audit.warningIssues.isEmpty ? '' : '；警告 ${result.audit.warningIssues.length} 項非阻斷追溯參照不完整';
    return FullRestoreCommitActionResult(
      preRestoreBackupPath: result.preRestoreBackupPath,
      message: result.preRestoreBackupPath == null ? '完整還原已完成$warningSuffix。' : '完整還原已完成；還原前備份已建立：${result.preRestoreBackupPath}$warningSuffix',
    );
  }

  Future<BackupMigrationActionResult> exportAndShareTransactionsJson(DatabaseExecutor db, {Directory? baseDirectory}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final file = await readableExportService.writeTransactionsJsonFile(db, baseDirectory: root);
    final shared = await fileExchange.shareFile(file: file, subject: 'My Finance App readable transactions JSON', text: '人類可讀交易匯出 JSON。');
    return BackupMigrationActionResult(filePath: shared.path, message: shared.message);
  }

  Future<BackupMigrationActionResult> exportAndShareTransactionsCsv(DatabaseExecutor db, {Directory? baseDirectory}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final file = await readableExportService.writeTransactionsCsvFile(db, baseDirectory: root);
    final shared = await fileExchange.shareFile(file: file, subject: 'My Finance App readable transactions CSV', text: '人類可讀交易匯出 CSV。');
    return BackupMigrationActionResult(filePath: shared.path, message: shared.message);
  }

  Future<String?> pickFullRestoreFilePath() {
    return fileExchange.pickOpenFilePath(allowedExtensions: const <String>['json']);
  }

  Future<String?> pickReadableImportFilePath() {
    return fileExchange.pickOpenFilePath(allowedExtensions: const <String>['json', 'csv']);
  }

  Future<RestoreSourcePickResult?> pickRestoreSource() {
    return fileExchange.pickRestoreSource(allowedExtensions: const <String>['json']);
  }

  Future<RestoreSourcePickResult?> pickReadableImportSource() {
    return fileExchange.pickReadableImportSource(allowedExtensions: const <String>['json', 'csv']);
  }

  Future<SafeImportSourceResult> prepareFullRestoreSource({Directory? baseDirectory, DatabaseExecutor? currentDb}) async {
    final directory = await _ensureImportSourceDirectory('full_restore', baseDirectory: baseDirectory);
    final previews = await restorePreviewService.scanSourceDirectory(directory, currentDb: currentDb);
    return SafeImportSourceResult(
      directoryPath: directory.path,
      title: '完整還原來源',
      allowedExtensions: const <String>['json'],
      restorePreviews: previews,
      message: '請選擇完整備份 JSON。預覽不會修改目前資料；正式還原前會再次確認並建立還原前備份。',
    );
  }

  Future<SafeImportSourceResult> prepareFullRestoreSourceFromPickResult(RestoreSourcePickResult result, {DatabaseExecutor? currentDb}) async {
    if (result.hasPreviewBytes) {
      final preview = await restorePreviewService.previewBytes(
        result.bytes!,
        sourceUri: result.grant.uri,
        fileName: result.grant.displayName,
        currentDb: currentDb,
      );
      return SafeImportSourceResult(
        directoryPath: result.grant.uri,
        title: '完整還原來源',
        allowedExtensions: const <String>['json'],
        restorePreviews: <FullRestoreBackupPreview>[preview],
        restoreSourceGrant: result.grant,
        message: '已讀取完整備份 JSON。預覽不會修改目前資料；正式還原前會要求輸入 RESTORE。',
      );
    }
    return prepareFullRestoreSourceFromGrant(result.grant, currentDb: currentDb);
  }

  Future<SafeImportSourceResult> prepareFullRestoreSourceFromGrant(RestoreSourceGrant grant, {DatabaseExecutor? currentDb}) async {
    if (!grant.pathBacked || grant.uri.isEmpty) {
      return SafeImportSourceResult(
        directoryPath: grant.uri,
        title: '完整還原來源',
        allowedExtensions: const <String>['json'],
        restoreSourceGrant: grant,
        message: '已取得來源授權，但目前 provider 未提供可預覽的檔案路徑或本次可用 bytes。請重新選擇可供 App 讀取的完整備份 JSON。',
      );
    }
    final file = File(grant.uri);
    final preview = await restorePreviewService.previewFile(file, currentDb: currentDb);
    return SafeImportSourceResult(
      directoryPath: grant.uri,
      title: '完整還原來源',
      allowedExtensions: const <String>['json'],
      restorePreviews: <FullRestoreBackupPreview>[preview],
      restoreSourceGrant: grant,
      message: '已讀取完整備份 JSON。預覽不會修改目前資料；正式還原前會要求輸入 RESTORE。',
    );
  }

  Future<SafeImportSourceResult> prepareReadableImportSource({Directory? baseDirectory, DatabaseExecutor? currentDb}) async {
    final directory = await _ensureImportSourceDirectory('readable_import', baseDirectory: baseDirectory);
    final candidates = await readableImportSourceService.scanSourceDirectory(directory, currentDb: currentDb);
    return SafeImportSourceResult(
      directoryPath: directory.path,
      title: 'readable 匯入來源',
      allowedExtensions: const <String>['json', 'csv'],
      readableImportCandidates: candidates,
      message: '請選擇 readable JSON 或 CSV。此模式只處理交易資料，匯入前可逐筆檢視。',
    );
  }

  Future<SafeImportSourceResult> prepareReadableImportSourceFromPickResult(RestoreSourcePickResult result, {DatabaseExecutor? currentDb}) async {
    if (result.hasPreviewBytes) {
      final candidate = await readableImportSourceService.previewBytes(
        result.bytes!,
        sourceUri: result.grant.uri,
        fileName: result.grant.displayName,
        currentDb: currentDb,
      );
      return SafeImportSourceResult(
        directoryPath: result.grant.uri,
        title: 'readable 匯入來源',
        allowedExtensions: const <String>['json', 'csv'],
        readableImportCandidates: <ReadableImportSourceCandidate>[candidate],
        restoreSourceGrant: result.grant,
        message: '已讀取 readable 匯入檔。此模式只處理交易資料，匯入前可逐筆檢視。',
      );
    }
    final path = result.path ?? result.grant.uri;
    return prepareReadableImportSourceFromPath(path, currentDb: currentDb, displayName: result.grant.displayName);
  }

  Future<SafeImportSourceResult> prepareReadableImportSourceFromPath(String filePath, {DatabaseExecutor? currentDb, String? displayName}) async {
    final file = File(filePath);
    final candidate = displayName == null ? await readableImportSourceService.previewFile(file, currentDb: currentDb) : await readableImportSourceService.previewText(await file.readAsString(), sourceUri: filePath, fileName: displayName, fileSizeBytes: file.existsSync() ? file.lengthSync() : 0, currentDb: currentDb);
    return SafeImportSourceResult(
      directoryPath: filePath,
      title: 'readable 匯入來源',
      allowedExtensions: const <String>['json', 'csv'],
      readableImportCandidates: <ReadableImportSourceCandidate>[candidate],
      message: '已讀取 readable 匯入檔。此模式只處理交易資料，匯入前可逐筆檢視。',
    );
  }

  Future<String> _writePreRestoreBackupEnvelope(Map<String, Object?> envelope, {Directory? baseDirectory}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'pre_restore_backups'));
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final createdAt = envelope['metadata'] is Map ? ((envelope['metadata']! as Map)['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String()) : DateTime.now().toUtc().toIso8601String();
    final safeTimestamp = createdAt.replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-');
    final file = File(p.join(directory.path, 'pre_restore_backup_$safeTimestamp.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(envelope));
    return file.path;
  }

  Future<Directory> _ensureImportSourceDirectory(String childName, {Directory? baseDirectory}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'import_sources', childName));
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return directory;
  }
}
