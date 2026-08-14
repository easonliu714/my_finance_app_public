import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';

import '../backup/backup_migration_actions.dart';
import '../backup/backup_migration_center.dart';
import '../backup/backup_notification_settings.dart';
import '../backup/backup_notification_settings_repository.dart';
import '../backup/backup_preview_confirmation_gate.dart';
import '../backup/backup_reminder_settings.dart';
import '../backup/backup_reminder_settings_repository.dart';
import '../backup/full_restore_preview_service.dart';
import '../backup/full_restore_service.dart';
import '../backup/import_mapping_analysis_service.dart';
import '../backup/import_review_flow.dart';
import '../backup/local_backup_reminder_notification_service.dart';
import '../backup/readable_import_source_service.dart';
import '../backup/restore_source_grant.dart';
import '../backup/restore_source_grant_repository.dart';
import '../backup/scheduled_backup_reminder_service.dart';
import '../invoice/lab/private_cloud_invoice_lab_webview_page.dart';
import '../transaction/transaction_repository.dart';

class MyPage extends StatefulWidget {
  const MyPage({
    super.key,
    this.actionService = const BackupMigrationActionService(),
    this.databaseProvider,
    this.reminderSettingsRepository = const BackupReminderSettingsRepository(),
    this.restoreSourceRepository = const RestoreSourceGrantRepository(),
    this.notificationSettingsRepository = const BackupNotificationSettingsRepository(),
    this.notificationPort = const NoopBackupReminderNotificationPort(),
    this.notificationPermissionPort,
    this.scheduledReminderPort,
  });

  static const routeName = 'my';
  static const routePath = '/my';
  static const cloudInvoiceWebViewEntryKey =
      Key('my_cloud_invoice_webview_entry');

  final BackupMigrationActionService actionService;
  final Future<DatabaseExecutor> Function()? databaseProvider;
  final BackupReminderSettingsRepository reminderSettingsRepository;
  final RestoreSourceGrantRepository restoreSourceRepository;
  final BackupNotificationSettingsRepository notificationSettingsRepository;
  final LocalBackupReminderNotificationPort notificationPort;
  final BackupNotificationPermissionPort? notificationPermissionPort;
  final ScheduledBackupReminderPort? scheduledReminderPort;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  BackupReminderSettings _reminderSettings = BackupReminderSettings.defaults();
  BackupNotificationSettings _notificationSettings = BackupNotificationSettings.defaults();
  RestoreSourceGrant? _restoreSourceGrant;
  var _settingsLoaded = false;
  var _automaticBackupRunning = false;

  BackupNotificationPermissionPort get _permissionPort {
    final explicit = widget.notificationPermissionPort;
    if (explicit != null) return explicit;
    final Object notificationPort = widget.notificationPort;
    if (notificationPort is BackupNotificationPermissionPort) return notificationPort;
    return const NoopBackupReminderNotificationPort();
  }

  ScheduledBackupReminderPort get _schedulePort {
    final explicit = widget.scheduledReminderPort;
    if (explicit != null) return explicit;
    final Object notificationPort = widget.notificationPort;
    if (notificationPort is ScheduledBackupReminderPort) return notificationPort;
    return const NoopScheduledBackupReminderPort();
  }

