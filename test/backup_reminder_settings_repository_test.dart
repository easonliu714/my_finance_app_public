import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings.dart';
import 'package:my_finance_app/features/backup/backup_reminder_settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('loads defaults then saves settings', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    const repo = BackupReminderSettingsRepository();

    final defaults = await repo.load(db);
    expect(defaults.enabled, isTrue);
    expect(defaults.intervalDays, 7);
    expect(defaults.automaticBackupEnabled, isFalse);
    expect(defaults.networkUsageAllowed, isFalse);
    expect(defaults.cloudBackupHandoffEnabled, isFalse);

    final saved = BackupReminderSettings(
      enabled: false,
      intervalDays: 14,
      lastBackupAt: DateTime.utc(2026, 6, 1, 8),
      automaticBackupEnabled: true,
      networkUsageAllowed: true,
      cloudBackupHandoffEnabled: true,
    );
    await repo.save(db, saved);

    final loaded = await repo.load(db);
    expect(loaded.enabled, isFalse);
    expect(loaded.intervalDays, 14);
    expect(loaded.lastBackupAt, DateTime.utc(2026, 6, 1, 8));
    expect(loaded.automaticBackupEnabled, isTrue);
    expect(loaded.networkUsageAllowed, isTrue);
    expect(loaded.cloudBackupHandoffEnabled, isTrue);
  });

  test('records backup completion timestamp', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    const repo = BackupReminderSettingsRepository();
    final completedAt = DateTime.utc(2026, 6, 2, 9, 30);

    await repo.recordBackupCompleted(db, completedAt);

    final loaded = await repo.load(db);
    expect(loaded.lastBackupAt, completedAt);
    expect(loaded.nextReminderAt(), DateTime.utc(2026, 6, 9, 9, 30));
  });
}
