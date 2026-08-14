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
}
