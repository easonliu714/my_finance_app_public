import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_migration_center.dart';
import 'package:my_finance_app/features/backup/restore_source_grant.dart';

void main() {
  testWidgets('BackupMigrationCenter shows restore source picker before grant', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(onPickFullRestoreSource: () => tapped = true),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('完整還原來源'), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('完整還原來源'), findsOneWidget);
    expect(find.text('未選擇'), findsOneWidget);
    expect(find.text('選擇還原來源'), findsOneWidget);

    await tester.tap(find.text('選擇還原來源'));
    expect(tapped, isTrue);
  });

  testWidgets('BackupMigrationCenter shows persisted restore source grant', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final grant = RestoreSourceGrant(
      uri: '/cloud/drive/backup.json',
      displayName: 'backup.json',
      grantedAt: DateTime.utc(2026, 6, 4, 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(restoreSourceGrant: grant),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('完整還原來源'), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('完整還原來源'), findsOneWidget);
    expect(find.text('已選擇'), findsOneWidget);
    expect(find.text('目前來源：backup.json'), findsOneWidget);
    expect(find.textContaining('/cloud/drive/backup.json'), findsOneWidget);
    expect(find.text('重新選擇還原來源'), findsOneWidget);
  });

  testWidgets('BackupMigrationCenter shows pathless cloud provider fallback state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final grant = RestoreSourceGrant(
      uri: 'provider:drive-backup.json',
      displayName: 'drive-backup.json',
      grantedAt: DateTime.utc(2026, 6, 4, 12),
      pathBacked: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(restoreSourceGrant: grant),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('完整還原來源'), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('完整還原來源'), findsOneWidget);
    expect(find.text('需重新選擇'), findsOneWidget);
    expect(find.text('目前來源：drive-backup.json'), findsOneWidget);
    expect(find.textContaining('目前無法直接讀取這個來源'), findsOneWidget);
    expect(find.text('重新選擇還原來源'), findsOneWidget);
  });
}