  @override
  void initState() {
    super.initState();
    _loadReminderSettings();
    _loadNotificationSettings();
    _loadRestoreSourceGrant();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: BackupMigrationCenter(
        reminderSettings: _reminderSettings,
        notificationSettings: _notificationSettings,
        restoreSourceGrant: _restoreSourceGrant,
        onReminderEnabledChanged: _handleReminderEnabledChanged,
        onReminderIntervalDaysChanged: _handleReminderIntervalDaysChanged,
        onAutomaticBackupEnabledChanged: _handleAutomaticBackupEnabledChanged,
        onNetworkUsageAllowedChanged: _handleNetworkUsageAllowedChanged,
        onCloudBackupHandoffEnabledChanged: _handleCloudBackupHandoffEnabledChanged,
        onNotificationEnabledChanged: _handleNotificationEnabledChanged,
        onNotificationPermissionStatusChanged: _handleNotificationPermissionStatusChanged,
        onRequestNotificationPermission: () => _requestNotificationPermission(context),
        onSendReminderNotification: () => _sendBackupReminderNotification(context),
        onFullBackup: () => _runFullBackup(context),
        onFullRestore: () => _openFullRestoreFlow(context),
        onPickFullRestoreSource: () => _pickFullRestoreSource(context),
        onReadableExport: () => _runFileAction(context, () async {
          final db = await _database();
          return widget.actionService.exportAndShareTransactionsJson(db);
        }),
        onPickReadableImportFile: () => _pickReadableImportFile(context),
        onReadableImportReview: () async {
          final db = await _database();
          if (!context.mounted) return;
          await _showSafeSource(context, () => widget.actionService.prepareReadableImportSource(currentDb: db), currentDb: db);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: MyPage.cloudInvoiceWebViewEntryKey,
        onPressed: () => context.pushNamed(
          PrivateCloudInvoiceLabWebViewPage.routeName,
        ),
        icon: const Icon(Icons.public_outlined),
        label: const Text('官方發票匯入'),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: 4,
        onDestinationSelected: (index) {
          if (index == 0) context.go('/accounts');
          if (index == 1) context.go('/plans');
          if (index == 2) context.go('/');
          if (index == 3) context.go('/ledger');
          if (index == 4) context.go(MyPage.routePath);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: '帳戶'),
          NavigationDestination(icon: Icon(Icons.check_box_outlined), label: '計劃'),
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首頁'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: '報表'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }

  Future<DatabaseExecutor> _database() {
    final provider = widget.databaseProvider;
    if (provider != null) return provider();
    return TransactionRepository.instance.database;
  }

  Future<void> _loadReminderSettings() async {
    try {
      final db = await _database();
      final settings = await widget.reminderSettingsRepository.load(db);
      if (!mounted) return;
      setState(() {
        _reminderSettings = settings;
        _settingsLoaded = true;
      });
      await _reconcileSchedule();
      await _maybeRunAutomaticBackup();
    } catch (_) {
      if (!mounted) return;
      setState(() => _settingsLoaded = true);
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final db = await _database();
      final settings = await widget.notificationSettingsRepository.load(db);
      if (!mounted) return;
      setState(() => _notificationSettings = settings);
      await _reconcileSchedule();
    } catch (_) {
      if (!mounted) return;
      setState(() => _notificationSettings = BackupNotificationSettings.defaults());
    }
  }

  Future<void> _loadRestoreSourceGrant() async {
    try {
      final db = await _database();
      final grant = await widget.restoreSourceRepository.load(db);
      if (!mounted) return;
      setState(() => _restoreSourceGrant = grant);
    } catch (_) {
      if (!mounted) return;
      setState(() => _restoreSourceGrant = null);
    }
  }

  Future<void> _handleReminderEnabledChanged(bool enabled) async {
    await _saveReminderSettings(_reminderSettings.copyWith(enabled: enabled));
  }

  Future<void> _handleReminderIntervalDaysChanged(int intervalDays) async {
    await _saveReminderSettings(_reminderSettings.copyWith(intervalDays: intervalDays));
  }

  Future<void> _handleAutomaticBackupEnabledChanged(bool enabled) async {
    await _saveReminderSettings(
      _reminderSettings.copyWith(
        automaticBackupEnabled: enabled,
        networkUsageAllowed: enabled ? _reminderSettings.networkUsageAllowed : false,
        cloudBackupHandoffEnabled: enabled ? _reminderSettings.cloudBackupHandoffEnabled : false,
      ),
      successMessage: enabled ? '自動建立備份已開啟；可另外開啟雲端備份交接' : '自動建立備份已關閉',
    );
  }

  Future<void> _handleNetworkUsageAllowedChanged(bool allowed) async {
    await _saveReminderSettings(
      _reminderSettings.copyWith(
        networkUsageAllowed: allowed,
        cloudBackupHandoffEnabled: allowed ? _reminderSettings.cloudBackupHandoffEnabled : false,
      ),
      successMessage: allowed ? '已允許備份流程使用網路流量；請留意行動數據用量' : '已關閉備份流程網路流量使用，雲端備份交接也已關閉',
    );
  }

  Future<void> _handleCloudBackupHandoffEnabledChanged(bool enabled) async {
    final allowed = _reminderSettings.automaticBackupEnabled && _reminderSettings.networkUsageAllowed;
    if (enabled && !allowed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先開啟自動建立備份並允許備份使用網路流量。')));
      return;
    }
    await _saveReminderSettings(
      _reminderSettings.copyWith(cloudBackupHandoffEnabled: enabled),
      successMessage: enabled ? '自動雲端備份交接已開啟；到期備份後會開啟系統分享面板' : '自動雲端備份交接已關閉',
    );
  }

  Future<void> _saveReminderSettings(BackupReminderSettings settings, {String successMessage = '備份提示設定已儲存，提醒排程已同步'}) async {
    setState(() => _reminderSettings = settings);
    try {
      final db = await _database();
      await widget.reminderSettingsRepository.save(db, settings);
      await _reconcileSchedule();
      await _maybeRunAutomaticBackup();
      if (!mounted || !_settingsLoaded) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('備份提示設定儲存失敗：$error')));
    }
  }

  Future<void> _maybeRunAutomaticBackup() async {
    if (_automaticBackupRunning || !_settingsLoaded) return;
    final settings = _reminderSettings;
    if (!settings.enabled || !settings.automaticBackupEnabled) return;
    if (settings.lastBackupAt == null || !settings.isReminderDue(DateTime.now().toUtc())) return;

    _automaticBackupRunning = true;
    try {
      final db = await _database();
      final file = await widget.actionService.fullBackupService.writeFullBackupFile(db, sourcePlatform: 'android');
      var backupMessage = '已自動建立本機完整備份：${file.path}';
      if (settings.cloudBackupHandoffEnabled && settings.networkUsageAllowed) {
        final shared = await widget.actionService.fileExchange.shareFile(
          file: file,
          subject: 'My Finance App 自動備份',
          text: 'My Finance App 自動建立的完整備份。請選擇 Google Drive、iCloud Drive 或其他雲端 App 儲存。',
        );
        backupMessage = '已建立本機完整備份並開啟雲端交接：${shared.path}';
      }
      final completedAt = DateTime.now().toUtc();
      await widget.reminderSettingsRepository.recordBackupCompleted(db, completedAt);
      final updatedSettings = await widget.reminderSettingsRepository.load(db);
      if (mounted) {
        setState(() => _reminderSettings = updatedSettings);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(backupMessage)));
      }
      await _reconcileSchedule();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('自動建立備份失敗：$error')));
    } finally {
      _automaticBackupRunning = false;
    }
  }

  Future<void> _handleNotificationEnabledChanged(bool enabled) async {
    await _saveNotificationSettings(_notificationSettings.copyWith(enabled: enabled, updatedAt: DateTime.now().toUtc()));
  }

  Future<void> _handleNotificationPermissionStatusChanged(BackupNotificationPermissionStatus status) async {
    await _saveNotificationSettings(_notificationSettings.copyWith(permissionStatus: status, updatedAt: DateTime.now().toUtc()));
  }

  Future<void> _requestNotificationPermission(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await _permissionPort.requestPermission();
      final next = _notificationSettings.copyWith(permissionStatus: status, updatedAt: DateTime.now().toUtc());
      await _saveNotificationSettings(next, successMessage: '系統通知權限狀態已更新：${status.label}；提醒排程已同步');
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('要求通知權限失敗：$error')));
    }
  }

  Future<void> _saveNotificationSettings(BackupNotificationSettings settings, {String successMessage = '備份通知 readiness 已儲存，提醒排程已同步'}) async {
    setState(() => _notificationSettings = settings);
    try {
      final db = await _database();
      await widget.notificationSettingsRepository.save(db, settings);
      await _reconcileSchedule();
      if (!mounted || !_settingsLoaded) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('備份通知 readiness 儲存失敗：$error')));
    }
  }

  Future<void> _reconcileSchedule() async {
    await ScheduledBackupReminderService(port: _schedulePort).reconcile(
      reminderSettings: _reminderSettings,
      notificationSettings: _notificationSettings,
      now: DateTime.now().toUtc(),
    );
  }

  Future<void> _sendBackupReminderNotification(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await LocalBackupReminderNotificationService(port: widget.notificationPort).sendSmokeReminder(
        notificationSettings: _notificationSettings,
        now: DateTime.now().toUtc(),
      );
      if (!context.mounted) return;
      if (result.sent) {
        messenger.showSnackBar(SnackBar(content: Text('已送出備份提醒 smoke：${result.notification?.body ?? ''}')));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('未送出備份提醒：${_notificationSkipReasonLabel(result.reason)}')));
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('備份提醒 smoke 失敗：$error')));
    }
  }

  Future<void> _runFullBackup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在準備檔案...')));
    try {
      final db = await _database();
      final result = await widget.actionService.createAndShareFullBackup(db);
      final completedAt = DateTime.now().toUtc();
      await widget.reminderSettingsRepository.recordBackupCompleted(db, completedAt);
      final updatedSettings = await widget.reminderSettingsRepository.load(db);
      if (mounted) setState(() => _reminderSettings = updatedSettings);
      await _reconcileSchedule();
      messenger.showSnackBar(SnackBar(content: Text('${result.message}；已更新備份提示時間與提醒排程')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('檔案操作失敗：$error')));
    }
  }

  Future<void> _openFullRestoreFlow(BuildContext context) async {
    final db = await _database();
    if (!context.mounted) return;
    final grant = _restoreSourceGrant;
    if (grant != null) {
      await _showSafeSource(context, () => widget.actionService.prepareFullRestoreSourceFromGrant(grant, currentDb: db), currentDb: db);
      return;
    }
    await _showSafeSource(context, () => widget.actionService.prepareFullRestoreSource(currentDb: db), currentDb: db);
  }

  Future<void> _pickFullRestoreSource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.actionService.pickRestoreSource();
      if (result == null) {
        messenger.showSnackBar(const SnackBar(content: Text('未選擇完整備份來源')));
        return;
      }
      final db = await _database();
      await widget.restoreSourceRepository.save(db, result.grant);
      if (!mounted) return;
      setState(() => _restoreSourceGrant = result.grant);
      messenger.showSnackBar(SnackBar(content: Text('已授權還原來源：${result.grant.displayName}')));
      await _showSafeSource(context, () => widget.actionService.prepareFullRestoreSourceFromPickResult(result, currentDb: db), currentDb: db);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('選擇完整還原來源失敗：$error')));
    }
  }

  Future<void> _pickReadableImportFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await widget.actionService.pickReadableImportFilePath();
      if (path == null) {
        messenger.showSnackBar(const SnackBar(content: Text('未選擇 readable 匯入檔')));
        return;
      }
      final db = await _database();
      if (!context.mounted) return;
      await _showSafeSource(context, () => widget.actionService.prepareReadableImportSourceFromPath(path, currentDb: db), currentDb: db);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('選擇 readable 匯入檔失敗：$error')));
    }
  }

  Future<void> _runFileAction(BuildContext context, Future<BackupMigrationActionResult> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在準備檔案...')));
    try {
      final result = await action();
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('檔案操作失敗：$error')));
    }
  }

  Future<void> _showSafeSource(BuildContext context, Future<SafeImportSourceResult> Function() prepareSource, {DatabaseExecutor? currentDb}) async {
    try {
      final result = await prepareSource();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final hasRestorePreview = result.restorePreviews.isNotEmpty;
          final hasReadableCandidates = result.readableImportCandidates.isNotEmpty;
          return AlertDialog(
            title: Text(result.title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(result.message),
                  const SizedBox(height: 12),
                  const Text('來源位置', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  SelectableText(result.directoryPath),
                  if (result.restoreSourceGrant != null) ...[
                    const SizedBox(height: 8),
                    Text('已授權來源：${result.restoreSourceGrant!.displayName}'),
                    Text('授權時間：${result.restoreSourceGrant!.grantedAt.toLocal()}'),
                  ],
                  const SizedBox(height: 12),
                  Text('允許副檔名：${result.allowedExtensions.join(', ')}'),
                  const SizedBox(height: 12),
                  if (hasRestorePreview)
                    const Text('安全狀態：正式還原前仍需輸入 RESTORE，且會先建立還原前備份。')
                  else if (hasReadableCandidates)
                    const Text('安全狀態：readable 匯入仍需 dry-run、mapping review 與確認後才會寫入交易列。'),
                  const SizedBox(height: 12),
                  _RestorePreviewSection(
                    previews: result.restorePreviews,
                    onCommitRestore: currentDb is Database
                        ? (preview) async {
                            Navigator.of(dialogContext).pop();
                            await _confirmAndCommitFullRestore(context, currentDb, preview);
                          }
                        : null,
                  ),
                  if (result.readableImportCandidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ReadableImportCandidateSection(
                      candidates: result.readableImportCandidates,
                      onOpenReviewFlow: currentDb == null
                          ? null
                          : (candidate) async {
                              Navigator.of(dialogContext).pop();
                              await _openReadableImportReviewFlow(context, currentDb, candidate);
                            },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('了解')),
            ],
          );
        },
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('準備安全來源失敗：$error')));
    }
  }

  Future<void> _confirmAndCommitFullRestore(BuildContext context, Database db, FullRestoreBackupPreview preview) async {
    final controller = TextEditingController();
    try {
      final confirmation = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('正式完整還原確認'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('此操作會以備份檔覆蓋目前資料。系統會先建立還原前備份，若還原或驗證失敗會 rollback。'),
                const SizedBox(height: 12),
                Text('候選檔案：${preview.fileName}'),
                Text('版本：${preview.metadata?.appVersion ?? '-'}'),
                Text('資料表數：${preview.tableRowCounts.length}'),
                const SizedBox(height: 12),
                const Text('請輸入 RESTORE 才能開始正式還原。'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '輸入 RESTORE'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('執行完整還原'),
            ),
          ],
        ),
      );
      if (confirmation == null) return;
      if (confirmation.trim() != FullRestoreService.destructiveConfirmationText) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未輸入 RESTORE，完整還原已阻擋。')));
        return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在執行完整還原...')));
      final result = await widget.actionService.commitFullRestoreFromPreview(
        db,
        preview,
        confirmationText: confirmation,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('完整還原完成'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(result.message),
                if (result.preRestoreBackupPath != null) ...[
                  const SizedBox(height: 12),
                  const Text('還原前備份位置', style: TextStyle(fontWeight: FontWeight.w800)),
                  SelectableText(result.preRestoreBackupPath!),
                ],
                const SizedBox(height: 12),
                const Text('建議關閉並重新開啟 App，確保所有畫面重新載入最新資料。'),
              ],
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('了解')),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完整還原失敗，已保留原資料：$error')));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openReadableImportReviewFlow(BuildContext context, DatabaseExecutor db, ReadableImportSourceCandidate candidate) async {
    final dryRun = candidate.dryRunResult;
    if (dryRun == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此候選檔尚未完成 dry-run preview，無法開啟審核流程。')));
      return;
    }
    try {
      final analysis = await const ImportMappingAnalysisService().analyze(db, dryRun);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 920,
            height: 720,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('readable 匯入審核｜${candidate.fileName}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close), tooltip: '關閉'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: ImportReviewFlow(dryRunResult: dryRun, mappingAnalysis: analysis, database: db)),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('開啟匯入審核流程失敗：$error')));
    }
  }
}

