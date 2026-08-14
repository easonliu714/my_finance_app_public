import 'backup_notification_settings.dart';
import 'backup_reminder_due_state.dart';
import 'backup_reminder_settings.dart';

abstract class LocalBackupReminderNotificationPort {
  Future<void> showBackupReminder(LocalBackupReminderNotification notification);
}

abstract class BackupNotificationPermissionPort {
  Future<BackupNotificationPermissionStatus> requestPermission();
}

class LocalBackupReminderNotification {
  const LocalBackupReminderNotification({
    required this.title,
    required this.body,
    required this.dueState,
    required this.createdAt,
  });

  final String title;
  final String body;
  final BackupReminderDueState dueState;
  final DateTime createdAt;
}

class LocalBackupReminderNotificationResult {
  const LocalBackupReminderNotificationResult._({
    required this.sent,
    required this.reason,
    required this.dueState,
    this.notification,
  });

  factory LocalBackupReminderNotificationResult.sent({
    required BackupReminderDueState dueState,
    required LocalBackupReminderNotification notification,
  }) {
    return LocalBackupReminderNotificationResult._(
      sent: true,
      reason: LocalBackupReminderNotificationSkipReason.sent,
      dueState: dueState,
      notification: notification,
    );
  }

  factory LocalBackupReminderNotificationResult.skipped({
    required LocalBackupReminderNotificationSkipReason reason,
    required BackupReminderDueState dueState,
  }) {
    return LocalBackupReminderNotificationResult._(
      sent: false,
      reason: reason,
      dueState: dueState,
    );
  }

  final bool sent;
  final LocalBackupReminderNotificationSkipReason reason;
  final BackupReminderDueState dueState;
  final LocalBackupReminderNotification? notification;
}

enum LocalBackupReminderNotificationSkipReason {
  sent,
  reminderDisabled,
  notificationDisabled,
  permissionNotGranted,
  notDue,
}

class LocalBackupReminderNotificationService {
  const LocalBackupReminderNotificationService({required this.port});

  final LocalBackupReminderNotificationPort port;

  Future<LocalBackupReminderNotificationResult> sendDueReminder({
    required BackupReminderSettings reminderSettings,
    required BackupNotificationSettings notificationSettings,
    required DateTime now,
  }) async {
    final dueState = resolveBackupReminderDueState(reminderSettings, now: now);
    if (dueState == BackupReminderDueState.disabled) {
      return LocalBackupReminderNotificationResult.skipped(
        reason: LocalBackupReminderNotificationSkipReason.reminderDisabled,
        dueState: dueState,
      );
    }
    if (!_isNotificationReady(notificationSettings)) {
      return _skipForNotificationReadiness(notificationSettings, dueState: dueState);
    }
    if (!shouldShowBackupReminderCta(dueState)) {
      return LocalBackupReminderNotificationResult.skipped(
        reason: LocalBackupReminderNotificationSkipReason.notDue,
        dueState: dueState,
      );
    }

    final notification = LocalBackupReminderNotification(
      title: '備份提醒',
      body: dueState == BackupReminderDueState.noBackupTime ? '尚未建立完整備份，建議立即建立一次完整備份。' : '已到達備份提醒週期，建議建立完整備份。',
      dueState: dueState,
      createdAt: now.toUtc(),
    );
    await port.showBackupReminder(notification);
    return LocalBackupReminderNotificationResult.sent(dueState: dueState, notification: notification);
  }

  Future<LocalBackupReminderNotificationResult> sendSmokeReminder({
    required BackupNotificationSettings notificationSettings,
    required DateTime now,
  }) async {
    const dueState = BackupReminderDueState.due;
    if (!_isNotificationReady(notificationSettings)) {
      return _skipForNotificationReadiness(notificationSettings, dueState: dueState);
    }
    final notification = LocalBackupReminderNotification(
      title: '備份提醒',
      body: '這是一則備份提醒測試通知。若你看得到這則通知，代表 Android 實機通知已可使用。',
      dueState: dueState,
      createdAt: now.toUtc(),
    );
    await port.showBackupReminder(notification);
    return LocalBackupReminderNotificationResult.sent(dueState: dueState, notification: notification);
  }

  bool _isNotificationReady(BackupNotificationSettings settings) {
    return settings.enabled && settings.permissionStatus == BackupNotificationPermissionStatus.granted;
  }

  LocalBackupReminderNotificationResult _skipForNotificationReadiness(
    BackupNotificationSettings settings, {
    required BackupReminderDueState dueState,
  }) {
    if (!settings.enabled) {
      return LocalBackupReminderNotificationResult.skipped(
        reason: LocalBackupReminderNotificationSkipReason.notificationDisabled,
        dueState: dueState,
      );
    }
    return LocalBackupReminderNotificationResult.skipped(
      reason: LocalBackupReminderNotificationSkipReason.permissionNotGranted,
      dueState: dueState,
    );
  }
}

class NoopBackupReminderNotificationPort implements LocalBackupReminderNotificationPort, BackupNotificationPermissionPort {
  const NoopBackupReminderNotificationPort();

  @override
  Future<void> showBackupReminder(LocalBackupReminderNotification notification) async {}

  @override
  Future<BackupNotificationPermissionStatus> requestPermission() async {
    return BackupNotificationPermissionStatus.unsupported;
  }
}

class InMemoryBackupReminderNotificationPort implements LocalBackupReminderNotificationPort, BackupNotificationPermissionPort {
  InMemoryBackupReminderNotificationPort({this.permissionStatus = BackupNotificationPermissionStatus.granted});

  final BackupNotificationPermissionStatus permissionStatus;
  final List<LocalBackupReminderNotification> notifications = <LocalBackupReminderNotification>[];

  @override
  Future<void> showBackupReminder(LocalBackupReminderNotification notification) async {
    notifications.add(notification);
  }

  @override
  Future<BackupNotificationPermissionStatus> requestPermission() async {
    return permissionStatus;
  }
}
