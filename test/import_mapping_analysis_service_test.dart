import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ImportMappingAnalysisService', () {
    test('classifies matched, missing, and ambiguous account references', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createAccountsTable(db);
      await _insertAccount(db, id: 'cash', name: '現金', suffix: '');
      await _insertAccount(db, id: 'card-1', name: '信用卡', suffix: '1234');
      await _insertAccount(db, id: 'card-2', name: '信用卡', suffix: '5678');

      final result = await const ImportMappingAnalysisService().analyze(db, _sampleDryRunResult());

      expect(result.summary.missingAccountCount, 1);
      expect(result.summary.ambiguousAccountCount, 1);
      expect(result.summary.unmappedCategoryCount, 2);
      expect(result.summary.unmappedMerchantCount, 2);

      final cash = _findReference(result, 'account_name', '現金');
      expect(cash.status, ImportAccountMappingStatus.matched);
      expect(cash.candidates.single.id, 'cash');

      final card = _findReference(result, 'account_name', '信用卡');
      expect(card.status, ImportAccountMappingStatus.ambiguous);
      expect(card.candidates.map((candidate) => candidate.id).toSet(), {'card-1', 'card-2'});

      final missing = _findReference(result, 'from_account_name', '不存在銀行');
      expect(missing.status, ImportAccountMappingStatus.missing);
    });

    test('matches account display name with suffix when provided', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createAccountsTable(db);
      await _insertAccount(db, id: 'card-1', name: '信用卡', suffix: '1234');
      await _insertAccount(db, id: 'card-2', name: '信用卡', suffix: '5678');

      final result = await const ImportMappingAnalysisService().analyze(
        db,
        const ReadableImportDryRunResult(
          totalRows: 1,
          validRows: 1,
          invalidRows: 0,
          duplicateRows: 0,
          readyToInsertRows: 1,
          rows: <ReadableImportRowResult>[
            ReadableImportRowResult(
              sourceRowIndex: 2,
              row: <String, Object?>{'id': 'tx-1', 'account_name': '信用卡 1234'},
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
          ],
        ),
      );

      final card = _findReference(result, 'account_name', '信用卡 1234');
      expect(card.status, ImportAccountMappingStatus.matched);
      expect(card.candidates.single.id, 'card-1');
    });

    test('matches account display variants but keeps output display format stable', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createAccountsTable(db);
      await _insertAccount(db, id: 'ipass-money', name: '一卡通 Money', suffix: 'ipass-money');

      final result = await const ImportMappingAnalysisService().analyze(
        db,
        const ReadableImportDryRunResult(
          totalRows: 2,
          validRows: 2,
          invalidRows: 0,
          duplicateRows: 0,
          readyToInsertRows: 2,
          rows: <ReadableImportRowResult>[
            ReadableImportRowResult(
              sourceRowIndex: 2,
              row: <String, Object?>{'id': 'tx-1', 'account_name': '一卡通 Money • ipass-money'},
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
            ReadableImportRowResult(
              sourceRowIndex: 3,
              row: <String, Object?>{'id': 'tx-2', 'to_account_name': '一卡通 Money(ipass-money)'},
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
          ],
        ),
      );

      final account = _findReference(result, 'account_name', '一卡通 Money • ipass-money');
      expect(account.status, ImportAccountMappingStatus.matched);
      expect(account.candidates.single.id, 'ipass-money');
      expect(account.candidates.single.displayName, '一卡通 Money ipass-money');

      final toAccount = _findReference(result, 'to_account_name', '一卡通 Money(ipass-money)');
      expect(toAccount.status, ImportAccountMappingStatus.matched);
      expect(toAccount.candidates.single.id, 'ipass-money');
    });

    test('filters account-like values out of merchant candidates', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createAccountsTable(db);
      await _insertAccount(db, id: 'ipass-money', name: '一卡通 Money', suffix: 'ipass-money');
      await _insertAccount(db, id: 'line-4568', name: 'Line', suffix: '4568');
      await _insertAccount(db, id: 'bank-3345', name: '華南銀行', suffix: '3345');

      final result = await const ImportMappingAnalysisService().analyze(
        db,
        const ReadableImportDryRunResult(
          totalRows: 4,
          validRows: 4,
          invalidRows: 0,
          duplicateRows: 0,
          readyToInsertRows: 4,
          rows: <ReadableImportRowResult>[
            ReadableImportRowResult(
              sourceRowIndex: 2,
              row: <String, Object?>{
                'id': 'tx-1',
                'type': 'transfer',
                'from_account_name': 'Line • 4568',
                'to_account_name': '一卡通 Money',
                'merchant_name': 'Line • 4568',
              },
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
            ReadableImportRowResult(
              sourceRowIndex: 3,
              row: <String, Object?>{
                'id': 'tx-2',
                'type': 'transfer',
                'from_account_name': '華南銀行 • 3345',
                'to_account_name': '一卡通 Money',
                'merchant_name': '華南銀行 • 3345',
              },
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
            ReadableImportRowResult(
              sourceRowIndex: 4,
              row: <String, Object?>{
                'id': 'tx-3',
                'type': 'expense',
                'account_name': '一卡通 Money(ipass-money)',
                'merchant_name': 'OK便利商店',
              },
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
            ReadableImportRowResult(
              sourceRowIndex: 5,
              row: <String, Object?>{
                'id': 'tx-4',
                'type': 'expense',
                'account_name': '一卡通 Money',
                'merchant_name': '一卡通 Money',
              },
              status: ReadableImportRowStatus.readyToInsert,
              errors: <String>[],
            ),
          ],
        ),
      );

      expect(result.merchants, contains('OK便利商店'));
      expect(result.merchants, isNot(contains('Line • 4568')));
      expect(result.merchants, isNot(contains('華南銀行 • 3345')));
      expect(result.merchants, isNot(contains('一卡通 Money')));
      expect(result.summary.unmappedMerchantCount, 1);

      final line = _findReference(result, 'from_account_name', 'Line • 4568');
      expect(line.status, ImportAccountMappingStatus.matched);
      expect(line.candidates.single.id, 'line-4568');

      final money = _findReference(result, 'account_name', '一卡通 Money(ipass-money)');
      expect(money.status, ImportAccountMappingStatus.matched);
      expect(money.candidates.single.id, 'ipass-money');
    });

    test('handles missing accounts table without crashing', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      final result = await const ImportMappingAnalysisService().analyze(db, _sampleDryRunResult());

      expect(result.accountReferences.every((reference) => reference.status == ImportAccountMappingStatus.missing), isTrue);
      expect(result.summary.missingAccountCount, result.accountReferences.length);
    });
  });
}

