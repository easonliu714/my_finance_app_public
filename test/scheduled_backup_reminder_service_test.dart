import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_notification_settings.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings.dart';
import 'package:my_finance_app/features/backup/scheduled_backup_reminder_service.dart';

void main() {
  BackupNotificationSettings readyNotifications() {
    return const BackupNotificationSettings(
      enabled: true,
      permissionStatus: BackupNotificationPermissionStatus.granted,
      updatedAt: null,
    );
  }

  test('decide schedules immediately when backup time is missing', () {
    final service = ScheduledBackupReminderService(port: InMemoryScheduledBackupReminderPort());
    final now = DateTime.utc(2026, 6, 6, 8);

    final decision = service.decide(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: readyNotifications(),
      now: now,
    );

    expect(decision.action, ScheduledBackupReminderAction.schedule);
    expect(decision.reason, ScheduledBackupReminderReason.ready);
    expect(decision.scheduledAt, now);
  });

  test('decide schedules at next reminder when future reminder exists', () {
    final service = ScheduledBackupReminderService(port: InMemoryScheduledBackupReminderPort());

    final decision = service.decide(
      reminderSettings: BackupReminderSettings(
        enabled: true,
        intervalDays: 7,
        lastBackupAt: DateTime.utc(2026, 6, 1, 8),
      ),
      notificationSettings: readyNotifications(),
      now: DateTime.utc(2026, 6, 6, 8),
    );

    expect(decision.shouldSchedule, isTrue);
    expect(decision.scheduledAt, DateTime.utc(2026, 6, 8, 8));
  });

  test('decide schedules immediately when next reminder is already past', () {
    final service = ScheduledBackupReminderService(port: InMemoryScheduledBackupReminderPort());
    final now = DateTime.utc(2026, 6, 10, 8);

    final decision = service.decide(
      reminderSettings: BackupReminderSettings(
        enabled: true,
        intervalDays: 7,
        lastBackupAt: DateTime.utc(2026, 6, 1, 8),
      ),
      notificationSettings: readyNotifications(),
      now: now,
    );

    expect(decision.shouldSchedule, isTrue);
    expect(decision.scheduledAt, now);
  });

  test('decide cancels when reminder is disabled', () {
    final service = ScheduledBackupReminderService(port: InMemoryScheduledBackupReminderPort());

    final decision = service.decide(
      reminderSettings: const BackupReminderSettings(enabled: false, intervalDays: 7),
      notificationSettings: readyNotifications(),
      now: DateTime.utc(2026, 6, 6, 8),
    );

    expect(decision.action, ScheduledBackupReminderAction.cancel);
    expect(decision.reason, ScheduledBackupReminderReason.reminderDisabled);
  });

  test('decide cancels when notification is disabled', () {
    final service = ScheduledBackupReminderService(port: InMemoryScheduledBackupReminderPort());

    final decision = service.decide(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: const BackupNotificationSettings(
        enabled: false,
        permissionStatus: BackupNotificationPermissionStatus.granted,
        updatedAt: null,
      ),
      now: DateTime.utc(2026, 6, 6, 8),
    );

    expect(decision.action, ScheduledBackupReminderAction.cancel);
    expect(decision.reason, ScheduledBackupReminderReason.notificationDisabled);
  });

  test('decide cancels when notification permission is not granted', () {
    final service = ScheduledBackupReminderService(port: InMemoryScheduledBackupReminderPort());

    final decision = service.decide(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: const BackupNotificationSettings(
        enabled: true,
        permissionStatus: BackupNotificationPermissionStatus.denied,
        updatedAt: null,
      ),
      now: DateTime.utc(2026, 6, 6, 8),
    );

    expect(decision.action, ScheduledBackupReminderAction.cancel);
    expect(decision.reason, ScheduledBackupReminderReason.permissionNotGranted);
  });

  test('reconcile sends schedule request to port', () async {
    final port = InMemoryScheduledBackupReminderPort();
    final service = ScheduledBackupReminderService(port: port);
    final now = DateTime.utc(2026, 6, 6, 8);

    final decision = await service.reconcile(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: readyNotifications(),
      now: now,
    );

    expect(decision.shouldSchedule, isTrue);
    expect(port.scheduledRequests, hasLength(1));
    expect(port.scheduledRequests.single.scheduledAt, now);
    expect(port.scheduledRequests.single.intervalDays, BackupReminderSettings.defaultIntervalDays);
    expect(port.cancelCount, 0);
  });

  test('reconcile cancels through port when not ready', () async {
    final port = InMemoryScheduledBackupReminderPort();
    final service = ScheduledBackupReminderService(port: port);

    final decision = await service.reconcile(
      reminderSettings: BackupReminderSettings.defaults(),
      notificationSettings: BackupNotificationSettings.defaults(),
      now: DateTime.utc(2026, 6, 6, 8),
    );

    expect(decision.action, ScheduledBackupReminderAction.cancel);
    expect(port.scheduledRequests, isEmpty);
    expect(port.cancelCount, 1);
  });
}
