import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_notification_settings.dart';
import 'package:my_finance_app/features/backup/backup_reminder_due_state.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings.dart';
import 'package:my_finance_app/features/backup/local_backup_reminder_notification_service.dart';

void main() {
  BackupNotificationSettings readyNotificationSettings() {
    return const BackupNotificationSettings(
      enabled: true,
      permissionStatus: BackupNotificationPermissionStatus.granted,
      updatedAt: null,
    );
  }

  test('sendDueReminder emits notification when no backup time is available', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendDueReminder(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: readyNotificationSettings(),
      now: DateTime.utc(2026, 6, 6, 12),
    );

    expect(result.sent, isTrue);
    expect(result.reason, LocalBackupReminderNotificationSkipReason.sent);
    expect(result.dueState, BackupReminderDueState.noBackupTime);
    expect(port.notifications, hasLength(1));
    expect(port.notifications.single.title, '備份提醒');
    expect(port.notifications.single.body, contains('尚未建立完整備份'));
  });

  test('sendDueReminder emits notification when interval is due', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendDueReminder(
      reminderSettings: BackupReminderSettings(
        enabled: true,
        intervalDays: 7,
        lastBackupAt: DateTime.utc(2026, 6, 1, 8),
      ),
      notificationSettings: readyNotificationSettings(),
      now: DateTime.utc(2026, 6, 8, 8),
    );

    expect(result.sent, isTrue);
    expect(result.dueState, BackupReminderDueState.due);
    expect(port.notifications.single.body, contains('已到達備份提醒週期'));
  });

  test('sendDueReminder skips when reminder is not due', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendDueReminder(
      reminderSettings: BackupReminderSettings(
        enabled: true,
        intervalDays: 7,
        lastBackupAt: DateTime.utc(2026, 6, 1, 8),
      ),
      notificationSettings: readyNotificationSettings(),
      now: DateTime.utc(2026, 6, 8, 7, 59),
    );

    expect(result.sent, isFalse);
    expect(result.reason, LocalBackupReminderNotificationSkipReason.notDue);
    expect(result.dueState, BackupReminderDueState.notDue);
    expect(port.notifications, isEmpty);
  });

  test('sendSmokeReminder emits notification even when backup reminder is not due', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendSmokeReminder(
      notificationSettings: readyNotificationSettings(),
      now: DateTime.utc(2026, 6, 8, 7, 59),
    );

    expect(result.sent, isTrue);
    expect(result.reason, LocalBackupReminderNotificationSkipReason.sent);
    expect(result.dueState, BackupReminderDueState.due);
    expect(port.notifications, hasLength(1));
    expect(port.notifications.single.body, contains('測試通知'));
  });

  test('sendSmokeReminder skips when notification is disabled', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendSmokeReminder(
      notificationSettings: const BackupNotificationSettings(
        enabled: false,
        permissionStatus: BackupNotificationPermissionStatus.granted,
        updatedAt: null,
      ),
      now: DateTime.utc(2026, 6, 8, 7, 59),
    );

    expect(result.sent, isFalse);
    expect(result.reason, LocalBackupReminderNotificationSkipReason.notificationDisabled);
    expect(port.notifications, isEmpty);
  });

  test('sendDueReminder skips when notification is disabled', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendDueReminder(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: const BackupNotificationSettings(
        enabled: false,
        permissionStatus: BackupNotificationPermissionStatus.granted,
        updatedAt: null,
      ),
      now: DateTime.utc(2026, 6, 6, 12),
    );

    expect(result.sent, isFalse);
    expect(result.reason, LocalBackupReminderNotificationSkipReason.notificationDisabled);
    expect(port.notifications, isEmpty);
  });

  test('sendDueReminder skips when permission is not granted', () async {
    final port = InMemoryBackupReminderNotificationPort();
    final service = LocalBackupReminderNotificationService(port: port);

    final result = await service.sendDueReminder(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: const BackupNotificationSettings(
        enabled: true,
        permissionStatus: BackupNotificationPermissionStatus.denied,
        updatedAt: null,
      ),
      now: DateTime.utc(2026, 6, 6, 12),
    );

    expect(result.sent, isFalse);
    expect(result.reason, LocalBackupReminderNotificationSkipReason.permissionNotGranted);
    expect(port.notifications, isEmpty);
  });
}
