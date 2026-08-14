import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_notification_settings.dart';
import 'package:my_finance_app/features/backup/backup_notification_settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('BackupNotificationSettingsRepository saves and loads readiness settings', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    const repo = BackupNotificationSettingsRepository();
    final defaults = await repo.load(db);

    expect(defaults.enabled, isFalse);
    expect(defaults.permissionStatus, BackupNotificationPermissionStatus.notRequested);
    expect(defaults.isReady, isFalse);

    final settings = BackupNotificationSettings(
      enabled: true,
      permissionStatus: BackupNotificationPermissionStatus.granted,
      updatedAt: DateTime.utc(2026, 6, 5, 12),
    );
    await repo.save(db, settings);
    final loaded = await repo.load(db);

    expect(loaded.enabled, isTrue);
    expect(loaded.permissionStatus, BackupNotificationPermissionStatus.granted);
    expect(loaded.updatedAt, settings.updatedAt);
    expect(loaded.isReady, isTrue);
  });
}
