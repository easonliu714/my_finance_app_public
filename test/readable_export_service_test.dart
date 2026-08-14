import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/readable_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReadableExportService', () {
    test('exports transactions CSV with stable header and escaped values', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createReadableExportTables(db);
      await _insertReadableRows(db);

      final csv = await const ReadableExportService().exportTransactionsCsv(db);

      expect(csv, startsWith('${ReadableExportService.transactionCsvColumns.join(',')}\n'));
      expect(csv, contains('tx-1'));
      expect(csv, contains('expense'));
      expect(csv, contains('"商家,含逗號"'));
      expect(csv, contains('"早餐""備註\n第二行"'));
    });

    test('exports transactions JSON with metadata and rows', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createReadableExportTables(db);
      await _insertReadableRows(db);

      final jsonText = await const ReadableExportService().exportTransactionsJson(db);
      final decoded = jsonDecode(jsonText) as Map<String, Object?>;
      final metadata = decoded['metadata']! as Map<String, Object?>;
      final data = decoded['data']! as List<dynamic>;

      expect(metadata['export_type'], 'transactions');
      expect(metadata['app_version'], '3.3.0+125');
      expect(metadata['phase'], 'P3.3');
      expect(data, hasLength(1));
      expect((data.single as Map<String, Object?>)['id'], 'tx-1');
    });

    test('exports accounts JSON for human audit', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createReadableExportTables(db);
      await _insertReadableRows(db);

      final jsonText = await const ReadableExportService().exportAccountsJson(db);
      final decoded = jsonDecode(jsonText) as Map<String, Object?>;
      final metadata = decoded['metadata']! as Map<String, Object?>;
      final data = decoded['data']! as List<dynamic>;

      expect(metadata['export_type'], 'accounts');
      expect(data, hasLength(1));
      expect((data.single as Map<String, Object?>)['name'], '信用卡');
    });

    test('writes readable export files under readable_exports directory', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createReadableExportTables(db);
      await _insertReadableRows(db);
      final tempDirectory = await Directory.systemTemp.createTemp('my_finance_readable_export_test_');
      addTearDown(() => tempDirectory.delete(recursive: true));

      final csvFile = await const ReadableExportService().writeTransactionsCsvFile(
        db,
        baseDirectory: tempDirectory,
        createdAt: DateTime.utc(2026, 6, 2, 1, 2),
      );
      final jsonFile = await const ReadableExportService().writeTransactionsJsonFile(
        db,
        baseDirectory: tempDirectory,
        createdAt: DateTime.utc(2026, 6, 2, 1, 3),
      );

      expect(csvFile.existsSync(), isTrue);
      expect(jsonFile.existsSync(), isTrue);
      expect(csvFile.path, contains('/readable_exports/'));
      expect(jsonFile.path, contains('/readable_exports/'));
      expect(csvFile.path, endsWith('.csv'));
      expect(jsonFile.path, endsWith('.json'));
      expect(await csvFile.readAsString(), contains('tx-1'));
      expect(await jsonFile.readAsString(), contains('tx-1'));
    });

    test('missing tables export empty CSV or JSON data without crash', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      final csv = await const ReadableExportService().exportTransactionsCsv(db);
      final transactionsJson = jsonDecode(await const ReadableExportService().exportTransactionsJson(db)) as Map<String, Object?>;
      final accountsJson = jsonDecode(await const ReadableExportService().exportAccountsJson(db)) as Map<String, Object?>;

      expect(csv.trim(), ReadableExportService.transactionCsvColumns.join(','));
      expect(transactionsJson['data'], isEmpty);
      expect(accountsJson['data'], isEmpty);
    });
  });
}

Future<void> _createReadableExportTables(Database db) async {
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT,
      base_amount REAL,
      category TEXT,
      account_name TEXT,
      from_account_name TEXT,
      to_account_name TEXT,
      member_name TEXT,
      merchant_name TEXT,
      tag_name TEXT,
      note TEXT,
      repayment_group_id TEXT,
      created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      suffix TEXT NOT NULL DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

Future<void> _insertReadableRows(Database db) async {
  await db.insert('accounts', <String, Object?>{
    'id': 'card-1',
    'name': '信用卡',
    'type': 'creditCard',
    'suffix': '1234',
    'sort_order': 1,
  });
  await db.insert('transactions', <String, Object?>{
    'id': 'tx-1',
    'type': 'expense',
    'occurred_at': '2026-06-01T08:00:00.000',
    'amount': 150,
    'currency_code': 'TWD',
    'base_amount': 150,
    'category': '早餐',
    'account_name': '信用卡',
    'from_account_name': null,
    'to_account_name': null,
    'member_name': '我',
    'merchant_name': '商家,含逗號',
    'tag_name': '日常',
    'note': '早餐"備註\n第二行',
    'repayment_group_id': 'repay-1',
    'created_at': '2026-06-01T08:05:00.000',
  });
}
