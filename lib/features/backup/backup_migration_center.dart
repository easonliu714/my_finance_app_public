import 'package:flutter/material.dart';

import '../invoice/gemini/gemini_invoice_settings_card.dart';
import 'backup_notification_settings.dart';
import 'backup_notification_status_card.dart';
import 'backup_reminder_settings.dart';
import 'backup_status_card.dart';
import 'restore_source_grant.dart';

class BackupMigrationCenter extends StatelessWidget {
  const BackupMigrationCenter({
    super.key,
    this.onFullBackup,
    this.onFullRestore,
    this.onPickFullRestoreSource,
    this.onReadableExport,
    this.onReadableImportReview,
    this.onPickReadableImportFile,
    this.reminderSettings,
    this.notificationSettings,
    this.restoreSourceGrant,
    this.onReminderEnabledChanged,
    this.onReminderIntervalDaysChanged,
    this.onAutomaticBackupEnabledChanged,
    this.onNetworkUsageAllowedChanged,
    this.onCloudBackupHandoffEnabledChanged,
    this.onNotificationEnabledChanged,
    this.onNotificationPermissionStatusChanged,
    this.onRequestNotificationPermission,
    this.onSendReminderNotification,
    this.registryUpdateSection,
  });

  static const String appVersion = '4.10.21+306';
  static const String phase = 'P4.10.21-cleanup';
  static const BackupReminderSettings _readOnlyReminderSettings =
      BackupReminderSettings(
    enabled: false,
    intervalDays: BackupReminderSettings.defaultIntervalDays,
  );

  final VoidCallback? onFullBackup;
  final VoidCallback? onFullRestore;
  final VoidCallback? onPickFullRestoreSource;
  final VoidCallback? onReadableExport;
  final VoidCallback? onReadableImportReview;
  final VoidCallback? onPickReadableImportFile;
  final BackupReminderSettings? reminderSettings;
  final BackupNotificationSettings? notificationSettings;
  final RestoreSourceGrant? restoreSourceGrant;
  final ValueChanged<bool>? onReminderEnabledChanged;
  final ValueChanged<int>? onReminderIntervalDaysChanged;
  final ValueChanged<bool>? onAutomaticBackupEnabledChanged;
  final ValueChanged<bool>? onNetworkUsageAllowedChanged;
  final ValueChanged<bool>? onCloudBackupHandoffEnabledChanged;
  final ValueChanged<bool>? onNotificationEnabledChanged;
  final ValueChanged<BackupNotificationPermissionStatus>?
      onNotificationPermissionStatusChanged;
  final VoidCallback? onRequestNotificationPermission;
  final VoidCallback? onSendReminderNotification;
  final Widget? registryUpdateSection;

