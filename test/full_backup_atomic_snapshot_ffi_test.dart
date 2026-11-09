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

  test('full backup uses one WAL read snapshot across concurrent commits',
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
      // A separate WAL connection must be able to commit while the backup
      // remains paused. A non-transactional backup would mix generations.
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
    } finally {
      resumeBackup.complete();
    }

    final backup = await backupFuture.timeout(const Duration(seconds: 10));
    final data = backup['data']! as Map<String, Object?>;
    final accounts = data['accounts']! as List;
    final ledger = data['transactions']! as List;
    expect((accounts.single as Map)['name'], 'before');
    expect((ledger.single as Map)['amount'], 1);
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
