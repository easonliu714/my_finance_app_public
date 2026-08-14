import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart' as v16;
import 'package:my_finance_app/database/production_schema_v17.dart' as v17;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v16 database upgrades to v17 without losing existing rows', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    addTearDown(db.close);

    await _createCoreTables(db);
    await v16.createCanonicalProductionV16Tables(db);
    await db.insert('accounts', _accountRow(id: 'bank-1', type: 'bank'));
    await db.insert('transactions', _transactionRow('transaction-existing'));

    await v17.createCanonicalProductionV17Tables(db);
    await v17.createCanonicalProductionV17Tables(db);

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    expect(
      tables,
      containsAll(<String>{
        'debit_card_profiles',
        'debit_card_settlements',
        'taiwan_business_calendar_days',
      }),
    );
    expect(v17.canonicalProductionSchemaVersion, 17);

    expect(
      await _count(db, 'accounts', where: 'id = ?', args: ['bank-1']),
      1,
    );
    expect(
      await _count(
        db,
        'transactions',
        where: 'id = ?',
        args: ['transaction-existing'],
      ),
      1,
    );
    expect(await _count(db, 'taiwan_business_calendar_days'), 730);

    final midAutumn = (await db.query(
      'taiwan_business_calendar_days',
      where: 'calendar_date = ?',
      whereArgs: const <Object?>['2026-09-25'],
    )).single;
    expect(midAutumn['is_business_day'], 0);

    final ordinaryMonday = (await db.query(
      'taiwan_business_calendar_days',
      where: 'calendar_date = ?',
      whereArgs: const <Object?>['2026-06-29'],
    )).single;
    expect(ordinaryMonday['is_business_day'], 1);
  });

  test('v17 constraints protect debit-card ownership and state', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    addTearDown(db.close);

    await _createCoreTables(db);
    await v17.createCanonicalProductionV17Tables(db);
    await db.insert('accounts', _accountRow(id: 'bank-1', type: 'bank'));
    await db.insert(
      'accounts',
      _accountRow(id: 'debit-1', type: 'debitCard'),
    );
    await db.insert('transactions', _transactionRow('purchase-1'));

    await db.insert('debit_card_profiles', <String, Object?>{
      'debit_card_account_id': 'debit-1',
      'linked_bank_account_id': 'bank-1',
      'currency_code': 'TWD',
      'settlement_business_days': 2,
      'is_enabled': 1,
    });
    await db.insert('debit_card_settlements', <String, Object?>{
      'id': 'settlement-1',
      'debit_card_account_id': 'debit-1',
      'linked_bank_account_id': 'bank-1',
      'transaction_id': 'purchase-1',
      'amount': 120,
      'currency_code': 'TWD',
      'authorized_at': '2026-09-24T10:00:00.000Z',
      'expected_settlement_date': '2026-09-30T10:00:00.000Z',
      'status': 'pending',
    });

    expect(await _count(db, 'debit_card_profiles'), 1);
    expect(await _count(db, 'debit_card_settlements'), 1);
    await expectLater(
      db.insert('debit_card_profiles', <String, Object?>{
        'debit_card_account_id': 'bank-1',
        'linked_bank_account_id': 'bank-1',
        'currency_code': 'TWD',
        'settlement_business_days': 2,
        'is_enabled': 1,
      }),
      throwsA(anything),
    );
    await expectLater(
      db.insert('debit_card_settlements', <String, Object?>{
        'id': 'invalid-terminal',
        'debit_card_account_id': 'debit-1',
        'linked_bank_account_id': 'bank-1',
        'transaction_id': 'purchase-1',
        'amount': 120,
        'currency_code': 'TWD',
        'authorized_at': '2026-09-24T10:00:00.000Z',
        'expected_settlement_date': '2026-09-30T10:00:00.000Z',
        'status': 'confirmed',
        'terminal_at': null,
      }),
      throwsA(anything),
    );
  });
}

Future<void> _createCoreTables(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      suffix TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      account_name TEXT NOT NULL,
      member_name TEXT NOT NULL,
      merchant_name TEXT NOT NULL,
      tag_name TEXT NOT NULL,
      note TEXT NOT NULL
    )
  ''');
}

Map<String, Object?> _accountRow({required String id, required String type}) =>
    <String, Object?>{
      'id': id,
      'name': id,
      'type': type,
      'initial_balance': 0,
      'sort_order': 0,
      'suffix': '',
      'currency_code': 'TWD',
      'note': '',
      'is_archived': 0,
    };

Map<String, Object?> _transactionRow(String id) => <String, Object?>{
      'id': id,
      'type': 'expense',
      'amount': 100,
      'category': '餐飲',
      'occurred_at': '2026-06-28T00:00:00.000Z',
      'account_name': 'debit-1',
      'member_name': '',
      'merchant_name': '',
      'tag_name': '',
      'note': '',
    };

Future<int> _count(
  Database db,
  String table, {
  String? where,
  List<Object?>? args,
}) async {
  final rows = await db.query(table, where: where, whereArgs: args);
  return rows.length;
}
