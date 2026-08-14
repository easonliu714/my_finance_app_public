import 'package:sqflite/sqflite.dart';

import 'backup_notification_settings.dart';

class BackupNotificationSettingsRepository {
  const BackupNotificationSettingsRepository();

  static const String tableName = 'app_settings';
  static const String _enabledKey = 'backup_notification.enabled';
  static const String _permissionStatusKey = 'backup_notification.permission_status';
  static const String _updatedAtKey = 'backup_notification.updated_at';

  Future<BackupNotificationSettings> load(DatabaseExecutor db) async {
    await ensureTable(db);
    final rows = await db.query(
      tableName,
      columns: const <String>['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const <Object?>[_enabledKey, _permissionStatusKey, _updatedAtKey],
    );
    if (rows.isEmpty) return BackupNotificationSettings.defaults();
    final map = <String, Object?>{};
    for (final row in rows) {
      map[row['key'].toString()] = row['value'];
    }
    return BackupNotificationSettings(
      enabled: _boolValue(map[_enabledKey], fallback: false),
      permissionStatus: BackupNotificationPermissionStatus.values.firstWhere(
        (status) => status.name == map[_permissionStatusKey]?.toString(),
        orElse: () => BackupNotificationPermissionStatus.notRequested,
      ),
      updatedAt: DateTime.tryParse(map[_updatedAtKey]?.toString() ?? ''),
    );
  }

  Future<void> save(DatabaseExecutor db, BackupNotificationSettings settings) async {
    await ensureTable(db);
    final updatedAt = settings.updatedAt ?? DateTime.now().toUtc();
    await _upsert(db, _enabledKey, settings.enabled ? '1' : '0');
    await _upsert(db, _permissionStatusKey, settings.permissionStatus.name);
    await _upsert(db, _updatedAtKey, updatedAt.toIso8601String());
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

bool _boolValue(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  final text = value.toString().toLowerCase();
  if (text == '1' || text == 'true') return true;
  if (text == '0' || text == 'false') return false;
  return fallback;
}
