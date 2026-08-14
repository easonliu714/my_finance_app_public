import 'package:flutter/foundation.dart';

import 'repayment_reminder_schedule.dart';

enum LocalNotificationPermissionStatus {
  notConfigured,
  readyToRequest,
  granted,
  denied,
}

class LocalNotificationPreview {
  const LocalNotificationPreview({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.payload,
    required this.enabled,
  });

  final String id;
  final String title;
  final String body;
  final DateTime scheduledDate;
  final String payload;
  final bool enabled;
}

class LocalNotificationSettings {
  const LocalNotificationSettings({
    required this.permissionStatus,
    required this.masterEnabled,
    required this.lastSyncAt,
    required this.lastScheduledCount,
    required this.lastSkippedCount,
  });

  factory LocalNotificationSettings.initial() => const LocalNotificationSettings(
        permissionStatus: kIsWeb ? LocalNotificationPermissionStatus.notConfigured : LocalNotificationPermissionStatus.readyToRequest,
        masterEnabled: true,
        lastSyncAt: null,
        lastScheduledCount: 0,
        lastSkippedCount: 0,
      );

  final LocalNotificationPermissionStatus permissionStatus;
  final bool masterEnabled;
  final DateTime? lastSyncAt;
  final int lastScheduledCount;
  final int lastSkippedCount;

  LocalNotificationSettings copyWith({
    LocalNotificationPermissionStatus? permissionStatus,
    bool? masterEnabled,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    int? lastScheduledCount,
    int? lastSkippedCount,
  }) {
    return LocalNotificationSettings(
      permissionStatus: permissionStatus ?? this.permissionStatus,
      masterEnabled: masterEnabled ?? this.masterEnabled,
      lastSyncAt: clearLastSyncAt ? null : lastSyncAt ?? this.lastSyncAt,
      lastScheduledCount: lastScheduledCount ?? this.lastScheduledCount,
      lastSkippedCount: lastSkippedCount ?? this.lastSkippedCount,
    );
  }
}

class LocalNotificationSyncResult {
  const LocalNotificationSyncResult({
    required this.permissionStatus,
    required this.scheduledCount,
    required this.skippedCount,
    required this.message,
  });

  final LocalNotificationPermissionStatus permissionStatus;
  final int scheduledCount;
  final int skippedCount;
  final String message;
}

class LocalNotificationPrototypeService {
  const LocalNotificationPrototypeService();

  LocalNotificationSettings get initialSettings => LocalNotificationSettings.initial();

  LocalNotificationPermissionStatus get permissionStatus => initialSettings.permissionStatus;

  List<LocalNotificationPreview> buildNotificationPreviews(List<RepaymentReminderScheduleItem> schedule) {
    return schedule
        .where((item) => item.enabled && !item.isCompleted)
        .map((item) => LocalNotificationPreview(
              id: item.id,
              title: item.title,
              body: item.message,
              scheduledDate: item.notifyDate,
              payload: 'repayment-plan:${item.id}',
              enabled: item.enabled,
            ))
        .toList(growable: false);
  }

  Future<LocalNotificationPermissionStatus> requestPermission({LocalNotificationSettings? settings}) async {
    final current = settings?.permissionStatus ?? permissionStatus;
    if (current == LocalNotificationPermissionStatus.notConfigured) return current;
    return LocalNotificationPermissionStatus.granted;
  }

  LocalNotificationSettings updateMasterEnabled(LocalNotificationSettings settings, bool enabled) {
    return settings.copyWith(masterEnabled: enabled);
  }

  LocalNotificationSettings applyPermissionResult(LocalNotificationSettings settings, LocalNotificationPermissionStatus status) {
    return settings.copyWith(permissionStatus: status);
  }

  LocalNotificationSettings applySyncResult(LocalNotificationSettings settings, LocalNotificationSyncResult result, {DateTime? syncedAt}) {
    return settings.copyWith(
      permissionStatus: result.permissionStatus,
      lastSyncAt: syncedAt ?? DateTime.now(),
      lastScheduledCount: result.scheduledCount,
      lastSkippedCount: result.skippedCount,
    );
  }

  Future<LocalNotificationSyncResult> syncNotificationPreviews(List<LocalNotificationPreview> previews, {LocalNotificationSettings? settings}) async {
    final activeSettings = settings ?? initialSettings;
    final status = activeSettings.permissionStatus;
    if (!activeSettings.masterEnabled) {
      return LocalNotificationSyncResult(permissionStatus: status, scheduledCount: 0, skippedCount: previews.length, message: '提醒總開關已關閉。');
    }
    if (status != LocalNotificationPermissionStatus.granted) {
      return LocalNotificationSyncResult(permissionStatus: status, scheduledCount: 0, skippedCount: previews.length, message: '尚未允許通知權限，請先啟用提醒權限。');
    }
    return LocalNotificationSyncResult(permissionStatus: status, scheduledCount: previews.length, skippedCount: 0, message: '已同步通知排程。');
  }

  String permissionStatusLabel(LocalNotificationPermissionStatus status) {
    switch (status) {
      case LocalNotificationPermissionStatus.notConfigured:
        return '尚未設定';
      case LocalNotificationPermissionStatus.readyToRequest:
        return '待啟用';
      case LocalNotificationPermissionStatus.granted:
        return '已允許';
      case LocalNotificationPermissionStatus.denied:
        return '已拒絕';
    }
  }
}
