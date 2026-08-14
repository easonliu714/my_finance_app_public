import 'package:flutter/material.dart';

import 'backup_notification_settings.dart';

class BackupNotificationStatusCard extends StatelessWidget {
  const BackupNotificationStatusCard({
    super.key,
    required this.settings,
    this.onEnabledChanged,
    this.onPermissionStatusChanged,
    this.onRequestPermission,
    this.onSendSmokeNotification,
  });

  static const Key requestPermissionButtonKey = Key('backup_notification_request_permission_button');
  static const Key smokeNotificationButtonKey = Key('backup_notification_smoke_button');

  final BackupNotificationSettings settings;
  final ValueChanged<bool>? onEnabledChanged;
  final ValueChanged<BackupNotificationPermissionStatus>? onPermissionStatusChanged;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onSendSmokeNotification;

  @override
  Widget build(BuildContext context) {
    final readinessLabel = settings.isReady ? '可通知' : '尚未可通知';
    final updatedText = settings.updatedAt == null ? '尚未更新' : _formatDateTime(settings.updatedAt!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '備份通知',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: Text(readinessLabel)),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(settings.enabled ? '通知：已開啟' : '通知：已關閉'),
              subtitle: const Text('允許通知後，App 可以發送備份提醒。'),
              value: settings.enabled,
              onChanged: onEnabledChanged,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('系統通知權限')),
                DropdownButton<BackupNotificationPermissionStatus>(
                  value: settings.permissionStatus,
                  onChanged: onPermissionStatusChanged == null
                      ? null
                      : (value) {
                          if (value != null) onPermissionStatusChanged!(value);
                        },
                  items: BackupNotificationPermissionStatus.values
                      .map((status) => DropdownMenuItem<BackupNotificationPermissionStatus>(
                            value: status,
                            child: Text(status.label),
                          ))
                      .toList(),
                ),
              ],
            ),
            Text('目前權限：${settings.permissionStatus.label}'),
            Text('更新時間：$updatedText'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.icon(
                  key: requestPermissionButtonKey,
                  onPressed: onRequestPermission,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('要求系統通知權限'),
                ),
                FilledButton.tonalIcon(
                  key: smokeNotificationButtonKey,
                  onPressed: onSendSmokeNotification,
                  icon: const Icon(Icons.notification_add_outlined),
                  label: const Text('發送測試通知'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('如果通知未開啟或系統權限未允許，App 不會發送備份提醒。'),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
