import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../database/production_database_coordinator.dart';
import 'expense_category_schema.dart';

class ExpenseCategoryRecord {
  const ExpenseCategoryRecord({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.isSystem = false,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final int sortOrder;
  final bool isSystem;
  final bool isArchived;
}

class ExpenseCategoryRepository {
  ExpenseCategoryRepository._();

  static final ExpenseCategoryRepository instance = ExpenseCategoryRepository._();

  Future<Database> get _db async {
    final db = await ProductionDatabaseCoordinator.instance.database;
    await ensureExpenseCategorySchema(db);
    return db;
  }

  Future<List<ExpenseCategoryRecord>> listActive() async {
    final db = await _db;
    final rows = await db.query(
      'expense_categories',
      where: 'is_archived = 0',
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<ExpenseCategoryRecord?> findActiveByName(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;
    final db = await _db;
    final rows = await db.query(
      'expense_categories',
      where: 'is_archived = 0 AND name = ?',
      whereArgs: <Object?>[name],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<ExpenseCategoryRecord> addUserCategory(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(rawName, 'rawName', '類別名稱不可空白');
    }
    final existing = await findActiveByName(name);
    if (existing != null) return existing;

    final db = await _db;
    final maxRows = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) AS max_sort FROM expense_categories',
    );
    final maxSort = (maxRows.firstOrNull?['max_sort'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toIso8601String();
    final record = ExpenseCategoryRecord(
      id: const Uuid().v4(),
      name: name,
      sortOrder: maxSort + 10,
    );
    await db.insert(
      'expense_categories',
      <String, Object?>{
        'id': record.id,
        'name': record.name,
        'sort_order': record.sortOrder,
        'is_system': 0,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return (await findActiveByName(name)) ?? record;
  }

  ExpenseCategoryRecord _fromRow(Map<String, Object?> row) {
    return ExpenseCategoryRecord(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      isSystem: (row['is_system'] as num?)?.toInt() == 1,
      isArchived: (row['is_archived'] as num?)?.toInt() == 1,
    );
  }
}