  @override
  Widget build(BuildContext context) {
    final settings = reminderSettings ?? _readOnlyReminderSettings;
    final notifications =
        notificationSettings ?? BackupNotificationSettings.defaults();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _CenterSectionLabel(
          title: 'AI 發票辨識',
          description: '設定 Gemini API Key、模型與實驗功能。',
          helpTitle: 'AI 發票辨識設定',
          helpBody:
              '可輸入多組 Google AI Studio API Key。App 會將 Key 保存在 Android 安全儲存空間，並在額度受限時由辨識服務依序切換。\n\n測試功能會讀取該 Key 可用且支援 generateContent 的模型清單。發票辨識仍先建立可編輯草稿，未經人工確認不會寫入正式交易。',
        ),
        const SizedBox(height: 12),
        const GeminiInvoiceSettingsCard(),
        if (registryUpdateSection != null) ...[
          const SizedBox(height: 24),
          const _CenterSectionLabel(
            title: '公司行號資料',
            description: '查看本機官方登記資料版本，並由你明確啟動更新。',
            helpTitle: '公司行號資料更新',
            helpBody:
                '發票覆核會優先查詢已安裝的本機公司行號資料，不會因每張發票直接連線到政府 API。\n\n手動更新時，App 會先下載並驗證版本、大小與 SHA-256，完整驗證成功後才原子切換；失敗時保留上一版資料。官方登記名稱只作佐證，不會覆寫你使用的正式商家名稱或歷史發票文字。',
          ),
          const SizedBox(height: 12),
          registryUpdateSection!,
        ],
        const SizedBox(height: 24),
        const _CenterSectionLabel(
          title: '備份與移轉',
          description: '選擇要執行的備份、還原或交易檔匯入方式。',
          helpTitle: '備份與移轉說明',
          helpBody:
              '完整模式適合換手機、重裝 App 或整包復原。readable 模式適合人工檢查或只匯入一批交易。\n\nApp 不會靜默上傳或覆蓋資料；正式寫入前會再次要求確認。',
        ),
        const SizedBox(height: 12),
        BackupStatusCard(
          settings: settings,
          onEnabledChanged: onReminderEnabledChanged,
          onIntervalDaysChanged: onReminderIntervalDaysChanged,
          onAutomaticBackupEnabledChanged: onAutomaticBackupEnabledChanged,
          onNetworkUsageAllowedChanged: onNetworkUsageAllowedChanged,
          onCloudBackupHandoffEnabledChanged:
              onCloudBackupHandoffEnabledChanged,
          onCreateBackup: onFullBackup,
          onSendReminderNotification: onSendReminderNotification,
        ),
        const SizedBox(height: 12),
        BackupNotificationStatusCard(
          settings: notifications,
          onEnabledChanged: onNotificationEnabledChanged,
          onPermissionStatusChanged: onNotificationPermissionStatusChanged,
          onRequestPermission: onRequestNotificationPermission,
          onSendSmokeNotification: onSendReminderNotification,
        ),
        const SizedBox(height: 12),
        const _CenterSectionLabel(
          title: '完整備份 / 完整還原',
          description: '適合換手機、重裝 App 或災難復原。',
          helpTitle: '完整模式是什麼？',
          helpBody:
              '完整模式就像幫 App 做一份完整快照。\n\n如果你要換手機、重裝 App，或想回到某一次完整備份，就使用這個模式。\n\n完整還原會恢復帳戶、交易、信用卡帳單、銀行規則與分期資料，並覆蓋目前資料，所以 App 會要求你再次確認。',
        ),
        const SizedBox(height: 8),
        _CenterActionCard(
          title: '完整備份',
          status: '整包快照',
          riskLabel: '低風險',
          tone: _CenterTone.safe,
          description: '建立完整備份檔。',
          bullets: const [
            '包含帳戶、交易、信用卡帳單、銀行規則與分期資料。',
            '只會匯出檔案，不會修改目前資料。',
          ],
          actionLabel: '建立完整備份',
          onPressed: onFullBackup,
        ),
        const SizedBox(height: 12),
        _RestoreSourceCard(
          grant: restoreSourceGrant,
          onPickSource: onPickFullRestoreSource,
        ),
        const SizedBox(height: 12),
        _CenterActionCard(
          title: '完整還原',
          status:
              restoreSourceGrant == null ? '尚未選擇備份來源' : '已選擇備份來源',
          riskLabel: '高風險',
          tone: _CenterTone.danger,
          description: '使用完整備份檔復原資料。',
          bullets: const [
            '會先預覽備份內容與差異。',
            '正式還原前會要求輸入 RESTORE。',
            '系統會先建立還原前備份。',
          ],
          actionLabel: '檢視完整還原流程',
          onPressed: onFullRestore,
        ),
        const SizedBox(height: 12),
        const _CenterSectionLabel(
          title: 'readable 匯出 / 匯入',
          description: '適合人工檢查或只匯入一批交易。',
          helpTitle: 'readable 模式是什麼？',
          helpBody:
              'readable 模式是看得懂的交易檔。\n\n它適合拿來人工檢查、用試算表整理，或只匯入某一批交易。\n\nreadable 匯入只處理交易紀錄，不會完整恢復帳戶設定，也不會整包覆蓋目前資料。',
        ),
        const SizedBox(height: 8),
        _CenterActionCard(
          title: 'CSV / JSON readable 匯出',
          status: '人類可讀交易資料',
          riskLabel: '低風險',
          tone: _CenterTone.safe,
          description: '匯出可閱讀的交易檔。',
          bullets: const [
            '可輸出 readable CSV / JSON。',
            '只會匯出檔案，不會修改目前資料。',
          ],
          actionLabel: '進入 readable 匯出',
          onPressed: onReadableExport,
        ),
        const SizedBox(height: 12),
        _CenterActionCard(
          title: 'CSV / JSON readable 匯入審核',
          status: '逐筆交易匯入',
          riskLabel: '中風險',
          tone: _CenterTone.warning,
          description: '匯入前可逐筆檢查交易。',
          bullets: const [
            '不包含帳戶完整復原。',
            '不自動新增帳戶、類別或商家。',
          ],
          actionLabel: '選擇 readable 匯入檔',
          onPressed: onPickReadableImportFile,
          secondaryActionLabel: '掃描固定匯入資料夾',
          onSecondaryPressed: onReadableImportReview,
        ),
      ],
    );
  }
}

