import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/import_mapping_decision_service.dart';
import 'package:my_finance_app/features/backup/readable_import_commit_service.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReadableImportService commitReadyTransactions', () {
    test('rejects commit when confirmation flag is false', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);

      expect(
        () => const ReadableImportService().commitReadyTransactions(
          db,
          _sampleDryRunResult(),
          confirmed: false,
        ),
        throwsA(isA<ReadableImportException>()),
      );
    });

    test('commits only ready-to-insert rows and skips invalid or duplicate rows', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);
      await _insertExistingTransaction(db, 'tx-duplicate');

      final result = await const ReadableImportService().commitReadyTransactions(
        db,
        _sampleDryRunResult(),
        confirmed: true,
      );

      expect(result.insertedRows, 1);
      expect(result.skippedRows, 2);
      expect(result.duplicateAtCommitRows, 0);
      expect(result.failedRows, 0);
      expect(result.invalidRows, 1);
      expect(await db.query('transactions', where: 'id = ?', whereArgs: <Object?>['tx-ready']), hasLength(1));
      expect(await db.query('transactions', where: 'id = ?', whereArgs: <Object?>['tx-invalid']), isEmpty);
    });

    test('rechecks duplicate ids at commit time', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);
      await _insertExistingTransaction(db, 'tx-ready');

      final result = await const ReadableImportService().commitReadyTransactions(
        db,
        _sampleDryRunResult(),
        confirmed: true,
      );

      expect(result.insertedRows, 0);
      expect(result.skippedRows, 2);
      expect(result.duplicateAtCommitRows, 1);
      expect(result.failedRows, 0);
    });

    test('throws typed exception when transactions table is missing', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      expect(
        () => const ReadableImportService().commitReadyTransactions(
          db,
          _sampleDryRunResult(),
          confirmed: true,
        ),
        throwsA(isA<ReadableImportException>()),
      );
    });
  });

  group('ReadableImportCommitService', () {
    test('commits reviewed ready rows and applies mapping decisions', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);

      final result = await const ReadableImportCommitService().commitReviewedTransactions(
        db,
        dryRunResult: _sampleDryRunResult(),
        mappingAnalysis: _analysis(categories: const <String>['早餐'], merchants: const <String>['早餐店']),
        decisions: const ImportMappingDecisionSet(
          categoryDecisions: <ImportCategoryMappingDecision>[ImportCategoryMappingDecision(importedCategory: '早餐', mappedCategory: '餐飲')],
          merchantDecisions: <ImportMerchantMappingDecision>[ImportMerchantMappingDecision(importedMerchant: '早餐店', mappedMerchant: '測試早餐店')],
        ),
        confirmed: true,
      );

      expect(result.insertedRows, 1);
      expect(result.skippedRows, 2);
      expect(result.invalidRows, 1);
      expect(result.blockingIssues, isEmpty);
      final rows = await db.query('transactions', where: 'id = ?', whereArgs: <Object?>['tx-ready']);
      expect(rows.single['category'], '餐飲');
      expect(rows.single['merchant_name'], '測試早餐店');
    });

    test('returns blocked summary without writing when account decision is missing', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);
      final result = await const ReadableImportCommitService().commitReviewedTransactions(
        db,
        dryRunResult: _sampleDryRunResult(),
        mappingAnalysis: _analysis(accountReferences: const <ImportAccountReferenceAnalysis>[
          ImportAccountReferenceAnalysis(fieldName: 'account_name', value: '信用卡', status: ImportAccountMappingStatus.missing, candidates: <ImportAccountCandidate>[]),
        ]),
        decisions: const ImportMappingDecisionSet(),
        confirmed: true,
      );

      expect(result.insertedRows, 0);
      expect(result.skippedRows, 3);
      expect(result.blockingIssues.single, contains('帳戶對應尚未決定'));
      expect(await db.query('transactions'), isEmpty);
    });

    test('skips duplicate detected at commit time', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createTransactionTable(db);
      await _insertExistingTransaction(db, 'tx-ready');

      final result = await const ReadableImportCommitService().commitReviewedTransactions(
        db,
        dryRunResult: _sampleDryRunResult(),
        mappingAnalysis: _analysis(),
        decisions: const ImportMappingDecisionSet(),
        confirmed: true,
      );

      expect(result.insertedRows, 0);
      expect(result.duplicateAtCommitRows, 1);
      expect(await db.query('transactions'), hasLength(1));
    });
  });
}

ImportMappingAnalysisResult _analysis({
  List<ImportAccountReferenceAnalysis> accountReferences = const <ImportAccountReferenceAnalysis>[],
  List<String> categories = const <String>[],
  List<String> merchants = const <String>[],
}) {
  return ImportMappingAnalysisResult(
    accountReferences: accountReferences,
    categories: categories,
    merchants: merchants,
    summary: ImportMappingConflictSummary(
      missingAccountCount: accountReferences.where((reference) => reference.status == ImportAccountMappingStatus.missing).length,
      ambiguousAccountCount: accountReferences.where((reference) => reference.status == ImportAccountMappingStatus.ambiguous).length,
      unmappedCategoryCount: categories.length,
      unmappedMerchantCount: merchants.length,
    ),
  );
}

ReadableImportDryRunResult _sampleDryRunResult() {
  return const ReadableImportDryRunResult(
    totalRows: 3,
    validRows: 2,
    invalidRows: 1,
    duplicateRows: 1,
    readyToInsertRows: 1,
    rows: <ReadableImportRowResult>[
      ReadableImportRowResult(
        sourceRowIndex: 2,
        row: <String, Object?>{
          'id': 'tx-ready',
          'type': 'expense',
          'occurred_at': '2026-06-01T08:00:00.000',
          'amount': '150',
          'currency_code': 'TWD',
          'base_amount': '150',
          'category': '早餐',
          'account_name': '信用卡',
          'member_name': '我',
          'merchant_name': '早餐店',
          'tag_name': '日常',
          'note': '匯入測試',
          'repayment_group_id': '',
          'created_at': '2026-06-01T08:05:00.000',
        },
        status: ReadableImportRowStatus.readyToInsert,
        errors: <String>[],
      ),
      ReadableImportRowResult(
        sourceRowIndex: 3,
        row: <String, Object?>{'id': 'tx-duplicate', 'type': 'expense', 'occurred_at': '2026-06-01T09:00:00.000', 'amount': '200'},
        status: ReadableImportRowStatus.duplicate,
        errors: <String>[],
      ),
      ReadableImportRowResult(
        sourceRowIndex: 4,
        row: <String, Object?>{'id': 'tx-invalid', 'type': 'other', 'occurred_at': 'bad-date', 'amount': 'abc'},
        status: ReadableImportRowStatus.invalid,
        errors: <String>['type 不支援：other'],
      ),
    ],
  );
}

Future<void> _createTransactionTable(Database db) async {
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT,
      occurred_at TEXT,
      amount REAL,
      currency_code TEXT,
      base_amount REAL,
      category TEXT,
      account_name TEXT,
      member_name TEXT,
      merchant_name TEXT,
      tag_name TEXT,
      note TEXT,
      repayment_group_id TEXT,
      created_at TEXT
    )
  ''');
}

Future<void> _insertExistingTransaction(Database db, String id) async {
  await db.insert('transactions', <String, Object?>{
    'id': id,
    'type': 'expense',
    'occurred_at': '2026-06-01T08:00:00.000',
    'amount': 200,
  });
}
