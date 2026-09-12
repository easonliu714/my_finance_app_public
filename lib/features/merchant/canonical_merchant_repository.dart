import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v13.dart';
import 'legacy_merchant_migration_service.dart';
import 'merchant_record.dart';
import 'merchant_seller_identifier_migration.dart';
import 'merchant_seller_identity_store.dart';
import 'merchant_store.dart';

/// Built-in merchant choices already exposed by the formal transaction-entry
/// surface. They are read-only reference defaults and are never inferred from
/// OCR, speech, Gemini, or other recognition output.
const List<String> canonicalBuiltInTransactionMerchantNames = <String>[
  'OK便利商店',
  '7-ELEVEN',
  '全家便利商店',
  '麥當勞',
  '八方雲集',
];

class CanonicalMerchantRepository
    implements MerchantStore, MerchantSellerIdentityStore {
  CanonicalMerchantRepository._();

  static final CanonicalMerchantRepository instance =
      CanonicalMerchantRepository._();

  final LegacyMerchantMigrationService _legacyMigration =
      const LegacyMerchantMigrationService();
  Future<void>? _migrationFuture;

  Future<Database> get _db async {
    final db = await ProductionDatabaseCoordinator.instance.database;
    await createCanonicalProductionV13Tables(db);
    await ensureMerchantSellerIdentifierSchema(db);
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
    final records = rows
        .map(_recordFromRow)
        .where(
          (item) =>
              item.id.trim().isNotEmpty && item.name.trim().isNotEmpty,
        )
        .toList();

    if (!includeArchived) {
      _appendBuiltInTransactionReferences(records);
      records.sort(
        (left, right) => left.displayName
            .toLowerCase()
            .compareTo(right.displayName.toLowerCase()),
      );
    }
    return records;
  }

  @override
  Future<MerchantRecord?> findBySellerIdentifier(
    String sellerIdentifier, {
    bool includeArchived = false,
  }) async {
    final normalized = _normalizeSellerIdentifier(sellerIdentifier);
    if (normalized.isEmpty) return null;
    final db = await _db;
    final rows = await db.query(
      'merchants',
      where: includeArchived
          ? 'seller_identifier = ?'
          : 'seller_identifier = ? AND is_archived = 0',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    return rows.isEmpty ? null : _recordFromRow(rows.first);
  }

  void _appendBuiltInTransactionReferences(List<MerchantRecord> records) {
    final existing = <String>{
      for (final record in records) ...<String>{
        _normalizeReference(record.name),
        _normalizeReference(record.displayName),
      },
    }..remove('');

    for (var index = 0;
        index < canonicalBuiltInTransactionMerchantNames.length;
        index += 1) {
      final name = canonicalBuiltInTransactionMerchantNames[index];
      if (existing.contains(_normalizeReference(name))) continue;
      records.add(
        MerchantRecord(
          id: 'builtin_transaction_merchant_$index',
          name: name,
          note: 'built-in transaction merchant reference',
        ),
      );
      existing.add(_normalizeReference(name));
    }
  }

  static String _normalizeReference(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·・_\-－—–]'), '')
      .replaceAll('臺', '台');

  static String _normalizeSellerIdentifier(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    final db = await _db;
    await db.transaction((txn) async {
      final name = merchant.name.trim();
      final alias = merchant.alias.trim();
      final sellerIdentifier =
          _normalizeSellerIdentifier(merchant.sellerIdentifier);
      if (name.isEmpty) return;

      if (sellerIdentifier.isNotEmpty) {
        final conflicting = await txn.query(
          'merchants',
          where: 'seller_identifier = ? AND id <> ?',
          whereArgs: <Object?>[sellerIdentifier, merchant.id],
          limit: 1,
        );
        if (conflicting.isNotEmpty) {
          throw StateError('MERCHANT_SELLER_IDENTIFIER_CONFLICT');
        }
      }

      final existing = await txn.query(
        'merchants',
        where: 'id = ? OR (name = ? AND alias = ?)',
        whereArgs: <Object?>[merchant.id, name, alias],
        limit: 1,
      );
      final now = DateTime.now();
      final current = existing.isEmpty ? null : _recordFromRow(existing.first);

      if (sellerIdentifier.isNotEmpty && current != null) {
        final conflicting = await txn.query(
          'merchants',
          where: 'seller_identifier = ? AND id <> ?',
          whereArgs: <Object?>[sellerIdentifier, current.id],
          limit: 1,
        );
        if (conflicting.isNotEmpty) {
          throw StateError('MERCHANT_SELLER_IDENTIFIER_CONFLICT');
        }
      }

      final normalized = merchant.copyWith(
        id: current?.id ?? merchant.id,
        name: name,
        alias: alias,
        sellerIdentifier: sellerIdentifier,
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
      whereArgs: <Object?>[id],
    );
  }

  MerchantRecord _recordFromRow(Map<String, Object?> row) {
    return MerchantRecord(
      id: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      alias: row['alias'] as String? ?? '',
      sellerIdentifier: row['seller_identifier'] as String? ?? '',
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
      'seller_identifier': _normalizeSellerIdentifier(record.sellerIdentifier),
      'note': record.note.trim(),
      'is_archived': record.isArchived ? 1 : 0,
      'created_at': record.createdAt.toIso8601String(),
      'updated_at': record.updatedAt.toIso8601String(),
    };
  }
}
