import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_notification_settings.dart';
import 'package:my_finance_app/features/backup/backup_notification_status_card.dart';

void main() {
  testWidgets('BackupNotificationStatusCard renders readiness and fires callbacks', (tester) async {
    var enabledChanged = false;
    var permissionRequested = false;
    var smokeRequested = false;
    BackupNotificationPermissionStatus? selectedStatus;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupNotificationStatusCard(
            settings: BackupNotificationSettings(
              enabled: false,
              permissionStatus: BackupNotificationPermissionStatus.notRequested,
              updatedAt: DateTime.utc(2026, 6, 5, 12),
            ),
            onEnabledChanged: (value) => enabledChanged = value,
            onPermissionStatusChanged: (value) => selectedStatus = value,
            onRequestPermission: () => permissionRequested = true,
            onSendSmokeNotification: () => smokeRequested = true,
          ),
        ),
      ),
    );

    expect(find.text('備份通知'), findsOneWidget);
    expect(find.text('尚未可通知'), findsOneWidget);
    expect(find.text('通知：已關閉'), findsOneWidget);
    expect(find.text('目前權限：尚未要求權限'), findsOneWidget);
    expect(find.byKey(BackupNotificationStatusCard.smokeNotificationButtonKey), findsOneWidget);
    expect(find.text('發送測試通知'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    expect(enabledChanged, isTrue);

    await tester.tap(find.byType(DropdownButton<BackupNotificationPermissionStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已允許').last);
    await tester.pumpAndSettle();
    expect(selectedStatus, BackupNotificationPermissionStatus.granted);

    await tester.tap(find.byKey(BackupNotificationStatusCard.requestPermissionButtonKey));
    expect(permissionRequested, isTrue);

    await tester.tap(find.byKey(BackupNotificationStatusCard.smokeNotificationButtonKey));
    expect(smokeRequested, isTrue);
  });

  testWidgets('BackupNotificationStatusCard shows ready state only when enabled and granted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BackupNotificationStatusCard(
            settings: BackupNotificationSettings(
              enabled: true,
              permissionStatus: BackupNotificationPermissionStatus.granted,
              updatedAt: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('可通知'), findsOneWidget);
    expect(find.text('通知：已開啟'), findsOneWidget);
    expect(find.text('目前權限：已允許'), findsOneWidget);
    expect(find.text('更新時間：尚未更新'), findsOneWidget);
    expect(find.byKey(BackupNotificationStatusCard.smokeNotificationButtonKey), findsOneWidget);
  });
}
