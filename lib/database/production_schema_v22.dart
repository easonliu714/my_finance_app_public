import 'package:sqflite/sqflite.dart';

import 'production_schema_v21.dart' show createCanonicalProductionV21Tables;

const int canonicalProductionSchemaVersion = 22;

const List<String> canonicalDefaultExpenseCategories = <String>[
  '早餐',
  '午餐',
  '晚餐',
  '飲料水果',
  '捷運',
  '客運',
  '家居百貨',
  '利息支出',
  '電子數碼',
  '手續費',
  '電影',
  '全部',
];

Future<void> createCanonicalProductionV22Tables(DatabaseExecutor db) async {
  await createCanonicalProductionV21Tables(db);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS expense_categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_system INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_expense_categories_name_unique '
    'ON expense_categories(name)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_expense_categories_sort '
    'ON expense_categories(is_archived, sort_order, name)',
  );
  await _seedDefaultExpenseCategories(db);
}

Future<void> _seedDefaultExpenseCategories(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  for (var index = 0; index < canonicalDefaultExpenseCategories.length; index++) {
    final name = canonicalDefaultExpenseCategories[index];
    await db.insert(
      'expense_categories',
      <String, Object?>{
        'id': 'system_expense_${index + 1}',
        'name': name,
        'sort_order': (index + 1) * 10,
        'is_system': 1,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