ReadableImportDryRunResult _sampleDryRunResult() {
  return const ReadableImportDryRunResult(
    totalRows: 2,
    validRows: 2,
    invalidRows: 0,
    duplicateRows: 0,
    readyToInsertRows: 2,
    rows: <ReadableImportRowResult>[
      ReadableImportRowResult(
        sourceRowIndex: 2,
        row: <String, Object?>{
          'id': 'tx-1',
          'account_name': '現金',
          'from_account_name': '不存在銀行',
          'to_account_name': '',
          'category': '早餐',
          'merchant_name': '早餐店',
        },
        status: ReadableImportRowStatus.readyToInsert,
        errors: <String>[],
      ),
      ReadableImportRowResult(
        sourceRowIndex: 3,
        row: <String, Object?>{
          'id': 'tx-2',
          'account_name': '信用卡',
          'from_account_name': '',
          'to_account_name': '現金',
          'category': '午餐',
          'merchant_name': '便當店',
        },
        status: ReadableImportRowStatus.readyToInsert,
        errors: <String>[],
      ),
    ],
  );
}

ImportAccountReferenceAnalysis _findReference(ImportMappingAnalysisResult result, String fieldName, String value) {
  return result.accountReferences.singleWhere((reference) => reference.fieldName == fieldName && reference.value == value);
}

Future<void> _createAccountsTable(Database db) async {
  await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, suffix TEXT NOT NULL DEFAULT "")');
}

Future<void> _insertAccount(Database db, {required String id, required String name, required String suffix}) async {
  await db.insert('accounts', <String, Object?>{'id': id, 'name': name, 'suffix': suffix});
}
