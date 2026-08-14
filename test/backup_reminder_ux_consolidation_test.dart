import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_migration_center.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings.dart';
import 'package:my_finance_app/features/backup/backup_status_card.dart';

void main() {
  testWidgets('BackupMigrationCenter shows reminder due state and CTA for first-time backup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var backupTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(
            reminderSettings: BackupReminderSettings.defaults(),
            onFullBackup: () => backupTapped = true,
          ),
        ),
      ),
    );

    await _scrollToReminderSection(tester);
    expect(find.text('備份提醒'), findsOneWidget);
    expect(find.text('提醒狀態：尚無上次備份時間'), findsOneWidget);
    expect(find.text('立即建立完整備份'), findsOneWidget);

    final backupButton = find.text('立即建立完整備份');
    await tester.tap(backupButton);
    expect(backupTapped, isTrue);
  });

  testWidgets('BackupMigrationCenter shows manual notification CTA when callback is present', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var notificationTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(
            reminderSettings: BackupReminderSettings.defaults(),
            onSendReminderNotification: () => notificationTapped = true,
          ),
        ),
      ),
    );

    final notificationButton = find.byKey(BackupStatusCard.reminderNotificationSmokeButtonKey);
    await tester.scrollUntilVisible(notificationButton, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(notificationButton, findsOneWidget);

    await tester.tap(notificationButton);
    expect(notificationTapped, isTrue);
  });

  testWidgets('BackupMigrationCenter hides reminder CTA when backup is not due', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(
            reminderSettings: BackupReminderSettings(
              enabled: true,
              intervalDays: 7,
              lastBackupAt: DateTime.now().toUtc(),
            ),
          ),
        ),
      ),
    );

    await _scrollToReminderSection(tester);
    expect(find.text('備份提醒'), findsOneWidget);
    expect(find.text('提醒狀態：尚未到期'), findsOneWidget);
    expect(find.text('立即建立完整備份'), findsNothing);
  });

  testWidgets('BackupMigrationCenter keeps backup reminder controls disabled when callbacks are absent', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BackupMigrationCenter(),
        ),
      ),
    );

    await _scrollToReminderSection(tester);
    expect(find.text('備份提醒'), findsOneWidget);

    final switchTile = tester.widget<SwitchListTile>(find.byKey(BackupStatusCard.reminderEnabledSwitchKey));
    expect(switchTile.value, isFalse);
    expect(switchTile.onChanged, isNull);

    final dropdown = tester.widget<DropdownButton<int>>(find.byKey(BackupStatusCard.reminderIntervalDropdownKey));
    expect(dropdown.value, 7);
    expect(dropdown.onChanged, isNull);

    expect(find.byKey(BackupStatusCard.reminderNotificationSmokeButtonKey), findsNothing);

    await tester.scrollUntilVisible(find.text('備份通知'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('備份通知'), findsOneWidget);
  });
}

Future<void> _scrollToReminderSection(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('備份提醒'), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}