String _notificationSkipReasonLabel(LocalBackupReminderNotificationSkipReason reason) {
  switch (reason) {
    case LocalBackupReminderNotificationSkipReason.sent:
      return '已送出';
    case LocalBackupReminderNotificationSkipReason.reminderDisabled:
      return '備份提示已停用';
    case LocalBackupReminderNotificationSkipReason.notificationDisabled:
      return '備份通知未啟用';
    case LocalBackupReminderNotificationSkipReason.permissionNotGranted:
      return '通知權限尚未允許';
    case LocalBackupReminderNotificationSkipReason.notDue:
      return '尚未到期';
  }
}

class _RestorePreviewSection extends StatelessWidget {
  const _RestorePreviewSection({required this.previews, this.onCommitRestore});

  final List<FullRestoreBackupPreview> previews;
  final ValueChanged<FullRestoreBackupPreview>? onCommitRestore;

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('完整還原候選｜完整備份 JSON', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('此區預覽完整備份檔 metadata 與 table diff；完成確認後可進入 RESTORE typed confirmation。'),
        const SizedBox(height: 8),
        for (final preview in previews) _RestorePreviewCard(preview: preview, onCommitRestore: onCommitRestore),
      ],
    );
  }
}

class _RestorePreviewCard extends StatelessWidget {
  const _RestorePreviewCard({required this.preview, this.onCommitRestore});

