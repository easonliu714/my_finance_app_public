import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_reminder_due_state.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings.dart';

void main() {
  test('resolveBackupReminderDueState returns no backup time when enabled without timestamp', () {
    final settings = BackupReminderSettings.defaults();

    expect(resolveBackupReminderDueState(settings, now: DateTime.utc(2026, 6, 4)), BackupReminderDueState.noBackupTime);
  });

  test('resolveBackupReminderDueState returns notDue before next reminder time', () {
    final settings = BackupReminderSettings(enabled: true, intervalDays: 7, lastBackupAt: DateTime.utc(2026, 6, 1, 8));

    expect(resolveBackupReminderDueState(settings, now: DateTime.utc(2026, 6, 8, 7, 59)), BackupReminderDueState.notDue);
  });

  test('resolveBackupReminderDueState returns due at next reminder time', () {
    final settings = BackupReminderSettings(enabled: true, intervalDays: 7, lastBackupAt: DateTime.utc(2026, 6, 1, 8));

    expect(resolveBackupReminderDueState(settings, now: DateTime.utc(2026, 6, 8, 8)), BackupReminderDueState.due);
  });

  test('resolveBackupReminderDueState returns disabled when reminder is off', () {
    final settings = BackupReminderSettings(enabled: false, intervalDays: 7, lastBackupAt: DateTime.utc(2026, 6, 1, 8));

    expect(resolveBackupReminderDueState(settings, now: DateTime.utc(2026, 6, 20)), BackupReminderDueState.disabled);
  });
}
