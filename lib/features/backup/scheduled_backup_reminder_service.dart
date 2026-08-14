import 'backup_notification_settings.dart';
import 'backup_reminder_settings.dart';

abstract class ScheduledBackupReminderPort {
  Future<void> schedule(ScheduledBackupReminderRequest request);
  Future<void> cancel();
}

class ScheduledBackupReminderRequest {
  const ScheduledBackupReminderRequest({
    required this.scheduledAt,
    required this.intervalDays,
  });

  final DateTime scheduledAt;
  final int intervalDays;
}

class ScheduledBackupReminderDecision {
  const ScheduledBackupReminderDecision._({
    required this.action,
    required this.reason,
    this.scheduledAt,
  });

  factory ScheduledBackupReminderDecision.schedule({required DateTime scheduledAt}) {
    return ScheduledBackupReminderDecision._(
      action: ScheduledBackupReminderAction.schedule,
      reason: ScheduledBackupReminderReason.ready,
      scheduledAt: scheduledAt,
    );
  }

  factory ScheduledBackupReminderDecision.cancel(ScheduledBackupReminderReason reason) {
    return ScheduledBackupReminderDecision._(
      action: ScheduledBackupReminderAction.cancel,
      reason: reason,
    );
  }

  final ScheduledBackupReminderAction action;
  final ScheduledBackupReminderReason reason;
  final DateTime? scheduledAt;

  bool get shouldSchedule => action == ScheduledBackupReminderAction.schedule;
}

enum ScheduledBackupReminderAction { schedule, cancel }

enum ScheduledBackupReminderReason {
  ready,
  reminderDisabled,
  notificationDisabled,
  permissionNotGranted,
  unsupported,
}

class ScheduledBackupReminderService {
  const ScheduledBackupReminderService({required this.port});

  final ScheduledBackupReminderPort port;

  ScheduledBackupReminderDecision decide({
    required BackupReminderSettings reminderSettings,
    required BackupNotificationSettings notificationSettings,
    required DateTime now,
  }) {
    if (!reminderSettings.enabled) {
      return ScheduledBackupReminderDecision.cancel(ScheduledBackupReminderReason.reminderDisabled);
    }
    if (!notificationSettings.enabled) {
      return ScheduledBackupReminderDecision.cancel(ScheduledBackupReminderReason.notificationDisabled);
    }
    switch (notificationSettings.permissionStatus) {
      case BackupNotificationPermissionStatus.granted:
        break;
      case BackupNotificationPermissionStatus.unsupported:
        return ScheduledBackupReminderDecision.cancel(ScheduledBackupReminderReason.unsupported);
      case BackupNotificationPermissionStatus.notRequested:
      case BackupNotificationPermissionStatus.denied:
        return ScheduledBackupReminderDecision.cancel(ScheduledBackupReminderReason.permissionNotGranted);
    }

    final next = reminderSettings.nextReminderAt() ?? now;
    final scheduledAt = now.isAfter(next) ? now : next;
    return ScheduledBackupReminderDecision.schedule(scheduledAt: scheduledAt.toUtc());
  }

  Future<ScheduledBackupReminderDecision> reconcile({
    required BackupReminderSettings reminderSettings,
    required BackupNotificationSettings notificationSettings,
    required DateTime now,
  }) async {
    final decision = decide(
      reminderSettings: reminderSettings,
      notificationSettings: notificationSettings,
      now: now,
    );
    if (decision.shouldSchedule) {
      await port.schedule(
        ScheduledBackupReminderRequest(
          scheduledAt: decision.scheduledAt!,
          intervalDays: reminderSettings.intervalDays,
        ),
      );
    } else {
      await port.cancel();
    }
    return decision;
  }
}

class NoopScheduledBackupReminderPort implements ScheduledBackupReminderPort {
  const NoopScheduledBackupReminderPort();

  @override
  Future<void> schedule(ScheduledBackupReminderRequest request) async {}

  @override
  Future<void> cancel() async {}
}

class InMemoryScheduledBackupReminderPort implements ScheduledBackupReminderPort {
  final List<ScheduledBackupReminderRequest> scheduledRequests = <ScheduledBackupReminderRequest>[];
  var cancelCount = 0;

  @override
  Future<void> schedule(ScheduledBackupReminderRequest request) async {
    scheduledRequests.add(request);
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }
}
