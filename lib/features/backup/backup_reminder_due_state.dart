import 'backup_reminder_settings.dart';

BackupReminderDueState resolveBackupReminderDueState(BackupReminderSettings settings, {required DateTime now}) {
  if (!settings.enabled) return BackupReminderDueState.disabled;
  if (settings.lastBackupAt == null) return BackupReminderDueState.noBackupTime;
  return settings.isReminderDue(now) ? BackupReminderDueState.due : BackupReminderDueState.notDue;
}

bool shouldShowBackupReminderCta(BackupReminderDueState status) {
  return status == BackupReminderDueState.noBackupTime || status == BackupReminderDueState.due;
}

enum BackupReminderDueState {
  disabled('已停用'),
  noBackupTime('尚無上次備份時間'),
  notDue('尚未到期'),
  due('已到期，建議備份');

  const BackupReminderDueState(this.label);

  final String label;
}
