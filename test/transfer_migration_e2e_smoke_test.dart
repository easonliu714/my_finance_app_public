import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/import_mapping_decision_service.dart';
import 'package:my_finance_app/features/backup/readable_export_service.dart';
import 'package:my_finance_app/features/backup/readable_import_commit_service.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('P3.5.11 transfer migration E2E smoke test', () {
    test('exports from source DB, imports into target DB, commits rows, and skips duplicate rerun', () async {
      final tempDirectory = await Directory.systemTemp.createTemp('my_finance_transfer_e2e_');
      addTearDown(() => tempDirectory.delete(recursive: true));
      final sourceDb = await openDatabase(p.join(tempDirectory.path, 'source.db'));
      final targetDb = await openDatabase(p.join(tempDirectory.path, 'target.db'));
      addTearDown(sourceDb.close);
      addTearDown(targetDb.close);
      await _createTransferTables(sourceDb);
      await _createTransferTables(targetDb);
      await _seedSourceDb(sourceDb);
      await _seedTargetAccounts(targetDb);

      final exportJson = await const ReadableExportService().exportTransactionsJson(sourceDb);
      final exportPayload = jsonDecode(exportJson) as Map<String, Object?>;
      expect((exportPayload['data'] as List<dynamic>), hasLength(2));

      final dryRun = await const ReadableImportService().dryRunTransactionsJson(targetDb, exportJson);
      expect(dryRun.totalRows, 2);
      expect(dryRun.readyToInsertRows, 2);
      expect(dryRun.invalidRows, 0);
      expect(dryRun.duplicateRows, 0);

      final analysis = await const ImportMappingAnalysisService().analyze(targetDb, dryRun);
      final validation = const ImportMappingDecisionService().validate(analysis: analysis, decisions: const ImportMappingDecisionSet());
      expect(validation.canCommit, isTrue);

      final commitResult = await const ReadableImportCommitService().commitReviewedTransactions(
        targetDb,
        dryRunResult: dryRun,
        mappingAnalysis: analysis,
        decisions: const ImportMappingDecisionSet(),
        confirmed: true,
      );
      expect(commitResult.insertedRows, 2);
      expect(commitResult.skippedRows, 0);
      expect(commitResult.failedRows, 0);

      final targetRows = await targetDb.query('transactions', orderBy: 'occurred_at ASC, id ASC');
      expect(targetRows, hasLength(2));
      expect(targetRows[0]['id'], 'tx-food');
      expect(targetRows[0]['amount'], 150.0);
      expect(targetRows[0]['category'], '早餐');
      expect(targetRows[0]['merchant_name'], '早餐店');
      expect(targetRows[1]['id'], 'tx-income');
      expect(targetRows[1]['amount'], 3000.0);
      expect(targetRows[1]['category'], '薪資');

      final rerunDryRun = await const ReadableImportService().dryRunTransactionsJson(targetDb, exportJson);
      expect(rerunDryRun.readyToInsertRows, 0);
      expect(rerunDryRun.duplicateRows, 2);

      final rerunCommit = await const ReadableImportCommitService().commitReviewedTransactions(
        targetDb,
        dryRunResult: rerunDryRun,
        mappingAnalysis: await const ImportMappingAnalysisService().analyze(targetDb, rerunDryRun),
        decisions: const ImportMappingDecisionSet(),
        confirmed: true,
      );
      expect(rerunCommit.insertedRows, 0);
      expect(rerunCommit.skippedRows, 2);
      expect(await targetDb.query('transactions'), hasLength(2));
    });
  });
}

Future<void> _createTransferTables(Database db) async {
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

Future<void> _seedSourceDb(Database db) async {
  await _seedTargetAccounts(db);
  await db.insert('transactions', <String, Object?>{
    'id': 'tx-food',
    'type': 'expense',
    'occurred_at': '2026-06-01T08:00:00.000',
    'amount': 150,
    'currency_code': 'TWD',
    'base_amount': 150,
    'category': '早餐',
    'account_name': '現金',
    'from_account_name': null,
    'to_account_name': null,
    'member_name': '我',
    'merchant_name': '早餐店',
    'tag_name': '日常',
    'note': '換機匯入測試',
    'repayment_group_id': null,
    'created_at': '2026-06-01T08:05:00.000',
  });
  await db.insert('transactions', <String, Object?>{
    'id': 'tx-income',
    'type': 'income',
    'occurred_at': '2026-06-02T09:00:00.000',
    'amount': 3000,
    'currency_code': 'TWD',
    'base_amount': 3000,
    'category': '薪資',
    'account_name': '現金',
    'from_account_name': null,
    'to_account_name': null,
    'member_name': '我',
    'merchant_name': '公司',
    'tag_name': '收入',
    'note': '換機匯入測試收入',
    'repayment_group_id': null,
    'created_at': '2026-06-02T09:05:00.000',
  });
}

Future<void> _seedTargetAccounts(Database db) async {
  await db.insert('accounts', <String, Object?>{
    'id': 'cash-1',
    'name': '現金',
    'type': 'cash',
    'suffix': '',
    'sort_order': 1,
  });
}
