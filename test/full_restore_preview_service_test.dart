import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_restore_preview_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('FullRestorePreviewService previews valid full backup metadata and table counts', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('restore_preview_valid_');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final file = File('${tempDirectory.path}/backup.json');
    await file.writeAsString(jsonEncode(<String, Object?>{
      'metadata': <String, Object?>{
        'export_format_version': 1,
        'app_name': 'my_finance_app',
        'app_version': '3.5.2+148',
        'phase': 'P3.5.2',
        'database_schema_version': 12,
        'created_at': '2026-06-02T01:02:03.000Z',
        'source_platform': 'android',
        'export_mode': 'full_backup',
      },
      'data': <String, Object?>{
        'accounts': <Object?>[
          <String, Object?>{'id': 'cash'},
          <String, Object?>{'id': 'card'},
        ],
        'transactions': <Object?>[
          <String, Object?>{'id': 'tx-1'},
        ],
      },
    }));

    final preview = await const FullRestorePreviewService().previewFile(file);

    expect(preview.isValid, isTrue);
    expect(preview.fileName, 'backup.json');
    expect(preview.metadata!.appName, 'my_finance_app');
    expect(preview.metadata!.appVersion, '3.5.2+148');
    expect(preview.metadata!.databaseSchemaVersion, 12);
    expect(preview.metadata!.sourcePlatform, 'android');
    expect(preview.tableRowCounts['accounts'], 2);
    expect(preview.tableRowCounts['transactions'], 1);
    expect(preview.tableImpacts, isEmpty);
  });

  test('FullRestorePreviewService builds table count impacts when current db is provided', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
    await db.insert('accounts', <String, Object?>{'id': 'cash'});
    final tempDirectory = await Directory.systemTemp.createTemp('restore_preview_impact_');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final file = File('${tempDirectory.path}/backup.json')..writeAsStringSync(_validBackupJson('impact'));

    final preview = await const FullRestorePreviewService().previewFile(file, currentDb: db);

    expect(preview.isValid, isTrue);
    final accounts = preview.tableImpacts.singleWhere((impact) => impact.tableName == 'accounts');
    final transactions = preview.tableImpacts.singleWhere((impact) => impact.tableName == 'transactions');
    expect(accounts.currentCount, 1);
    expect(accounts.backupCount, 2);
    expect(accounts.delta, 1);
    expect(accounts.level, FullRestoreImpactLevel.high);
    expect(transactions.currentCount, 0);
    expect(transactions.backupCount, 1);
    expect(transactions.delta, 1);
    expect(transactions.level, FullRestoreImpactLevel.high);
  });

  test('FullRestorePreviewService marks invalid JSON and non-backup JSON as invalid', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('restore_preview_invalid_');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final invalidJson = File('${tempDirectory.path}/invalid.json')..writeAsStringSync('{not json');
    final wrongMode = File('${tempDirectory.path}/wrong.json')
      ..writeAsStringSync(jsonEncode(<String, Object?>{
        'metadata': <String, Object?>{'app_name': 'my_finance_app', 'export_mode': 'readable_json'},
        'data': <String, Object?>{},
      }));

    final invalidPreview = await const FullRestorePreviewService().previewFile(invalidJson);
    final wrongPreview = await const FullRestorePreviewService().previewFile(wrongMode);

    expect(invalidPreview.isValid, isFalse);
    expect(invalidPreview.message, contains('無法解析備份檔'));
    expect(invalidPreview.tableImpacts, isEmpty);
    expect(wrongPreview.isValid, isFalse);
    expect(wrongPreview.message, contains('不是 my_finance_app 完整備份檔'));
    expect(wrongPreview.tableImpacts, isEmpty);
  });

  test('FullRestorePreviewService marks invalid JSON bytes as invalid', () async {
    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode('{not json')),
      sourceUri: 'provider:invalid.json',
      fileName: 'invalid.json',
    );

    expect(preview.isValid, isFalse);
    expect(preview.message, contains('無法解析備份檔'));
    expect(preview.tableImpacts, isEmpty);
  });

  test('FullRestorePreviewService scans json files only and sorts newest first', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('restore_preview_scan_');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final older = File('${tempDirectory.path}/older.json')..writeAsStringSync(_validBackupJson('older'));
    final newer = File('${tempDirectory.path}/newer.json')..writeAsStringSync(_validBackupJson('newer'));
    File('${tempDirectory.path}/note.txt').writeAsStringSync('ignored');
    older.setLastModifiedSync(DateTime(2026, 1, 1));
    newer.setLastModifiedSync(DateTime(2026, 1, 2));

    final previews = await const FullRestorePreviewService().scanSourceDirectory(tempDirectory);

    expect(previews, hasLength(2));
    expect(previews.first.fileName, 'newer.json');
    expect(previews.last.fileName, 'older.json');
  });
}

String _validBackupJson(String id) {
  return jsonEncode(<String, Object?>{
    'metadata': <String, Object?>{
      'export_format_version': 1,
      'app_name': 'my_finance_app',
      'app_version': id,
      'phase': 'P3.5.2',
      'database_schema_version': 12,
      'created_at': '2026-06-02T01:02:03.000Z',
      'source_platform': 'android',
      'export_mode': 'full_backup',
    },
    'data': <String, Object?>{
      'accounts': <Object?>[
        <String, Object?>{'id': 'cash'},
        <String, Object?>{'id': 'card'},
      ],
      'transactions': <Object?>[
        <String, Object?>{'id': 'tx-1'},
      ],
    },
  });
}
