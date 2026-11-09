import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openSyntheticLedger() async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute(
      'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE transactions (id TEXT PRIMARY KEY, amount INTEGER NOT NULL)',
    );
    return db;
  }

  test('current Scope9 rejects unlisted future custody data before I/O',
      () async {
    final db = await openSyntheticLedger();
    addTearDown(db.close);
    await db.insert('accounts', <String, Object?>{
      'id': 'account-1',
      'name': 'preserved',
    });
    await db.insert('transactions', <String, Object?>{
      'id': 'ledger-1',
      'amount': 100,
    });
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated');
    final data = envelope['data']! as Map<String, Object?>;
    data['future_durable_consent'] = <Map<String, Object?>>[
      <String, Object?>{'revision': 1, 'grant': 'synthetic'},
    ];
    var custodyCalled = false;
    await expectLater(
      const FullRestoreService().restoreFromEnvelope(
        db,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
        persistPreRestoreBackup: (_) async {
          custodyCalled = true;
          return 'not-written';
        },
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect(custodyCalled, isFalse);
    expect((await db.query('accounts')).single['name'], 'preserved');
    expect((await db.query('transactions')).single['amount'], 100);
  });

  test('current Scope9 rejects forged included table authority', () async {
    final db = await openSyntheticLedger();
    addTearDown(db.close);
    await db.insert('accounts', <String, Object?>{
      'id': 'account-1',
      'name': 'preserved',
    });
    await db.insert('transactions', <String, Object?>{
      'id': 'ledger-1',
      'amount': 100,
    });
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated');
    final metadata = envelope['metadata']! as Map<String, Object?>;
    for (final unexpected in <String>['future_durable_consent', 'accounts']) {
      metadata['included_tables'] = <String>[
        ...FullBackupScope.backupTableNames,
        unexpected,
      ];
      await expectLater(
        const FullRestoreService().restoreFromEnvelope(
          db,
          envelope,
          confirmationText: FullRestoreService.destructiveConfirmationText,
        ),
        throwsA(isA<FullRestoreException>()),
      );
    }
    expect((await db.query('accounts')).single['name'], 'preserved');
    expect((await db.query('transactions')).single['amount'], 100);
  });

  test('current Scope9 rejects unknown ledger columns without erasing rows',
      () async {
    final db = await openSyntheticLedger();
    addTearDown(db.close);
    await db.insert('accounts', <String, Object?>{
      'id': 'account-1',
      'name': 'original',
    });
    await db.insert('transactions', <String, Object?>{
      'id': 'ledger-1',
      'amount': 100,
    });
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated');
    final data = envelope['data']! as Map<String, Object?>;
    final accounts = (data['accounts']! as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    accounts.single['name'] = 'must-not-restore';
    data['accounts'] = accounts;
    final ledger = (data['transactions']! as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    ledger.single['future_consent_revision'] = 'must-not-drop';
    data['transactions'] = ledger;

    await expectLater(
      const FullRestoreService().restoreFromEnvelope(
        db,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect((await db.query('accounts')).single['name'], 'original');
    expect((await db.query('transactions')).single['amount'], 100);
  });

  test('current Scope9 rejects populated managed table absent at destination',
      () async {
    final source = await openSyntheticLedger();
    final target = await openSyntheticLedger();
    addTearDown(source.close);
    addTearDown(target.close);
    await source.execute('CREATE TABLE merchants (id TEXT PRIMARY KEY)');
    await source.insert('merchants', <String, Object?>{'id': 'source-merchant'});
    await source.insert('accounts', <String, Object?>{
      'id': 'source-account',
      'name': 'source',
    });
    await source.insert('transactions', <String, Object?>{
      'id': 'source-ledger',
      'amount': 200,
    });
    await target.insert('accounts', <String, Object?>{
      'id': 'target-account',
      'name': 'preserved',
    });
    await target.insert('transactions', <String, Object?>{
      'id': 'target-ledger',
      'amount': 300,
    });
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'isolated');

    await expectLater(
      const FullRestoreService().restoreFromEnvelope(
        target,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect((await target.query('accounts')).single['name'], 'preserved');
    expect((await target.query('transactions')).single['amount'], 300);
  });

  // Scope9 row-count parity alone cannot detect dropped nullable/defaulted
  // custody fields. Reject omissions before any destructive restore DML.
  Future<void> expectMissingCurrentColumnRejected({
    required String table,
    required String column,
  }) async {
    final db = await openSyntheticLedger();
    addTearDown(db.close);
    await db.execute(
      'ALTER TABLE accounts ADD COLUMN revision INTEGER NOT NULL DEFAULT 7',
    );
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN digest TEXT',
    );
    await db.insert('accounts', <String, Object?>{
      'id': 'account-1',
      'name': 'preserved',
      'revision': 17,
    });
    await db.insert('transactions', <String, Object?>{
      'id': 'ledger-1',
      'amount': 100,
      'digest': 'original-digest',
    });
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated');
    final data = envelope['data']! as Map<String, Object?>;
    final accounts = (data['accounts']! as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    accounts.single['name'] = 'must-not-restore';
    data['accounts'] = accounts;
    final rows = (data[table]! as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    rows.single.remove(column);
    data[table] = rows;
    var custodyCalled = false;

    await expectLater(
      const FullRestoreService().restoreFromEnvelope(
        db,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
        persistPreRestoreBackup: (_) async {
          custodyCalled = true;
          return 'isolated-custody';
        },
      ),
      throwsA(
        isA<FullRestoreException>().having(
          (error) => error.message,
          'column custody failure',
          contains('缺少目標欄位'),
        ),
      ),
    );
    expect(custodyCalled, isTrue);
    final savedAccount = (await db.query('accounts')).single;
    final savedLedger = (await db.query('transactions')).single;
    expect(savedAccount['name'], 'preserved');
    expect(savedAccount['revision'], 17);
    expect(savedLedger['amount'], 100);
    expect(savedLedger['digest'], 'original-digest');
  }

  test('Scope9 rejects omitted defaulted revision before destructive DML',
      () async {
    await expectMissingCurrentColumnRejected(
      table: 'accounts',
      column: 'revision',
    );
  });

  test('Scope9 rejects omitted nullable ledger digest before destructive DML',
      () async {
    await expectMissingCurrentColumnRejected(
      table: 'transactions',
      column: 'digest',
    );
  });

}
