import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_audit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('schema audit inventories objects without reading financial rows', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE accounts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY,
              account_id INTEGER NOT NULL,
              note TEXT NOT NULL,
              FOREIGN KEY(account_id) REFERENCES accounts(id)
            )
          ''');
          await database.execute(
            'CREATE INDEX idx_transactions_account '
            'ON transactions(account_id)',
          );
          await database.execute('''
            CREATE VIEW account_transaction_counts AS
            SELECT account_id, COUNT(*) AS transaction_count
            FROM transactions
            GROUP BY account_id
          ''');
          await database.execute('''
            CREATE TRIGGER transactions_note_guard
            BEFORE INSERT ON transactions
            WHEN NEW.note IS NULL
            BEGIN
              SELECT RAISE(ABORT, 'note_required');
            END
          ''');
        },
      ),
    );

    final accountId = await db.insert(
      'accounts',
      <String, Object?>{'name': 'Sensitive Account Name'},
    );
    await db.insert('transactions', <String, Object?>{
      'id': 'tx-sensitive',
      'account_id': accountId,
      'note': 'Sensitive financial note',
    });

    const service = ProductionSchemaAuditService();
    final report = await service.inspect(db);
    final encoded = jsonEncode(report.toJson());

    expect(report.userVersion, 12);
    expect(report.tables.keys, containsAll(<String>['accounts', 'transactions']));
    expect(
      report.objects.map((object) => object.name),
      containsAll(<String>[
        'idx_transactions_account',
        'account_transaction_counts',
        'transactions_note_guard',
      ]),
    );
    expect(
      report.tables['transactions']!.foreignKeys.single['parent_table'],
      'accounts',
    );
    final transactionIndexes = report.tables['transactions']!.indexes;
    expect(
      transactionIndexes.any(
        (index) => index['name'] == 'idx_transactions_account',
      ),
      isTrue,
    );
    expect(
      report.sqliteSequence.single['table_name'],
      'accounts',
    );

    expect(encoded, isNot(contains('Sensitive Account Name')));
    expect(encoded, isNot(contains('Sensitive financial note')));
    expect(encoded, isNot(contains('tx-sensitive')));

    await db.close();
  });

  // B3 #18: metadata-only audit on an isolated in-memory fixture.
  // Preserve composite FK ordering, partial uniqueness, and row privacy.
  test('B3 isolated schema audit preserves composite FK and partial uniqueness',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE b3_accounts (
              account_id TEXT NOT NULL,
              currency_code TEXT NOT NULL,
              PRIMARY KEY (account_id, currency_code)
            )
          ''');
          await database.execute('''
            CREATE TABLE b3_transactions (
              id TEXT PRIMARY KEY,
              account_id TEXT NOT NULL,
              currency_code TEXT NOT NULL,
              note TEXT,
              FOREIGN KEY (account_id, currency_code)
                REFERENCES b3_accounts(account_id, currency_code)
            )
          ''');
          await database.execute(
            'CREATE UNIQUE INDEX b3_unique_live_account '
            'ON b3_transactions(account_id, currency_code) '
            'WHERE note IS NOT NULL',
          );
        },
      ),
    );
    addTearDown(db.close);
    await db.insert('b3_accounts', <String, Object?>{
      'account_id': 'synthetic-private-account',
      'currency_code': 'TWD',
    });
    await db.insert('b3_transactions', <String, Object?>{
      'id': 'synthetic-private-transaction',
      'account_id': 'synthetic-private-account',
      'currency_code': 'TWD',
      'note': 'synthetic-private-note',
    });
    final changesBefore = (await db.rawQuery(
      'SELECT total_changes() AS n',
    )).single['n'];

    const audit = ProductionSchemaAuditService();
    final first = await audit.inspect(db);
    final second = await audit.inspect(db);
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    expect(first.userVersion, 1);
    final transactions = first.tables['b3_transactions']!;
    expect(
      transactions.foreignKeys.map((fk) => fk['sequence']).toList(),
      <int>[0, 1],
    );
    expect(
      transactions.foreignKeys.map((fk) => fk['from_column']).toList(),
      <String>['account_id', 'currency_code'],
    );
    expect(
      transactions.foreignKeys.map((fk) => fk['to_column']).toList(),
      <String>['account_id', 'currency_code'],
    );
    expect(
      transactions.foreignKeys.every(
        (fk) => fk['parent_table'] == 'b3_accounts',
      ),
      isTrue,
    );
    final uniqueIndex = transactions.indexes.singleWhere(
      (index) => index['name'] == 'b3_unique_live_account',
    );
    expect(uniqueIndex['unique'], isTrue);
    expect(uniqueIndex['partial'], isTrue);
    final columns = uniqueIndex['columns']! as List<Map<String, Object?>>;
    expect(
      columns.map((column) => column['name']).toList(),
      <String>['account_id', 'currency_code'],
    );
    final reportJson = jsonEncode(first.toJson());
    expect(reportJson, isNot(contains('synthetic-private-account')));
    expect(reportJson, isNot(contains('synthetic-private-transaction')));
    expect(reportJson, isNot(contains('synthetic-private-note')));
    expect(
      (await db.rawQuery('SELECT total_changes() AS n')).single['n'],
      changesBefore,
    );
  });
}
