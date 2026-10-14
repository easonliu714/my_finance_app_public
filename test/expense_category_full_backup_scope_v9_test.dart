import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service_v8.dart';
import 'package:my_finance_app/features/category/expense_category_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> newCoreDb() async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
    return db;
  }

  test('Scope V9 exports custom expense categories rather than blocking',
      () async {
    final db = await newCoreDb();
    addTearDown(db.close);
    await ensureExpenseCategorySchema(db);
    await db.insert('expense_categories', <String, Object?>{
      'id': 'owner-custom-1',
      'name': '手沖咖啡',
      'sort_order': 321,
      'is_system': 0,
      'is_archived': 1,
      'created_at': '2026-10-13T00:00:00Z',
      'updated_at': '2026-10-14T00:00:00Z',
    });

    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'test');
    final metadata = envelope['metadata']! as Map<String, Object?>;
    final data = envelope['data']! as Map<String, Object?>;
    final categories = data['expense_categories']! as List;

    expect(FullBackupScope.backupScopeVersion, 9);
    expect(metadata['backup_scope_version'], 9);
    expect(metadata['coverage_complete'], isTrue);
    expect(metadata['unknown_tables'], isEmpty);
    expect(metadata['included_tables'], contains('expense_categories'));
    expect(categories, contains(predicate((row) {
      if (row is! Map) return false;
      return row['id'] == 'owner-custom-1' &&
          row['name'] == '手沖咖啡' &&
          row['is_archived'] == 1 &&
          row['sort_order'] == 321;
    })));
  });

  test('Scope V9 restores categories even to a target without lazy table',
      () async {
    final source = await newCoreDb();
    final target = await newCoreDb();
    addTearDown(source.close);
    addTearDown(target.close);
    await ensureExpenseCategorySchema(source);
    await source.insert('expense_categories', <String, Object?>{
      'id': 'owner-category-1',
      'name': '自訂午茶',
      'sort_order': 455,
      'is_system': 0,
      'is_archived': 0,
      'created_at': '2026-10-13T00:00:00Z',
      'updated_at': '2026-10-13T01:00:00Z',
    });

    final snapshot = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'test');
    await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      snapshot,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    final rows = await target.query(
      'expense_categories',
      where: 'id = ?',
      whereArgs: <Object?>['owner-category-1'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['name'], '自訂午茶');
    expect(rows.single['sort_order'], 455);
    expect(rows.single['is_archived'], 0);

    // Full restoration is repeatable and does not create duplicate category IDs.
    await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      snapshot,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect(await target.query('expense_categories', where: 'id = ?',
      whereArgs: <Object?>['owner-category-1']), hasLength(1));
  });

  test('existing Scope V8 merchant history remains intact on restore',
      () async {
    final source = await newCoreDb();
    final target = await newCoreDb();
    addTearDown(source.close);
    addTearDown(target.close);
    for (final db in <Database>[source, target]) {
      await db.execute('CREATE TABLE merchant_brands ('
          'id TEXT PRIMARY KEY, display_name TEXT)');
    }
    await source.insert('merchant_brands', <String, Object?>{
      'id': 'brand-legacy-1',
      'display_name': '舊版自訂品牌',
    });
    final exported = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'test');
    final envelope = Map<String, Object?>.from(exported);
    final metadata = Map<String, Object?>.from(
        envelope['metadata']! as Map<String, Object?>);
    final data = Map<String, Object?>.from(
        envelope['data']! as Map<String, Object?>);
    metadata['backup_scope_version'] = 8;
    metadata['included_tables'] = FullBackupScope.legacyScopeV8TableNames;
    data.remove('expense_categories');
    envelope['metadata'] = metadata;
    envelope['data'] = data;

    await const FullRestoreServiceV8().restoreFromEnvelope(
      target,
      envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    final rows = await target.query('merchant_brands');
    expect(rows, hasLength(1));
    expect(rows.single['display_name'], '舊版自訂品牌');
  });

  test('unknown user table still fail-closes the complete backup', () async {
    final db = await newCoreDb();
    addTearDown(db.close);
    await ensureExpenseCategorySchema(db);
    await db.execute('CREATE TABLE unknown_owner_data (id TEXT PRIMARY KEY)');
    final report = await FullBackupScope.inspect(db);
    expect(report.unknownTables, contains('unknown_owner_data'));
    await expectLater(
      const FullBackupService().buildFullBackupEnvelope(db),
      throwsA(isA<FullBackupCoverageException>()),
    );
  });

  test('tampered Scope V9 missing category array is rejected', () async {
    final db = await newCoreDb();
    addTearDown(db.close);
    await ensureExpenseCategorySchema(db);
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'test');
    final data = envelope['data']! as Map<String, Object?>;
    data.remove('expense_categories');
    await expectLater(
      const FullRestoreServiceV8().restoreFromEnvelope(
        db,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
  });
}
