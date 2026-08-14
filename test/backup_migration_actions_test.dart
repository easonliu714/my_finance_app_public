import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_migration_actions.dart';
import 'package:my_finance_app/features/backup/file_exchange_service.dart';
import 'package:my_finance_app/features/backup/restore_source_grant.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'BackupMigrationActionService creates and shares full backup file through abstraction',
    () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE transactions (id TEXT PRIMARY KEY, amount REAL NOT NULL)',
      );
      await db.insert(
        'accounts',
        <String, Object?>{'id': 'cash', 'name': '現金'},
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'my_finance_actions_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final exchange = _FakeFileExchange();

      final result = await BackupMigrationActionService(
        fileExchange: exchange,
      ).createAndShareFullBackup(db, baseDirectory: tempDirectory);

      expect(result.filePath, exchange.sharedPath);
      expect(result.message, contains('fake shared'));
      expect(exchange.sharedPath, isNotNull);
      expect(File(exchange.sharedPath!).existsSync(), isTrue);
      expect(exchange.sharedSubject, 'My Finance App 完整備份');
    },
  );

  test(
    'BackupMigrationActionService creates and shares readable transactions JSON',
    () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          occurred_at TEXT NOT NULL,
          amount REAL NOT NULL,
          created_at TEXT
        )
      ''');
      await db.insert(
        'transactions',
        <String, Object?>{
          'id': 'tx-1',
          'type': 'expense',
          'occurred_at': '2026-06-01T08:00:00.000',
          'amount': 150,
          'created_at': '2026-06-01T08:05:00.000',
        },
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'my_finance_actions_export_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final exchange = _FakeFileExchange();

      final result = await BackupMigrationActionService(
        fileExchange: exchange,
      ).exportAndShareTransactionsJson(db, baseDirectory: tempDirectory);

      expect(result.filePath, exchange.sharedPath);
      expect(exchange.sharedPath, endsWith('.json'));
      expect(File(exchange.sharedPath!).readAsStringSync(), contains('tx-1'));
      expect(exchange.sharedSubject, contains('readable transactions JSON'));
    },
  );

  test(
    'BackupMigrationActionService exposes safe file pickers without side effects',
    () async {
      final exchange = _FakeFileExchange(pickedPath: '/tmp/import.csv');
      final service = BackupMigrationActionService(fileExchange: exchange);

      final importPath = await service.pickReadableImportFilePath();
      final restorePath = await service.pickFullRestoreFilePath();

      expect(importPath, '/tmp/import.csv');
      expect(restorePath, '/tmp/import.csv');
      expect(
        exchange.pickAllowedExtensionsLog,
        containsAll(<List<String>>[
          <String>['json', 'csv'],
          <String>['json'],
        ]),
      );
    },
  );

  test('BackupMigrationActionService picks restore source grant', () async {
    final exchange = _FakeFileExchange(
      restorePickResult: RestoreSourcePickResult(
        path: '/cloud/backup.json',
        grant: RestoreSourceGrant(
          uri: '/cloud/backup.json',
          displayName: 'backup.json',
          grantedAt: DateTime.utc(2026, 6, 4),
        ),
      ),
    );
    final service = BackupMigrationActionService(fileExchange: exchange);

    final result = await service.pickRestoreSource();

    expect(result, isNotNull);
    expect(result!.path, '/cloud/backup.json');
    expect(result.grant.displayName, 'backup.json');
    expect(
      exchange.restorePickAllowedExtensionsLog.single,
      <String>['json'],
    );
  });

  test('BackupMigrationActionService picks readable import source grant', () async {
    final exchange = _FakeFileExchange(
      readablePickResult: RestoreSourcePickResult(
        path: '/cloud/readable.json',
        grant: RestoreSourceGrant(
          uri: '/cloud/readable.json',
          displayName: 'readable.json',
          grantedAt: DateTime.utc(2026, 6, 8),
        ),
      ),
    );
    final service = BackupMigrationActionService(fileExchange: exchange);

    final result = await service.pickReadableImportSource();

    expect(result, isNotNull);
    expect(result!.path, '/cloud/readable.json');
    expect(result.grant.displayName, 'readable.json');
    expect(
      exchange.readablePickAllowedExtensionsLog.single,
      <String>['json', 'csv'],
    );
  });

  test(
    'BackupMigrationActionService previews pathless restore source from bytes',
    () async {
      final pickResult = RestoreSourcePickResult(
        bytes: Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'metadata': <String, Object?>{
                'app_name': 'my_finance_app',
                'app_version': '3.8.2+205',
                'phase': 'P3.8.2',
                'export_format_version': 1,
                'database_schema_version': 12,
                'created_at': '2026-06-05T00:00:00.000Z',
                'source_platform': 'android',
                'export_mode': 'full_backup',
              },
              'data': <String, Object?>{
                'accounts': <Object?>[
                  <String, Object?>{'id': 'cash'},
                  <String, Object?>{'id': 'bank'},
                ],
                'transactions': <Object?>[],
              },
            }),
          ),
        ),
        grant: RestoreSourceGrant(
          uri: 'provider:drive-backup.json',
          displayName: 'drive-backup.json',
          grantedAt: DateTime.utc(2026, 6, 5),
          pathBacked: false,
        ),
      );
      const service = BackupMigrationActionService();

      final result = await service.prepareFullRestoreSourceFromPickResult(
        pickResult,
      );

      expect(result.restoreSourceGrant, pickResult.grant);
      expect(result.restorePreviews, hasLength(1));
      expect(result.restorePreviews.single.isValid, isTrue);
      expect(result.restorePreviews.single.metadata?.appVersion, '3.8.2+205');
      expect(result.restorePreviews.single.tableRowCounts['accounts'], 2);
      expect(result.message, contains('不會修改目前資料'));
      expect(result.message, contains('RESTORE'));
    },
  );

  test(
    'BackupMigrationActionService handles pathless restore source grant as non-previewable fallback',
    () async {
      final grant = RestoreSourceGrant(
        uri: 'provider:drive-backup.json',
        displayName: 'drive-backup.json',
        grantedAt: DateTime.utc(2026, 6, 4),
        pathBacked: false,
      );
      const service = BackupMigrationActionService();

      final result = await service.prepareFullRestoreSourceFromGrant(grant);

      expect(result.restoreSourceGrant, grant);
      expect(result.restorePreviews, isEmpty);
      expect(result.message, contains('未提供可預覽'));
      expect(result.message, contains('重新選擇'));
    },
  );

  test(
    'BackupMigrationActionService prepares safe restore and readable import source directories',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'my_finance_safe_source_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      const service = BackupMigrationActionService();

      final restore = await service.prepareFullRestoreSource(
        baseDirectory: tempDirectory,
      );
      final readable = await service.prepareReadableImportSource(
        baseDirectory: tempDirectory,
      );

      expect(Directory(restore.directoryPath).existsSync(), isTrue);
      expect(Directory(readable.directoryPath).existsSync(), isTrue);
      expect(restore.directoryPath, contains('import_sources/full_restore'));
      expect(readable.directoryPath, contains('import_sources/readable_import'));
      expect(restore.allowedExtensions, <String>['json']);
      expect(readable.allowedExtensions, <String>['json', 'csv']);
      expect(restore.message, contains('預覽不會修改目前資料'));
      expect(readable.message, contains('只處理交易資料'));
      expect(readable.message, contains('逐筆檢視'));
    },
  );
}

class _FakeFileExchange implements FileExchangePort {
  _FakeFileExchange({
    this.pickedPath,
    this.restorePickResult,
    this.readablePickResult,
  });

  final String? pickedPath;
  final RestoreSourcePickResult? restorePickResult;
  final RestoreSourcePickResult? readablePickResult;
  String? sharedPath;
  String? sharedSubject;
  final List<List<String>> pickAllowedExtensionsLog = <List<String>>[];
  final List<List<String>> restorePickAllowedExtensionsLog = <List<String>>[];
  final List<List<String>> readablePickAllowedExtensionsLog = <List<String>>[];

  @override
  Future<FileExchangeResult> shareFile({
    required File file,
    required String subject,
    String? text,
  }) async {
    sharedPath = file.path;
    sharedSubject = subject;
    return FileExchangeResult(
      path: file.path,
      message: 'fake shared ${file.path}',
    );
  }

  @override
  Future<String?> pickOpenFilePath({List<String>? allowedExtensions}) async {
    pickAllowedExtensionsLog.add(
      List<String>.from(allowedExtensions ?? const <String>[]),
    );
    return pickedPath;
  }

  @override
  Future<RestoreSourcePickResult?> pickRestoreSource({
    List<String>? allowedExtensions,
  }) async {
    restorePickAllowedExtensionsLog.add(
      List<String>.from(allowedExtensions ?? const <String>[]),
    );
    return restorePickResult;
  }

  @override
  Future<RestoreSourcePickResult?> pickReadableImportSource({
    List<String>? allowedExtensions,
  }) async {
    readablePickAllowedExtensionsLog.add(
      List<String>.from(allowedExtensions ?? const <String>[]),
    );
    return readablePickResult;
  }
}