  final FullRestoreBackupPreview preview;
  final ValueChanged<FullRestoreBackupPreview>? onCommitRestore;

  @override
  Widget build(BuildContext context) {
    final metadata = preview.metadata;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.fileName, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(preview.isValid ? '狀態：可預覽' : '狀態：不可用'),
            Text(preview.message),
            if (metadata != null) ...[
              const SizedBox(height: 8),
              Text('app_version：${metadata.appVersion}'),
              Text('schema_version：${metadata.databaseSchemaVersion ?? '-'}'),
              Text('created_at：${metadata.createdAt}'),
              Text('source_platform：${metadata.sourcePlatform}'),
              const SizedBox(height: 8),
              Text('tables：${preview.tableRowCounts.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}'),
              const SizedBox(height: 8),
              _TableImpactSummary(impacts: preview.tableImpacts),
              BackupPreviewConfirmationGate(preview: preview, onCommitRestore: onCommitRestore),
            ],
          ],
        ),
      ),
    );
  }
}

class _TableImpactSummary extends StatelessWidget {
  const _TableImpactSummary({required this.impacts});

  final List<FullRestoreTableImpact> impacts;

  @override
  Widget build(BuildContext context) {
    if (impacts.isEmpty) return const Text('table diff：尚無目前資料庫筆數可比較。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('table diff summary', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final impact in impacts) Text('${impact.tableName}：目前 ${impact.currentCount} / 備份 ${impact.backupCount} / 差異 ${impact.delta} / ${impact.level.name}'),
      ],
    );
  }
}

