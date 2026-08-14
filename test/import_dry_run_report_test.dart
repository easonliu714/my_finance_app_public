import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/import_dry_run_report.dart';
import 'package:my_finance_app/features/backup/readable_import_service.dart';

void main() {
  testWidgets('ImportDryRunReport renders summary and row-level statuses', (tester) async {
    const result = ReadableImportDryRunResult(
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
          },
          status: ReadableImportRowStatus.readyToInsert,
          errors: <String>[],
        ),
        ReadableImportRowResult(
          sourceRowIndex: 3,
          row: <String, Object?>{
            'id': 'tx-duplicate',
            'type': 'expense',
            'occurred_at': '2026-06-01T09:00:00.000',
            'amount': '200',
          },
          status: ReadableImportRowStatus.duplicate,
          errors: <String>[],
        ),
        ReadableImportRowResult(
          sourceRowIndex: 4,
          row: <String, Object?>{
            'id': 'tx-invalid',
            'type': 'other',
            'occurred_at': 'bad-date',
            'amount': 'abc',
          },
          status: ReadableImportRowStatus.invalid,
          errors: <String>['type 不支援：other', 'amount 不是有效數字', 'occurred_at 不是有效日期'],
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImportDryRunReport(result: result)),
      ),
    );

    expect(find.text('匯入預檢報告'), findsOneWidget);
    expect(find.textContaining('尚未寫入正式資料'), findsOneWidget);
    expect(find.text('總列數'), findsOneWidget);
    expect(find.text('有效'), findsOneWidget);
    expect(find.text('錯誤'), findsAtLeastNWidgets(1));
    expect(find.text('重複'), findsAtLeastNWidgets(1));
    expect(find.text('可匯入'), findsAtLeastNWidgets(1));
    expect(find.text('第 2 列｜可匯入'), findsOneWidget);
    expect(find.text('第 3 列｜重複'), findsOneWidget);
    expect(find.text('第 4 列｜錯誤'), findsOneWidget);

    await tester.tap(find.text('第 4 列｜錯誤'));
    await tester.pumpAndSettle();

    expect(find.text('錯誤原因'), findsOneWidget);
    expect(find.text('• type 不支援：other'), findsOneWidget);
    expect(find.text('• amount 不是有效數字'), findsOneWidget);
    expect(find.text('• occurred_at 不是有效日期'), findsOneWidget);
  });

  testWidgets('ImportDryRunReport renders empty state', (tester) async {
    const result = ReadableImportDryRunResult(
      totalRows: 0,
      validRows: 0,
      invalidRows: 0,
      duplicateRows: 0,
      readyToInsertRows: 0,
      rows: <ReadableImportRowResult>[],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImportDryRunReport(result: result)),
      ),
    );

    expect(find.text('沒有可顯示的匯入列。'), findsOneWidget);
  });
}
