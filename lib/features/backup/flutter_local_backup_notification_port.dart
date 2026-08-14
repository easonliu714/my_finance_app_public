import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'backup_notification_settings.dart';
import 'local_backup_reminder_notification_service.dart';
import 'scheduled_backup_reminder_service.dart';

class FlutterLocalBackupReminderNotificationPort implements LocalBackupReminderNotificationPort, BackupNotificationPermissionPort, ScheduledBackupReminderPort {
  FlutterLocalBackupReminderNotificationPort({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int backupReminderNotificationId = 3110;
  static const int scheduledBackupReminderNotificationId = 3120;
  static const String backupReminderChannelId = 'backup_reminder';
  static const String backupReminderChannelName = '備份提醒';
  static const String backupReminderChannelDescription = '提醒使用者定期建立完整備份。';

  final FlutterLocalNotificationsPlugin _plugin;
  var _initialized = false;
  static var _timezoneInitialized = false;

  @override
  Future<void> showBackupReminder(LocalBackupReminderNotification notification) async {
    await _ensureInitialized();
    await _plugin.show(
      backupReminderNotificationId,
      notification.title,
      notification.body,
      _notificationDetails(),
      payload: 'backup_reminder',
    );
  }

  @override
  Future<void> schedule(ScheduledBackupReminderRequest request) async {
    await _ensureInitialized();
    final scheduledAt = _toScheduledDate(request.scheduledAt);
    await _plugin.zonedSchedule(
      scheduledBackupReminderNotificationId,
      '備份提醒',
      '已到達備份提醒週期，建議建立完整備份。',
      scheduledAt,
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'scheduled_backup_reminder',
    );
  }

  @override
  Future<void> cancel() async {
    await _ensureInitialized();
    await _plugin.cancel(scheduledBackupReminderNotificationId);
  }

  @override
  Future<BackupNotificationPermissionStatus> requestPermission() async {
    await _ensureInitialized();
    final android = _androidImplementation();
    if (android == null) return BackupNotificationPermissionStatus.unsupported;
    final granted = await android.requestNotificationsPermission();
    return granted == true ? BackupNotificationPermissionStatus.granted : BackupNotificationPermissionStatus.denied;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!_timezoneInitialized) {
      tz.initializeTimeZones();
      _timezoneInitialized = true;
    }
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidSettings));
    _initialized = true;
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        backupReminderChannelId,
        backupReminderChannelName,
        channelDescription: backupReminderChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
  }

  tz.TZDateTime _toScheduledDate(DateTime value) {
    final utcValue = value.toUtc();
    final scheduled = tz.TZDateTime.from(utcValue, tz.UTC);
    final now = tz.TZDateTime.now(tz.UTC);
    if (scheduled.isAfter(now)) return scheduled;
    return now.add(const Duration(seconds: 5));
  }

  AndroidFlutterLocalNotificationsPlugin? _androidImplementation() {
    if (kIsWeb || !Platform.isAndroid) return null;
    return _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  }
}
