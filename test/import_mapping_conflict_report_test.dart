import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_mapping_analysis_service.dart';
import 'package:my_finance_app/features/backup/import_mapping_conflict_report.dart';

void main() {
  testWidgets('ImportMappingConflictReport renders summary and mapping states', (tester) async {
    const result = ImportMappingAnalysisResult(
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

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImportMappingConflictReport(result: result)),
      ),
    );

    expect(find.text('對應 / 衝突檢查報告'), findsOneWidget);
    expect(find.textContaining('不會自動新增帳戶、類別或商家'), findsOneWidget);
    expect(find.text('缺失帳戶'), findsOneWidget);
    expect(find.text('模糊帳戶'), findsOneWidget);
    expect(find.text('類別候選'), findsOneWidget);
    expect(find.text('商家候選'), findsOneWidget);
    expect(find.text('account_name｜現金'), findsOneWidget);
    expect(find.text('account_name｜信用卡'), findsOneWidget);
    expect(find.text('from_account_name｜不存在銀行'), findsOneWidget);
    expect(find.text('已對應'), findsOneWidget);
    expect(find.text('模糊'), findsOneWidget);
    expect(find.text('缺失'), findsOneWidget);
    expect(find.text('現金 (cash)'), findsOneWidget);
    expect(find.text('信用卡 1234 (card-1)'), findsOneWidget);
    expect(find.text('信用卡 5678 (card-2)'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('早餐'), 240, scrollable: find.byType(Scrollable));
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('早餐店'), 240, scrollable: find.byType(Scrollable));
    expect(find.text('早餐店'), findsOneWidget);
    expect(find.text('便當店'), findsOneWidget);
  });

  testWidgets('ImportMappingConflictReport renders empty states', (tester) async {
    const result = ImportMappingAnalysisResult(
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
        home: Scaffold(body: ImportMappingConflictReport(result: result)),
      ),
    );

    expect(find.text('沒有帳戶欄位需要檢查。'), findsOneWidget);
    expect(find.text('沒有類別候選值。'), findsOneWidget);
    expect(find.text('沒有商家候選值。'), findsOneWidget);
  });
}
