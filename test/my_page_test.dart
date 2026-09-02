import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_migration_actions.dart';
import 'package:my_finance_app/features/backup/full_restore_preview_service.dart';
import 'package:my_finance_app/features/profile/my_page.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  testWidgets('MyPage renders concise backup and migration settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: MyPage()),
    );

    expect(find.text('我的'), findsAtLeastNWidgets(1));
    expect(find.text('備份與移轉'), findsOneWidget);
    expect(find.text('備份與換機移轉中心'), findsNothing);
    expect(find.text('目前可用功能'), findsNothing);

    await tester.tap(find.byTooltip('備份與移轉 說明'));
    // P4.20.1 registry status may legitimately keep an indeterminate loading
    // indicator alive while the local snapshot read is pending. This test is
    // about static settings/navigation copy, so use bounded pumps instead of
    // requiring unrelated application-wide animation quiescence.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('備份與移轉說明'), findsOneWidget);
    expect(find.textContaining('完整模式'), findsOneWidget);
    await tester.tap(find.text('了解'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.text('備份提醒'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('備份提醒'), findsOneWidget);
    expect(find.text('備份通知'), findsOneWidget);
    expect(find.text('要求系統通知權限'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('完整還原'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('完整備份 / 完整還原'), findsOneWidget);
    expect(find.text('完整備份'), findsOneWidget);
    expect(find.text('完整還原'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('CSV / JSON readable 匯入審核'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('readable 匯出 / 匯入'), findsOneWidget);
    expect(find.text('CSV / JSON readable 匯出'), findsOneWidget);
    expect(find.text('CSV / JSON readable 匯入審核'), findsOneWidget);
  });

  testWidgets(
      'MyPage restore action shows table count diff preview before commit gate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MyPage(
          actionService: const _FakeBackupMigrationActionService(),
          databaseProvider: () async => _NoopDatabaseExecutor(),
        ),
      ),
    );

    final restoreButton = find.widgetWithText(
      FilledButton,
      '檢視完整還原流程',
    );
    await tester.scrollUntilVisible(
      restoreButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(restoreButton);
    await tester.pump();
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(restoreButton);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('完整還原來源'), findsAtLeastNWidgets(1));
    expect(find.textContaining('來源位置'), findsOneWidget);
    expect(find.textContaining('import_sources/full_restore'), findsOneWidget);
    expect(find.textContaining('安全狀態'), findsOneWidget);
    expect(
      find.text('安全狀態：正式還原前仍需輸入 RESTORE，且會先建立還原前備份。'),
      findsOneWidget,
    );
    expect(find.textContaining('完整還原候選｜完整備份 JSON'), findsOneWidget);
    expect(find.textContaining('預覽完整備份檔 metadata 與 table diff'), findsOneWidget);
    expect(find.textContaining('RESTORE typed confirmation'), findsOneWidget);
    expect(find.text('backup.json'), findsOneWidget);
    expect(find.textContaining('app_version：3.5.2+148'), findsOneWidget);
    expect(find.textContaining('accounts=2'), findsOneWidget);
    expect(find.text('table diff summary'), findsOneWidget);
    expect(
      find.textContaining('accounts：目前 1 / 備份 2 / 差異 1 / high'),
      findsOneWidget,
    );
  });
}

class _FakeBackupMigrationActionService extends BackupMigrationActionService {
  const _FakeBackupMigrationActionService();

  @override
  Future<SafeImportSourceResult> prepareFullRestoreSource({
    baseDirectory,
    currentDb,
  }) async {
    return const SafeImportSourceResult(
      directoryPath: '/test/import_sources/full_restore',
      title: '完整還原來源',
      message: '請將完整備份 JSON 放入此資料夾。預覽階段不會修改目前資料；輸入 RESTORE 後才可正式還原。',
      allowedExtensions: <String>['json'],
      restorePreviews: <FullRestoreBackupPreview>[
        FullRestoreBackupPreview(
          filePath: '/test/import_sources/full_restore/backup.json',
          fileName: 'backup.json',
          isValid: true,
          message: '可預覽；正式還原前需再次確認。',
          metadata: FullRestoreBackupMetadata(
            appName: 'my_finance_app',
            appVersion: '3.5.2+148',
            phase: 'P3.5.2',
            exportFormatVersion: 1,
            databaseSchemaVersion: 12,
            createdAt: '2026-06-02T01:02:03.000Z',
            sourcePlatform: 'android',
            exportMode: 'full_backup',
          ),
          tableRowCounts: <String, int>{'accounts': 2, 'transactions': 1},
          tableImpacts: <FullRestoreTableImpact>[
            FullRestoreTableImpact(
              tableName: 'accounts',
              currentCount: 1,
              backupCount: 2,
              delta: 1,
              level: FullRestoreImpactLevel.high,
            ),
          ],
        ),
      ],
    );
  }
}

class _NoopDatabaseExecutor implements DatabaseExecutor {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
