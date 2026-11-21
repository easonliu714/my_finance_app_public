import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('full backup keeps one coherent snapshot while SQLite writers serialize',
      () async {
    final root = await Directory.systemTemp.createTemp('finance-backup-snapshot-');
    final path = p.join(root.path, 'isolated.db');
    final reader = await openDatabase(path, singleInstance: false);
    await reader.rawQuery('PRAGMA journal_mode=WAL');
    await reader.execute(
      'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await reader.execute(
      'CREATE TABLE transactions (id TEXT PRIMARY KEY, amount INTEGER NOT NULL)',
    );
    await reader.insert('accounts', <String, Object?>{
      'id': 'synthetic-account',
      'name': 'before',
    });
    await reader.insert('transactions', <String, Object?>{
      'id': 'synthetic-ledger',
      'amount': 1,
    });
    final writer = await openDatabase(path, singleInstance: false);
    // sqflite transaction(exclusive: false) starts BEGIN IMMEDIATE, not
    // BEGIN DEFERRED. Fail fast on a competing write instead of hanging CI.
    await writer.execute('PRAGMA busy_timeout = 0');
    addTearDown(() async {
      await writer.close();
      await reader.close();
      await root.delete(recursive: true);
    });

    final accountsRead = Completer<void>();
    final resumeBackup = Completer<void>();
    final service = FullBackupService(
      afterManagedTableReadForTesting: (tableName) async {
        if (tableName != 'accounts') return;
        accountsRead.complete();
        await resumeBackup.future;
      },
    );
    final backupFuture =
        service.buildFullBackupEnvelope(reader, sourcePlatform: 'isolated');

    try {
      await accountsRead.future.timeout(const Duration(seconds: 10));
      // sqflite's exclusive:false maps to BEGIN IMMEDIATE and reserves the
      // SQLite writer slot. WAL does not allow a second writer to commit here.
      // This negative assertion also fails against the old unprotected
      // per-table backup: its competing writer would commit successfully.
      await expectLater(
        writer.transaction((txn) async {
          await txn.update(
            'accounts',
            <String, Object?>{'name': 'after'},
            where: 'id = ?',
            whereArgs: <Object?>['synthetic-account'],
          );
          await txn.update(
            'transactions',
            <String, Object?>{'amount': 2},
            where: 'id = ?',
            whereArgs: <Object?>['synthetic-ledger'],
          );
        }).timeout(const Duration(seconds: 10)),
        throwsA(predicate(
          (error) => error.toString().contains('database is locked'),
        )),
      );
    } finally {
      // Never leave the snapshot barrier held after a failing assertion.
      resumeBackup.complete();
    }

    final backup = await backupFuture.timeout(const Duration(seconds: 10));
    final data = backup['data']! as Map<String, Object?>;
    final accounts = data['accounts']! as List;
    final ledger = data['transactions']! as List;
    expect((accounts.single as Map)['name'], 'before');
    expect((ledger.single as Map)['amount'], 1);
    // After the backup releases its snapshot, the same second connection
    // must be able to commit both rows as one new generation.
    await writer.transaction((txn) async {
      await txn.update(
        'accounts',
        <String, Object?>{'name': 'after'},
        where: 'id = ?',
        whereArgs: <Object?>['synthetic-account'],
      );
      await txn.update(
        'transactions',
        <String, Object?>{'amount': 2},
        where: 'id = ?',
        whereArgs: <Object?>['synthetic-ledger'],
      );
    }).timeout(const Duration(seconds: 10));
    expect((await reader.query('accounts')).single['name'], 'after');
    expect((await reader.query('transactions')).single['amount'], 2);

    // The next complete snapshot must see the new generation in both tables.
    final successor = await const FullBackupService()
        .buildFullBackupEnvelope(reader, sourcePlatform: 'isolated');
    final successorData = successor['data']! as Map<String, Object?>;
    expect(
      ((successorData['accounts']! as List).single as Map)['name'],
      'after',
    );
    expect(
      ((successorData['transactions']! as List).single as Map)['amount'],
      2,
    );
  });

  test('already-transactional backup does not open a nested transaction',
      () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    addTearDown(db.close);
    await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
    await db.insert('accounts', <String, Object?>{'id': 'fixture'});
    final backup = await db.transaction(
      (txn) => const FullBackupService().buildFullBackupEnvelope(
        txn,
        sourcePlatform: 'isolated',
      ),
    );
    final data = backup['data']! as Map<String, Object?>;
    expect((data['accounts']! as List), hasLength(1));
  });
}
