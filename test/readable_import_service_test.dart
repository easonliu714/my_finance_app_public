import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReadableImportService', () {
    test('dry-runs P3.3 CSV with ready, duplicate, and invalid rows', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);
      await _insertExistingTransaction(db);

      final csv = [
        'id,type,occurred_at,amount,currency_code,base_amount,category,account_name,from_account_name,to_account_name,member_name,merchant_name,tag_name,note,repayment_group_id,created_at',
        'tx-new,expense,2026-06-01T08:00:00.000,150,TWD,150,早餐,信用卡,,,我,"商家,含逗號",日常,"早餐""備註\n第二行",,2026-06-01T08:05:00.000',
        'tx-existing,expense,2026-06-01T08:00:00.000,200,TWD,200,午餐,現金,,,我,便當店,日常,,repay-1,2026-06-01T08:05:00.000',
        'tx-bad,expense,not-date,abc,TWD,abc,晚餐,現金,,,我,夜市,日常,,,2026-06-01T08:05:00.000',
      ].join('\n');

      final result = await const ReadableImportService().dryRunTransactionsCsv(db, csv);

      expect(result.totalRows, 3);
      expect(result.validRows, 2);
      expect(result.invalidRows, 1);
      expect(result.duplicateRows, 1);
      expect(result.readyToInsertRows, 1);
      expect(result.rows[0].status, ReadableImportRowStatus.readyToInsert);
      expect(result.rows[0].row['merchant_name'], '商家,含逗號');
      expect(result.rows[0].row['note'], '早餐"備註\n第二行');
      expect(result.rows[1].status, ReadableImportRowStatus.duplicate);
      expect(result.rows[2].status, ReadableImportRowStatus.invalid);
      expect(result.rows[2].errors, contains('amount 不是有效數字'));
      expect(result.rows[2].errors, contains('occurred_at 不是有效日期'));
    });

    test('dry-runs P3.3 transactions JSON', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);

      final jsonText = jsonEncode(<String, Object?>{
        'metadata': <String, Object?>{'export_type': 'transactions'},
        'data': <Map<String, Object?>>[
          <String, Object?>{'id': 'json-1', 'type': 'income', 'occurred_at': '2026-06-01T09:00:00.000', 'amount': 1000},
          <String, Object?>{'id': '', 'type': 'other', 'occurred_at': 'bad-date', 'amount': 'x'},
        ],
      });

      final result = await const ReadableImportService().dryRunTransactionsJson(db, jsonText);

      expect(result.totalRows, 2);
      expect(result.validRows, 1);
      expect(result.invalidRows, 1);
      expect(result.readyToInsertRows, 1);
      expect(result.rows[0].status, ReadableImportRowStatus.readyToInsert);
      expect(result.rows[1].errors, contains('id 為必填'));
      expect(result.rows[1].errors, contains('type 不支援：other'));
    });

    test('duplicate detection is skipped safely when transactions table is missing', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      final csv = [
        'id,type,occurred_at,amount',
        'tx-1,expense,2026-06-01T08:00:00.000,150',
      ].join('\n');

      final result = await const ReadableImportService().dryRunTransactionsCsv(db, csv);

      expect(result.totalRows, 1);
      expect(result.readyToInsertRows, 1);
      expect(result.duplicateRows, 0);
    });

    test('throws typed exception for invalid transactions JSON root', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      expect(
        () => const ReadableImportService().dryRunTransactionsJson(db, '[]'),
        throwsA(isA<ReadableImportException>()),
      );
    });
  });
}

Future<void> _createTransactionTable(Database db) async {
  await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY, type TEXT, occurred_at TEXT, amount REAL)');
}

Future<void> _insertExistingTransaction(Database db) async {
  await db.insert('transactions', <String, Object?>{'id': 'tx-existing', 'type': 'expense', 'occurred_at': '2026-06-01T08:00:00.000', 'amount': 200});
}
