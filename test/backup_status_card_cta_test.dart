import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_reminder_due_state.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings.dart';
import 'package:my_finance_app/features/backup/backup_status_card.dart';

void main() {
  test('shouldShowBackupReminderCta returns true only for action-needed states', () {
    expect(shouldShowBackupReminderCta(BackupReminderDueState.noBackupTime), isTrue);
    expect(shouldShowBackupReminderCta(BackupReminderDueState.due), isTrue);
    expect(shouldShowBackupReminderCta(BackupReminderDueState.notDue), isFalse);
    expect(shouldShowBackupReminderCta(BackupReminderDueState.disabled), isFalse);
  });

  testWidgets('BackupStatusCard shows CTA when reminder is due and triggers callback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupStatusCard(
            settings: BackupReminderSettings(enabled: true, intervalDays: 7, lastBackupAt: DateTime.utc(2026, 6, 1, 8)),
            now: DateTime.utc(2026, 6, 8, 8),
            onCreateBackup: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('立即建立完整備份'), findsOneWidget);
    await tester.tap(find.text('立即建立完整備份'));
    expect(tapped, isTrue);
  });

  testWidgets('BackupStatusCard hides CTA when reminder is not due', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupStatusCard(
            settings: BackupReminderSettings(enabled: true, intervalDays: 7, lastBackupAt: DateTime.utc(2026, 6, 1, 8)),
            now: DateTime.utc(2026, 6, 8, 7, 59),
          ),
        ),
      ),
    );

    expect(find.text('立即建立完整備份'), findsNothing);
  });
}