class _ReadableImportCandidateSection extends StatelessWidget {
  const _ReadableImportCandidateSection({required this.candidates, this.onOpenReviewFlow});

  final List<ReadableImportSourceCandidate> candidates;
  final ValueChanged<ReadableImportSourceCandidate>? onOpenReviewFlow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('readable 匯入候選｜交易 CSV / JSON', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('此區只處理交易列，會經過 dry-run、mapping、review、confirmation 與 commit；不是完整還原。'),
        const SizedBox(height: 8),
        for (final candidate in candidates) _ReadableImportCandidateCard(candidate: candidate, onOpenReviewFlow: onOpenReviewFlow),
      ],
    );
  }
}

class _ReadableImportCandidateCard extends StatelessWidget {
  const _ReadableImportCandidateCard({required this.candidate, this.onOpenReviewFlow});

  final ReadableImportSourceCandidate candidate;
  final ValueChanged<ReadableImportSourceCandidate>? onOpenReviewFlow;

  @override
  Widget build(BuildContext context) {
    final dryRun = candidate.dryRunResult;
    final canOpenReview = candidate.isValid && dryRun != null && onOpenReviewFlow != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.fileName, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('format：${candidate.format.name}'),
            Text('size：${candidate.fileSizeBytes} bytes'),
            Text(candidate.isValid ? '狀態：dry-run preview ready' : '狀態：不可用'),
            Text(candidate.message),
            if (dryRun != null) ...[
              const SizedBox(height: 8),
              Text('dry-run rows：total ${dryRun.totalRows} / valid ${dryRun.validRows} / invalid ${dryRun.invalidRows} / duplicate ${dryRun.duplicateRows} / ready ${dryRun.readyToInsertRows}'),
              const Text('下一步：可開啟 mapping review flow；通過確認後才會寫入交易列。'),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: canOpenReview ? () => onOpenReviewFlow?.call(candidate) : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('開啟審核流程'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
