import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/import_mapping_decision_service.dart';
import 'package:my_finance_app/features/backup/import_review_flow.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';

void main() {
  testWidgets('ImportReviewFlow navigates steps and updates review summary after decisions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ImportMappingDecisionSet? latestDecisions;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportReviewFlow(
            dryRunResult: _sampleDryRunResult(),
            mappingAnalysis: _sampleAnalysis(),
            onDecisionChanged: (decisions) => latestDecisions = decisions,
          ),
        ),
      ),
    );

    expect(find.text('匯入審核流程'), findsOneWidget);
    expect(find.textContaining('不會自動新增主檔'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('阻擋 1'), findsOneWidget);
    expect(find.text('未處理類別 1'), findsOneWidget);
    expect(find.text('未處理商家 1'), findsOneWidget);
    expect(find.text('目前｜Step 1｜Dry-run report'), findsOneWidget);
    expect(find.text('下一步｜Step 2｜Mapping / conflict report'), findsOneWidget);
    expect(find.text('Step 3｜Mapping decision'), findsNothing);
    expect(find.text('Step 4｜Review summary'), findsNothing);
    expect(find.text('匯入預檢報告'), findsOneWidget);

    await tester.tap(find.text('下一步｜Step 2｜Mapping / conflict report'));
    await tester.pumpAndSettle();
    expect(find.text('對應 / 衝突檢查報告'), findsOneWidget);
    expect(find.text('目前｜Step 2｜Mapping / conflict report'), findsOneWidget);
    expect(find.text('下一步｜Step 3｜Mapping decision'), findsOneWidget);

    await tester.tap(find.text('下一步｜Step 3｜Mapping decision'));
    await tester.pumpAndSettle();
    expect(find.text('匯入對應決策'), findsOneWidget);
    expect(find.text('目前｜Step 3｜Mapping decision'), findsOneWidget);
    expect(find.text('下一步｜Step 4｜Review summary'), findsOneWidget);

    final editorScrollable = find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down).last;
    await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('account-account_name-信用卡-card-1')), 120, scrollable: editorScrollable);
    await tester.tap(find.byKey(const ValueKey<String>('account-account_name-信用卡-card-1')));
    await tester.pumpAndSettle();

    expect(latestDecisions, isNotNull);
    expect(latestDecisions!.accountDecisions.single.selectedAccountId, 'card-1');

    await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('category-早餐')), 240, scrollable: editorScrollable);
    await tester.enterText(find.byKey(const ValueKey<String>('category-早餐')), '餐飲/早餐');
    await tester.pumpAndSettle();
    expect(latestDecisions!.categoryDecisions.single.mappedCategory, '餐飲/早餐');

    await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('merchant-早餐店')), 240, scrollable: editorScrollable);
    await tester.enterText(find.byKey(const ValueKey<String>('merchant-早餐店')), '早餐店-已對應');
    await tester.pumpAndSettle();
    expect(latestDecisions!.merchantDecisions.single.mappedMerchant, '早餐店-已對應');

    await tester.tap(find.text('下一步｜Step 4｜Review summary'));
    await tester.pumpAndSettle();

    expect(find.text('最終確認摘要'), findsOneWidget);
    expect(find.textContaining('狀態：可繼續'), findsOneWidget);
    expect(find.text('匯入總列數'), findsOneWidget);
    expect(find.text('可匯入列數'), findsOneWidget);
    expect(find.text('阻擋項目'), findsOneWidget);
    expect(find.text('0'), findsAtLeastNWidgets(1));
  });

  testWidgets('ImportReviewFlow review summary shows blocked state before required decisions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportReviewFlow(
            dryRunResult: _sampleDryRunResult(),
            mappingAnalysis: _sampleAnalysis(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('下一步｜Step 2｜Mapping / conflict report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步｜Step 3｜Mapping decision'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步｜Step 4｜Review summary'));
    await tester.pumpAndSettle();

    expect(find.text('最終確認摘要'), findsOneWidget);
    expect(find.textContaining('狀態：Blocked'), findsOneWidget);
    expect(find.text('阻擋原因'), findsOneWidget);
    expect(find.textContaining('帳戶對應尚未決定'), findsOneWidget);
  });
}

ReadableImportDryRunResult _sampleDryRunResult() {
  return const ReadableImportDryRunResult(
    totalRows: 1,
    validRows: 1,
    invalidRows: 0,
    duplicateRows: 0,
    readyToInsertRows: 1,
    rows: <ReadableImportRowResult>[
      ReadableImportRowResult(
        sourceRowIndex: 2,
        row: <String, Object?>{
          'id': 'tx-1',
          'type': 'expense',
          'occurred_at': '2026-06-01T08:00:00.000',
          'amount': '150',
          'account_name': '信用卡',
          'category': '早餐',
          'merchant_name': '早餐店',
        },
        status: ReadableImportRowStatus.readyToInsert,
        errors: <String>[],
      ),
    ],
  );
}

ImportMappingAnalysisResult _sampleAnalysis() {
  return const ImportMappingAnalysisResult(
    accountReferences: <ImportAccountReferenceAnalysis>[
      ImportAccountReferenceAnalysis(
        fieldName: 'account_name',
        value: '信用卡',
        status: ImportAccountMappingStatus.ambiguous,
        candidates: <ImportAccountCandidate>[
          ImportAccountCandidate(id: 'card-1', name: '信用卡', suffix: '1234'),
          ImportAccountCandidate(id: 'card-2', name: '信用卡', suffix: '5678'),
        ],
      ),
    ],
    categories: <String>['早餐'],
    merchants: <String>['早餐店'],
    summary: ImportMappingConflictSummary(
      missingAccountCount: 0,
      ambiguousAccountCount: 1,
      unmappedCategoryCount: 1,
      unmappedMerchantCount: 1,
    ),
  );
}