class _RestoreSourceCard extends StatelessWidget {
  const _RestoreSourceCard({required this.grant, required this.onPickSource});

  final RestoreSourceGrant? grant;
  final VoidCallback? onPickSource;

  @override
  Widget build(BuildContext context) {
    final hasGrant = grant != null;
    final canPreview = grant?.pathBacked ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '完整還原來源',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(
                  label: hasGrant
                      ? (canPreview ? '已選擇' : '需重新選擇')
                      : '未選擇',
                  tone: !hasGrant
                      ? _CenterTone.warning
                      : canPreview
                          ? _CenterTone.safe
                          : _CenterTone.warning,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(hasGrant
                ? '目前來源：${grant!.displayName}'
                : '尚未選擇完整備份 JSON。'),
            if (hasGrant) ...[
              const SizedBox(height: 4),
              SelectableText('來源位置：${grant!.uri}'),
              const SizedBox(height: 4),
              Text('選擇時間：${grant!.grantedAt.toLocal()}'),
              if (!canPreview) ...[
                const SizedBox(height: 8),
                const Text('目前無法直接讀取這個來源，請重新選擇備份檔。'),
              ],
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onPickSource,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(hasGrant ? '重新選擇還原來源' : '選擇還原來源'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterSectionLabel extends StatelessWidget {
  const _CenterSectionLabel({
    required this.title,
    required this.description,
    required this.helpTitle,
    required this.helpBody,
  });

  final String title;
  final String description;
  final String helpTitle;
  final String helpBody;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(description),
            ],
          ),
        ),
        IconButton(
          tooltip: '$title 說明',
          icon: const Icon(Icons.help_outline),
          onPressed: () => _showHelpDialog(context, helpTitle, helpBody),
        ),
      ],
    );
  }
}

void _showHelpDialog(BuildContext context, String title, String body) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('了解'),
        ),
      ],
    ),
  );
}

class _CenterActionCard extends StatelessWidget {
  const _CenterActionCard({
    required this.title,
    required this.status,
    required this.riskLabel,
    required this.tone,
    required this.description,
    required this.bullets,
    required this.actionLabel,
    required this.onPressed,
    this.secondaryActionLabel,
    this.onSecondaryPressed,
  });

  final String title;
  final String status;
  final String riskLabel;
  final _CenterTone tone;
  final String description;
  final List<String> bullets;
  final String actionLabel;
  final VoidCallback? onPressed;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(label: riskLabel, tone: tone),
              ],
            ),
            const SizedBox(height: 8),
            Text(status, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 8),
            for (final bullet in bullets) Text('• $bullet'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text(actionLabel),
                ),
                if (secondaryActionLabel != null)
                  FilledButton.tonalIcon(
                    onPressed: onSecondaryPressed,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(secondaryActionLabel!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _CenterTone tone;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, tone);
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}

enum _CenterTone { neutral, safe, warning, danger }

Color _toneColor(BuildContext context, _CenterTone tone) {
  final scheme = Theme.of(context).colorScheme;
  switch (tone) {
    case _CenterTone.neutral:
      return scheme.secondary;
    case _CenterTone.safe:
      return Colors.green.shade700;
    case _CenterTone.warning:
      return Colors.deepOrange.shade700;
    case _CenterTone.danger:
      return scheme.error;
  }
}
