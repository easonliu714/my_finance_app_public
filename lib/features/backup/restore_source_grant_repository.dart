import 'package:sqflite/sqflite.dart';

import 'restore_source_grant.dart';

class RestoreSourceGrantRepository {
  const RestoreSourceGrantRepository();

  static const String tableName = 'app_settings';
  static const String _uriKey = 'restore_source.uri';
  static const String _displayNameKey = 'restore_source.display_name';
  static const String _grantedAtKey = 'restore_source.granted_at';
  static const String _sourceKindKey = 'restore_source.source_kind';
  static const String _persistedKey = 'restore_source.persisted';
  static const String _pathBackedKey = 'restore_source.path_backed';

  Future<RestoreSourceGrant?> load(DatabaseExecutor db) async {
    await ensureTable(db);
    final rows = await db.query(
      tableName,
      columns: const <String>['key', 'value'],
      where: 'key IN (?, ?, ?, ?, ?, ?)',
      whereArgs: const <Object?>[_uriKey, _displayNameKey, _grantedAtKey, _sourceKindKey, _persistedKey, _pathBackedKey],
    );
    if (rows.isEmpty) return null;
    final map = <String, Object?>{};
    for (final row in rows) {
      map[row['key'].toString()] = row['value'];
    }
    final uri = map[_uriKey]?.toString() ?? '';
    if (uri.isEmpty) return null;
    return RestoreSourceGrant.fromMap(<String, Object?>{
      'uri': uri,
      'display_name': map[_displayNameKey],
      'granted_at': map[_grantedAtKey],
      'source_kind': map[_sourceKindKey],
      'persisted': map[_persistedKey],
      'path_backed': map[_pathBackedKey],
    });
  }

  Future<void> save(DatabaseExecutor db, RestoreSourceGrant grant) async {
    await ensureTable(db);
    final values = grant.toMap();
    await _upsert(db, _uriKey, values['uri']?.toString() ?? '');
    await _upsert(db, _displayNameKey, values['display_name']?.toString() ?? '');
    await _upsert(db, _grantedAtKey, values['granted_at']?.toString() ?? '');
    await _upsert(db, _sourceKindKey, values['source_kind']?.toString() ?? RestoreSourceKind.documentFile.name);
    await _upsert(db, _persistedKey, values['persisted']?.toString() ?? '1');
    await _upsert(db, _pathBackedKey, values['path_backed']?.toString() ?? '1');
  }

  Future<void> clear(DatabaseExecutor db) async {
    await ensureTable(db);
    await db.delete(
      tableName,
      where: 'key IN (?, ?, ?, ?, ?, ?)',
      whereArgs: const <Object?>[_uriKey, _displayNameKey, _grantedAtKey, _sourceKindKey, _persistedKey, _pathBackedKey],
    );
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
