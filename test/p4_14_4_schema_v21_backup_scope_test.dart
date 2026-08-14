import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v20.dart'
    show createCanonicalProductionV20Tables;
import 'package:my_finance_app/database/production_schema_v21.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('V20 to V21 migration is additive and idempotent', () async {
    final db = await _openCoreDatabase();
    addTearDown(db.close);
    await createCanonicalProductionV20Tables(db);

    await db.transaction((txn) => createCanonicalProductionV21Tables(txn));
    await db.transaction((txn) => createCanonicalProductionV21Tables(txn));

    expect(canonicalProductionSchemaVersion, 21);
    final objects = await _schemaObjects(db);
    expect(
      objects,
      containsAll(<String>{
        'wallet_top_up_executions',
        'trg_wallet_top_up_executions_no_update',
        'trg_wallet_top_up_executions_no_delete',
      }),
    );
  });

  test('injected V21 migration failure rolls back execution objects', () async {
    final db = await _openCoreDatabase();
    addTearDown(db.close);
    await createCanonicalProductionV20Tables(db);

    await expectLater(
      db.transaction((txn) async {
        await createCanonicalProductionV21Tables(
          txn,
          stageHook: (stage) async {
            if (stage ==
                ProductionSchemaV21MigrationStage.afterWalletTopUpExecution) {
              throw StateError('injected V21 failure');
            }
          },
        );
      }),
      throwsA(isA<StateError>()),
    );

    final objects = await _schemaObjects(db);
    expect(objects, isNot(contains('wallet_top_up_executions')));
    expect(
      objects,
      isNot(contains('trg_wallet_top_up_executions_no_update')),
    );
    expect(
      objects,
      isNot(contains('trg_wallet_top_up_executions_no_delete')),
    );
  });

  test('Backup Scope V7 adds only the execution ledger after Scope V6', () {
    expect(FullBackupScope.databaseSchemaVersion, 21);
    expect(FullBackupScope.backupScopeVersion, 7);
    expect(FullBackupScope.supportedBackupScopeVersions, containsAll(<int>{
      2,
      3,
      4,
      5,
      6,
      7,
    }));
    expect(
      FullBackupScope.backupTableNames,
      <String>[
        ...FullBackupScope.legacyScopeV6TableNames,
        'wallet_top_up_executions',
      ],
    );
    expect(
      FullBackupScope.scopeV7OptionalForLegacyRestore,
      <String>{'wallet_top_up_executions'},
    );
  });
}

Future<Database> _openCoreDatabase() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
    onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
  );
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      suffix TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      credit_limit REAL NOT NULL DEFAULT 0,
      statement_day INTEGER NOT NULL DEFAULT 1,
      payment_due_day INTEGER NOT NULL DEFAULT 1,
      payment_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_principal REAL NOT NULL DEFAULT 0,
      annual_interest_rate REAL NOT NULL DEFAULT 0,
      loan_term_months INTEGER NOT NULL DEFAULT 0,
      loan_repayment_method TEXT NOT NULL DEFAULT 'equalPrincipalAndInterest',
      loan_payment_due_day INTEGER NOT NULL DEFAULT 1,
      loan_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      loan_reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_start_date TEXT,
      loan_disbursement_account_name TEXT NOT NULL DEFAULT '',
      loan_handling_fee REAL NOT NULL DEFAULT 0,
      loan_disbursement_created INTEGER NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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
      note TEXT NOT NULL,
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      exchange_rate_to_base REAL NOT NULL DEFAULT 1,
      base_amount REAL NOT NULL DEFAULT 0,
      from_account_name TEXT,
      to_account_name TEXT,
      repayment_group_id TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  return db;
}

Future<Set<String>> _schemaObjects(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']).whereType<String>().toSet();
}
