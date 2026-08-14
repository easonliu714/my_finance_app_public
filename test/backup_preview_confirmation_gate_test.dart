import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_preview_confirmation_gate.dart';
import 'package:my_finance_app/features/backup/full_restore_preview_service.dart';

void main() {
  testWidgets('BackupPreviewConfirmationGate requires all checks before commit callback', (tester) async {
    FullRestoreBackupPreview? selectedPreview;
    final preview = _preview();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupPreviewConfirmationGate(
            preview: preview,
            onCommitRestore: (value) => selectedPreview = value,
          ),
        ),
      ),
    );

    expect(find.text('確認門檻'), findsOneWidget);
    expect(find.text('請先完成確認'), findsOneWidget);
    expect(find.text('下一步預留'), findsNothing);
    expect(find.text('進入正式還原確認'), findsNothing);

    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.tap(find.byType(CheckboxListTile).at(2));
    await tester.pumpAndSettle();

    expect(find.text('進入正式還原確認'), findsOneWidget);
    await tester.tap(find.text('進入正式還原確認'));
    await tester.pumpAndSettle();

    expect(selectedPreview, same(preview));
  });

  testWidgets('BackupPreviewConfirmationGate hides invalid preview', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BackupPreviewConfirmationGate(
            preview: FullRestoreBackupPreview(
              filePath: '/tmp/bad.json',
              fileName: 'bad.json',
              isValid: false,
              message: 'bad',
              metadata: null,
              tableRowCounts: <String, int>{},
            ),
          ),
        ),
      ),
    );

    expect(find.text('確認門檻'), findsNothing);
  });
}

FullRestoreBackupPreview _preview() {
  return const FullRestoreBackupPreview(
    filePath: '/tmp/full_backup.json',
    fileName: 'full_backup.json',
    isValid: true,
    message: '可預覽',
    metadata: FullRestoreBackupMetadata(
      appName: 'my_finance_app',
      appVersion: '3.15.0+223',
      phase: 'P3.15.0',
      exportFormatVersion: 1,
      databaseSchemaVersion: 12,
      createdAt: '2026-06-07T00:00:00.000Z',
      sourcePlatform: 'android',
      exportMode: 'full_backup',
    ),
    tableRowCounts: <String, int>{'accounts': 1, 'transactions': 1},
  );
}
