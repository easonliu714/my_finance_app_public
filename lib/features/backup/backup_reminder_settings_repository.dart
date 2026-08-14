import 'package:sqflite/sqflite.dart';

import 'backup_reminder_settings.dart';

class BackupReminderSettingsRepository {
  const BackupReminderSettingsRepository();

  static const String tableName = 'app_settings';
  static const String _enabledKey = 'backup_reminder.enabled';
  static const String _intervalDaysKey = 'backup_reminder.interval_days';
  static const String _lastBackupAtKey = 'backup_reminder.last_backup_at';
  static const String _automaticBackupEnabledKey = 'backup_reminder.automatic_backup_enabled';
  static const String _networkUsageAllowedKey = 'backup_reminder.network_usage_allowed';
  static const String _cloudBackupHandoffEnabledKey = 'backup_reminder.cloud_backup_handoff_enabled';

  Future<BackupReminderSettings> load(DatabaseExecutor db) async {
    await ensureTable(db);
    final rows = await db.query(
      tableName,
      columns: const <String>['key', 'value'],
      where: 'key IN (?, ?, ?, ?, ?, ?)',
      whereArgs: const <Object?>[
        _enabledKey,
        _intervalDaysKey,
        _lastBackupAtKey,
        _automaticBackupEnabledKey,
        _networkUsageAllowedKey,
        _cloudBackupHandoffEnabledKey,
      ],
    );
    if (rows.isEmpty) return BackupReminderSettings.defaults();
    final map = <String, Object?>{};
    for (final row in rows) {
      map[row['key'].toString()] = row['value'];
    }
    return BackupReminderSettings.fromMap(<String, Object?>{
      'enabled': map[_enabledKey],
      'interval_days': map[_intervalDaysKey],
      'last_backup_at': map[_lastBackupAtKey],
      'automatic_backup_enabled': map[_automaticBackupEnabledKey],
      'network_usage_allowed': map[_networkUsageAllowedKey],
      'cloud_backup_handoff_enabled': map[_cloudBackupHandoffEnabledKey],
    });
  }

  Future<void> save(DatabaseExecutor db, BackupReminderSettings settings) async {
    await ensureTable(db);
    await _upsert(db, _enabledKey, settings.enabled ? '1' : '0');
    await _upsert(db, _intervalDaysKey, settings.intervalDays.toString());
    await _upsert(db, _lastBackupAtKey, settings.lastBackupAt?.toIso8601String() ?? '');
    await _upsert(db, _automaticBackupEnabledKey, settings.automaticBackupEnabled ? '1' : '0');
    await _upsert(db, _networkUsageAllowedKey, settings.networkUsageAllowed ? '1' : '0');
    await _upsert(db, _cloudBackupHandoffEnabledKey, settings.cloudBackupHandoffEnabled ? '1' : '0');
  }

  Future<void> recordBackupCompleted(DatabaseExecutor db, DateTime completedAt) async {
    final current = await load(db);
    await save(db, current.copyWith(lastBackupAt: completedAt));
  }

  Future<void> ensureTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upsert(DatabaseExecutor db, String key, String value) async {
    await db.insert(
      tableName,
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
