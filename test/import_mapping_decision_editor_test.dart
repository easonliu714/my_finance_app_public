import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/import_mapping_decision_editor.dart';
import 'package:my_finance_app/features/backup/import_mapping_decision_service.dart';

void main() {
  testWidgets('ImportMappingDecisionEditor emits decisions and updates validation state', (tester) async {
    ImportMappingDecisionSet? latestDecisions;
    final editorScrollable = find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportMappingDecisionEditor(
            analysis: _sampleAnalysis(),
            onChanged: (decisions) => latestDecisions = decisions,
          ),
        ),
      ),
    );

    expect(find.text('匯入對應決策'), findsOneWidget);
    expect(find.textContaining('不會正式寫入 transactions'), findsOneWidget);
    expect(find.text('仍有阻擋項目'), findsOneWidget);
    expect(find.text('阻擋 1'), findsOneWidget);
    expect(find.text('未處理類別 2'), findsOneWidget);
    expect(find.text('未處理商家 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('account-account_name-信用卡-card-1')));
    await tester.pumpAndSettle();

    expect(latestDecisions, isNotNull);
    expect(latestDecisions!.accountDecisions.single.selectedAccountId, 'card-1');
    expect(find.text('可進入後續確認'), findsOneWidget);
    expect(find.text('阻擋 0'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('category-早餐')), 240, scrollable: editorScrollable);
    await tester.enterText(find.byKey(const ValueKey<String>('category-早餐')), '餐飲/早餐');
    await tester.pumpAndSettle();

    expect(latestDecisions!.categoryDecisions.single.mappedCategory, '餐飲/早餐');
    await tester.drag(editorScrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('未處理類別 1'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('merchant-早餐店')), 240, scrollable: editorScrollable);
    await tester.enterText(find.byKey(const ValueKey<String>('merchant-早餐店')), '早餐店-已對應');
    await tester.pumpAndSettle();

    expect(latestDecisions!.merchantDecisions.single.mappedMerchant, '早餐店-已對應');
    await tester.drag(editorScrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('未處理商家 0'), findsOneWidget);
  });

  testWidgets('ImportMappingDecisionEditor renders empty sections', (tester) async {
    const analysis = ImportMappingAnalysisResult(
      accountReferences: <ImportAccountReferenceAnalysis>[],
      categories: <String>[],
      merchants: <String>[],
      summary: ImportMappingConflictSummary(
        missingAccountCount: 0,
        ambiguousAccountCount: 0,
        unmappedCategoryCount: 0,
        unmappedMerchantCount: 0,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImportMappingDecisionEditor(analysis: analysis)),
      ),
    );

    expect(find.text('沒有帳戶欄位需要決策。'), findsOneWidget);
    expect(find.text('沒有類別候選值。'), findsOneWidget);
    expect(find.text('沒有商家候選值。'), findsOneWidget);
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
    ],
    categories: <String>['早餐', '午餐'],
    merchants: <String>['早餐店'],
    summary: ImportMappingConflictSummary(
      missingAccountCount: 0,
      ambiguousAccountCount: 1,
      unmappedCategoryCount: 2,
      unmappedMerchantCount: 1,
    ),
  );
}
