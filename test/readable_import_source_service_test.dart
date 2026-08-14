import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/readable_import_source_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReadableImportSourceService', () {
    test('infers json for Android picker file name without extension', () async {
      final tempDir = await Directory.systemTemp.createTemp('readable_source_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final file = File('${tempDir.path}/My Finance App readable transactions JSON');
      await file.writeAsString(jsonEncode(<String, Object?>{
        'metadata': <String, Object?>{'export_type': 'transactions'},
        'data': <Map<String, Object?>>[
          <String, Object?>{'id': 'tx-json-1', 'type': 'expense', 'occurred_at': '2026-06-07T08:00:00.000', 'amount': 120},
        ],
      }));
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);

      final candidate = await const ReadableImportSourceService().previewFile(file, currentDb: db);

      expect(candidate.format, ReadableImportSourceFormat.json);
      expect(candidate.isValid, isTrue);
      expect(candidate.dryRunResult, isNotNull);
      expect(candidate.dryRunResult?.readyToInsertRows, 1);
    });

    test('infers csv for extensionless content with transaction header', () async {
      final tempDir = await Directory.systemTemp.createTemp('readable_source_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final file = File('${tempDir.path}/transactions_export');
      await file.writeAsString('id,type,occurred_at,amount\ntx-csv-1,expense,2026-06-07T08:00:00.000,120');
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);

      final candidate = await const ReadableImportSourceService().previewFile(file, currentDb: db);

      expect(candidate.format, ReadableImportSourceFormat.csv);
      expect(candidate.isValid, isTrue);
      expect(candidate.dryRunResult?.readyToInsertRows, 1);
    });
  });
}

Future<void> _createTransactionTable(Database db) async {
  await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY, type TEXT, occurred_at TEXT, amount REAL)');
}
