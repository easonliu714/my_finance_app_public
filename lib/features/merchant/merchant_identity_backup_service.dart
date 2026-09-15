import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v22.dart';

/// User-owned merchant identity/history backup payload.
///
/// Replaceable official Registry cache tables are intentionally excluded.
/// Restore is additive/idempotent: it never deletes existing user-owned rows.
class MerchantIdentityBackupSnapshot {
  const MerchantIdentityBackupSnapshot(this.tables);

  final Map<String, List<Map<String, Object?>>> tables;
}

class MerchantIdentityBackupService {
  const MerchantIdentityBackupService({required this.database});

  static const List<String> userOwnedTables = <String>[
    'merchant_brands',
    'merchant_brand_aliases',
    'merchant_legal_entities',
    'merchant_branches_or_outlets',
    'merchant_brand_legal_links',
    'merchant_identity_observations',
  ];

  final DatabaseExecutor database;

  Future<MerchantIdentityBackupSnapshot> exportSnapshot() async {
    await createCanonicalProductionV22Tables(database);
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in userOwnedTables) {
      final rows = await database.query(table, orderBy: 'rowid ASC');
      tables[table] = rows
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    }
    return MerchantIdentityBackupSnapshot(tables);
  }

  Future<void> restoreSnapshot(MerchantIdentityBackupSnapshot snapshot) async {
    await createCanonicalProductionV22Tables(database);
    await _runTransaction(database, (txn) async {
      for (final table in userOwnedTables) {
        for (final row
            in snapshot.tables[table] ?? const <Map<String, Object?>>[]) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
  }

  Future<T> _runTransaction<T>(
    DatabaseExecutor db,
    Future<T> Function(DatabaseExecutor txn) action,
  ) async {
    if (db is Database) {
      return db.transaction<T>((txn) => action(txn));
    }
    return action(db);
  }
}
