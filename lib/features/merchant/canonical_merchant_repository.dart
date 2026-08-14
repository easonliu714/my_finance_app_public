import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v13.dart';
import 'legacy_merchant_migration_service.dart';
import 'merchant_record.dart';
import 'merchant_store.dart';

class CanonicalMerchantRepository implements MerchantStore {
  CanonicalMerchantRepository._();

  static final CanonicalMerchantRepository instance =
      CanonicalMerchantRepository._();

  final LegacyMerchantMigrationService _legacyMigration =
      const LegacyMerchantMigrationService();
  Future<void>? _migrationFuture;

  Future<Database> get _db async {
    final db = await ProductionDatabaseCoordinator.instance.database;
    await createCanonicalProductionV13Tables(db);
    _migrationFuture ??= _legacyMigration.migrate(db).then((_) {});
    try {
      await _migrationFuture;
    } catch (_) {
      _migrationFuture = null;
      rethrow;
    }
    return db;
  }

  @override
  Future<List<MerchantRecord>> listMerchants({
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'merchants',
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'name COLLATE NOCASE ASC, alias COLLATE NOCASE ASC, id ASC',
    );
    return rows
        .map(_recordFromRow)
        .where(
          (item) =>
              item.id.trim().isNotEmpty && item.name.trim().isNotEmpty,
        )
        .toList();
  }

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    final db = await _db;
    await db.transaction((txn) async {
      final name = merchant.name.trim();
      final alias = merchant.alias.trim();
      if (name.isEmpty) return;
      final existing = await txn.query(
        'merchants',
        where: 'id = ? OR (name = ? AND alias = ?)',
        whereArgs: [merchant.id, name, alias],
        limit: 1,
      );
      final now = DateTime.now();
      final current =
          existing.isEmpty ? null : _recordFromRow(existing.first);
      final normalized = merchant.copyWith(
        id: current?.id ?? merchant.id,
        name: name,
        alias: alias,
        createdAt: current?.createdAt ?? now,
        updatedAt: now,
      );
      await txn.insert(
        'merchants',
        _recordToRow(normalized),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> archiveMerchant(String id) async {
    final db = await _db;
    await db.update(
      'merchants',
      <String, Object?>{
        'is_archived': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  MerchantRecord _recordFromRow(Map<String, Object?> row) {
    return MerchantRecord(
      id: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      alias: row['alias'] as String? ?? '',
      note: row['note'] as String? ?? '',
      isArchived: (row['is_archived'] as int? ?? 0) != 0,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }

  Map<String, Object?> _recordToRow(MerchantRecord record) {
    return <String, Object?>{
      'id': record.id,
      'name': record.name.trim(),
      'alias': record.alias.trim(),
      'note': record.note.trim(),
      'is_archived': record.isArchived ? 1 : 0,
      'created_at': record.createdAt.toIso8601String(),
      'updated_at': record.updatedAt.toIso8601String(),
    };
  }
}
