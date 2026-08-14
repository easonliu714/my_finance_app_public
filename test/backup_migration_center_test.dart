import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_migration_center.dart';

void main() {
  testWidgets(
      'BackupMigrationCenter renders concise actions and help dialogs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BackupMigrationCenter()),
      ),
    );

    expect(find.text('備份與移轉'), findsOneWidget);
    expect(find.text('備份與換機移轉中心'), findsNothing);
    expect(find.text('目前可用功能'), findsNothing);

    await tester.tap(find.byTooltip('備份與移轉 說明'));
    await tester.pumpAndSettle();
    expect(find.text('備份與移轉說明'), findsOneWidget);
    expect(find.textContaining('不會靜默上傳或覆蓋資料'), findsOneWidget);
    await tester.tap(find.text('了解'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('完整備份 / 完整還原'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('完整備份 / 完整還原'), findsOneWidget);
    expect(find.text('完整備份'), findsOneWidget);
    expect(find.text('完整還原來源'), findsOneWidget);
    expect(find.text('完整還原'), findsOneWidget);
    expect(find.text('高風險'), findsOneWidget);
    expect(find.text('使用完整備份檔復原資料。'), findsOneWidget);

    await tester.tap(find.byTooltip('完整備份 / 完整還原 說明'));
    await tester.pumpAndSettle();
    expect(find.text('完整模式是什麼？'), findsOneWidget);
    expect(find.textContaining('換手機'), findsWidgets);
    expect(
      find.textContaining('完整還原會恢復帳戶、交易、信用卡帳單'),
      findsOneWidget,
    );
    await tester.tap(find.text('了解'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('readable 匯出 / 匯入'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('readable 匯出 / 匯入'), findsOneWidget);
    expect(find.text('CSV / JSON readable 匯出'), findsOneWidget);
    expect(find.text('CSV / JSON readable 匯入審核'), findsOneWidget);

    await tester.tap(find.byTooltip('readable 匯出 / 匯入 說明'));
    await tester.pumpAndSettle();
    expect(find.text('readable 模式是什麼？'), findsOneWidget);
    expect(find.textContaining('只處理交易紀錄'), findsOneWidget);
    expect(find.textContaining('不會完整恢復帳戶設定'), findsOneWidget);
    await tester.tap(find.text('了解'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不包含帳戶完整復原'), findsOneWidget);
    expect(find.text('選擇 readable 匯入檔'), findsOneWidget);
    expect(find.text('掃描固定匯入資料夾'), findsOneWidget);
  });

  testWidgets('BackupMigrationCenter exposes callbacks for all action cards',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var fullBackupTapped = false;
    var fullRestoreTapped = false;
    var readableExportTapped = false;
    var readableImportTapped = false;
    var readablePickTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(
            onFullBackup: () => fullBackupTapped = true,
            onFullRestore: () => fullRestoreTapped = true,
            onReadableExport: () => readableExportTapped = true,
            onReadableImportReview: () => readableImportTapped = true,
            onPickReadableImportFile: () => readablePickTapped = true,
          ),
        ),
      ),
    );

    await _scrollAndTap(tester, '建立完整備份');
    expect(fullBackupTapped, isTrue);

    await _scrollAndTap(tester, '檢視完整還原流程');
    expect(fullRestoreTapped, isTrue);

    await _scrollAndTap(tester, '進入 readable 匯出');
    expect(readableExportTapped, isTrue);

    await _scrollAndTap(tester, '選擇 readable 匯入檔');
    expect(readablePickTapped, isTrue);

    await _scrollAndTap(tester, '掃描固定匯入資料夾');
    expect(readableImportTapped, isTrue);
  });
}

Future<void> _scrollAndTap(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}
