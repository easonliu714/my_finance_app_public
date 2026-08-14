import 'package:flutter/material.dart';

import 'backup_reminder_due_state.dart';
import 'backup_reminder_settings.dart';

class BackupStatusCard extends StatelessWidget {
  const BackupStatusCard({
    super.key,
    required this.settings,
    this.now,
    this.onEnabledChanged,
    this.onIntervalDaysChanged,
    this.onAutomaticBackupEnabledChanged,
    this.onNetworkUsageAllowedChanged,
    this.onCloudBackupHandoffEnabledChanged,
    this.onCreateBackup,
    this.onSendReminderNotification,
  });

  static const Key reminderEnabledSwitchKey = Key('backup_reminder_enabled_switch');
  static const Key reminderIntervalDropdownKey = Key('backup_reminder_interval_dropdown');
  static const Key automaticBackupSwitchKey = Key('backup_automatic_enabled_switch');
  static const Key networkUsageSwitchKey = Key('backup_network_usage_switch');
  static const Key cloudBackupHandoffSwitchKey = Key('backup_cloud_handoff_switch');
  static const Key reminderNotificationSmokeButtonKey = Key('backup_reminder_notification_smoke_button');

  final BackupReminderSettings settings;
  final DateTime? now;
  final ValueChanged<bool>? onEnabledChanged;
  final ValueChanged<int>? onIntervalDaysChanged;
  final ValueChanged<bool>? onAutomaticBackupEnabledChanged;
  final ValueChanged<bool>? onNetworkUsageAllowedChanged;
  final ValueChanged<bool>? onCloudBackupHandoffEnabledChanged;
  final VoidCallback? onCreateBackup;
  final VoidCallback? onSendReminderNotification;

  @override
  Widget build(BuildContext context) {
    final next = settings.nextReminderAt();
    final status = resolveBackupReminderDueState(settings, now: now ?? DateTime.now());
    final showBackupCta = shouldShowBackupReminderCta(status);
    final nextText = next == null ? '下次提醒：尚無上次備份時間' : '下次提醒：${_formatDateTime(next)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('備份提醒', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SwitchListTile(
              key: reminderEnabledSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(settings.enabled ? '提醒：已開啟' : '提醒：已關閉'),
              subtitle: const Text('開啟後，App 會依你設定的週期提醒你建立完整備份。'),
              value: settings.enabled,
              onChanged: onEnabledChanged,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('提醒週期')),
                DropdownButton<int>(
                  key: reminderIntervalDropdownKey,
                  value: _supportedInterval(settings.intervalDays),
                  onChanged: onIntervalDaysChanged == null
                      ? null
                      : (value) {
                          if (value != null) onIntervalDaysChanged!(value);
                        },
                  items: const [
                    DropdownMenuItem<int>(value: 1, child: Text('每天')),
                    DropdownMenuItem<int>(value: 7, child: Text('每 7 天')),
                    DropdownMenuItem<int>(value: 14, child: Text('每 14 天')),
                    DropdownMenuItem<int>(value: 30, child: Text('每 30 天')),
                  ],
                ),
              ],
            ),
            Text('目前週期：每 ${settings.intervalDays} 天'),
            Text(nextText),
            Text('提醒狀態：${status.label}', style: TextStyle(fontWeight: FontWeight.w800, color: _statusColor(context, status))),
            if (showBackupCta) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: onCreateBackup,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('立即建立完整備份'),
                  ),
                  FilledButton.tonalIcon(
                    key: reminderNotificationSmokeButtonKey,
                    onPressed: onSendReminderNotification,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('發送測試提醒'),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            SwitchListTile(
              key: automaticBackupSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(settings.automaticBackupEnabled ? '自動建立備份：已開啟' : '自動建立備份：已關閉'),
              subtitle: const Text('開啟後，App 會在你開啟此頁且備份週期已到期時，自動建立本機完整備份。背景自動備份仍受 Android 系統限制。'),
              value: settings.automaticBackupEnabled,
              onChanged: onAutomaticBackupEnabledChanged,
            ),
            SwitchListTile(
              key: networkUsageSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(settings.networkUsageAllowed ? '允許備份使用網路流量' : '不允許備份使用網路流量'),
              subtitle: const Text('若備份目的地是雲端或外部 provider，可能會使用行動網路或 Wi-Fi 流量。關閉時只允許本機備份流程。'),
              value: settings.networkUsageAllowed,
              onChanged: settings.automaticBackupEnabled ? onNetworkUsageAllowedChanged : null,
            ),
            SwitchListTile(
              key: cloudBackupHandoffSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(settings.cloudBackupHandoffEnabled ? '自動雲端備份交接：已開啟' : '自動雲端備份交接：已關閉'),
              subtitle: const Text('到期自動建立本機備份後，會開啟系統分享面板交給 Google Drive、iCloud Drive 或其他雲端 App。需允許網路流量。'),
              value: settings.cloudBackupHandoffEnabled,
              onChanged: settings.automaticBackupEnabled && settings.networkUsageAllowed ? onCloudBackupHandoffEnabledChanged : null,
            ),
            if (settings.automaticBackupEnabled && !settings.networkUsageAllowed)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('目前自動備份限制為本機備份；不會自動上傳雲端。'),
              ),
            if (settings.automaticBackupEnabled && settings.networkUsageAllowed && !settings.cloudBackupHandoffEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('已允許網路流量；雲端備份交接仍需另外開啟。'),
              ),
            if (settings.automaticBackupEnabled && settings.networkUsageAllowed && settings.cloudBackupHandoffEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('注意：自動雲端備份交接會開啟系統分享面板，實際上傳由你選擇的雲端 App 完成，可能使用行動網路或 Wi-Fi。', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 8),
            const Text('建議定期建立完整備份，尤其是在換手機、重裝 App 或大量修改資料前。'),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, BackupReminderDueState status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case BackupReminderDueState.due:
      return scheme.error;
    case BackupReminderDueState.notDue:
      return Colors.green.shade700;
    case BackupReminderDueState.noBackupTime:
    case BackupReminderDueState.disabled:
      return scheme.primary;
  }
}

int _supportedInterval(int value) {
  if (value <= 1) return 1;
  if (value <= 7) return 7;
  if (value <= 14) return 14;
  return 30;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
