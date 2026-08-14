import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'debit_card_settlement_reminder.dart';

class FlutterLocalDebitCardSettlementReminderPort
    implements DebitCardSettlementReminderPort {
  FlutterLocalDebitCardSettlementReminderPort({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'debit_card_settlement_reminder';
  static const String channelName = '簽帳金融卡扣款提醒';
  static const String channelDescription =
      '提醒使用者檢查 App 推算的簽帳金融卡預計扣款與逾期未確認項目。';

  final FlutterLocalNotificationsPlugin _plugin;
  var _initialized = false;
  static var _timezoneInitialized = false;

  @override
  Future<Set<int>> pendingReminderIds() async {
    await _ensureInitialized();
    final pending = await _plugin.pendingNotificationRequests();
    return pending
        .where(
          (request) => request.payload?.startsWith(
                DebitCardSettlementReminderPlanner.payloadPrefix,
              ) ==
              true,
        )
        .map((request) => request.id)
        .toSet();
  }

  @override
  Future<void> schedule(DebitCardSettlementReminderRequest request) async {
    await _ensureInitialized();
    final scheduled = _toScheduledDate(request.scheduledAtUtc);
    await _plugin.zonedSchedule(
      request.notificationId,
      request.title,
      request.body,
      scheduled,
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: request.payload,
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    await _ensureInitialized();
    await _plugin.cancel(notificationId);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!_timezoneInitialized) {
      tz.initializeTimeZones();
      _timezoneInitialized = true;
    }
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
    _initialized = true;
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
  }

  tz.TZDateTime _toScheduledDate(DateTime value) {
    final scheduled = tz.TZDateTime.from(value.toUtc(), tz.UTC);
    final now = tz.TZDateTime.now(tz.UTC);
    if (scheduled.isAfter(now)) return scheduled;
    return now.add(const Duration(seconds: 5));
  }
}
