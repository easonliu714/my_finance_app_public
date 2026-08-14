import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/import_mapping_decision_service.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';

void main() {
  group('ImportMappingDecisionService', () {
    test('reports blocking issues for missing or ambiguous account references without decisions', () {
      final validation = const ImportMappingDecisionService().validate(
        analysis: _sampleAnalysis(),
        decisions: const ImportMappingDecisionSet(),
      );

      expect(validation.canCommit, isFalse);
      expect(validation.blockingIssues, hasLength(2));
      expect(validation.blockingIssues.map((issue) => issue.importedValue).toSet(), {'信用卡', '不存在銀行'});
      expect(validation.unresolvedCategories, containsAll(<String>['早餐', '午餐']));
      expect(validation.unresolvedMerchants, containsAll(<String>['早餐店', '便當店']));
    });

    test('passes account blocking validation when missing and ambiguous references have decisions', () {
      final validation = const ImportMappingDecisionService().validate(
        analysis: _sampleAnalysis(),
        decisions: _sampleDecisionSet(),
      );

      expect(validation.canCommit, isTrue);
      expect(validation.blockingIssues, isEmpty);
      expect(validation.unresolvedCategories, contains('午餐'));
      expect(validation.unresolvedMerchants, contains('便當店'));
    });

    test('applies decisions to row copies without mutating original rows', () {
      final original = _sampleDryRunResult();
      final preview = const ImportMappingDecisionService().previewApplyDecisions(original, _sampleDecisionSet());

      expect(preview.rows, hasLength(2));
      expect(preview.rows[0].row['category'], '餐飲/早餐');
      expect(preview.rows[0].row['merchant_name'], '早餐店-已對應');
      expect(preview.rows[1].row['account_name'], '信用卡 1234');
      expect(preview.rows[1].row['account_name_mapped_account_id'], 'card-1');
      expect(preview.rows[0].row['from_account_name'], '銀行帳戶');
      expect(preview.rows[0].row['from_account_name_mapped_account_id'], 'bank-1');

      expect(original.rows[0].row['category'], '早餐');
      expect(original.rows[0].row['merchant_name'], '早餐店');
      expect(original.rows[1].row['account_name'], '信用卡');
      expect(original.rows[1].row.containsKey('account_name_mapped_account_id'), isFalse);
    });

    test('keeps fields unchanged when no decision is defined', () {
      final preview = const ImportMappingDecisionService().previewApplyDecisions(
        _sampleDryRunResult(),
        const ImportMappingDecisionSet(),
      );

      expect(preview.rows[0].row['category'], '早餐');
      expect(preview.rows[0].row['merchant_name'], '早餐店');
      expect(preview.rows[0].row['account_name'], '現金');
      expect(preview.rows[1].row['account_name'], '信用卡');
    });
  });
}

ImportMappingAnalysisResult _sampleAnalysis() {
  return const ImportMappingAnalysisResult(
    accountReferences: <ImportAccountReferenceAnalysis>[
      ImportAccountReferenceAnalysis(
        fieldName: 'account_name',
        value: '現金',
        status: ImportAccountMappingStatus.matched,
        candidates: <ImportAccountCandidate>[ImportAccountCandidate(id: 'cash', name: '現金', suffix: '')],
      ),
      ImportAccountReferenceAnalysis(
        fieldName: 'account_name',
        value: '信用卡',
        status: ImportAccountMappingStatus.ambiguous,
        candidates: <ImportAccountCandidate>[
          ImportAccountCandidate(id: 'card-1', name: '信用卡', suffix: '1234'),
          ImportAccountCandidate(id: 'card-2', name: '信用卡', suffix: '5678'),
        ],
      ),
      ImportAccountReferenceAnalysis(
        fieldName: 'from_account_name',
        value: '不存在銀行',
        status: ImportAccountMappingStatus.missing,
        candidates: <ImportAccountCandidate>[],
      ),
    ],
    categories: <String>['早餐', '午餐'],
    merchants: <String>['早餐店', '便當店'],
    summary: ImportMappingConflictSummary(
      missingAccountCount: 1,
      ambiguousAccountCount: 1,
      unmappedCategoryCount: 2,
      unmappedMerchantCount: 2,
    ),
  );
}

ImportMappingDecisionSet _sampleDecisionSet() {
  return const ImportMappingDecisionSet(
    accountDecisions: <ImportAccountMappingDecision>[
      ImportAccountMappingDecision(fieldName: 'account_name', importedValue: '信用卡', selectedAccountId: 'card-1', selectedDisplayName: '信用卡 1234'),
      ImportAccountMappingDecision(fieldName: 'from_account_name', importedValue: '不存在銀行', selectedAccountId: 'bank-1', selectedDisplayName: '銀行帳戶'),
    ],
    categoryDecisions: <ImportCategoryMappingDecision>[
      ImportCategoryMappingDecision(importedCategory: '早餐', mappedCategory: '餐飲/早餐'),
    ],
    merchantDecisions: <ImportMerchantMappingDecision>[
      ImportMerchantMappingDecision(importedMerchant: '早餐店', mappedMerchant: '早餐店-已對應'),
    ],
  );
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
          'category': '午餐',
          'merchant_name': '便當店',
        },
        status: ReadableImportRowStatus.readyToInsert,
        errors: <String>[],
      ),
    ],
  );
}
