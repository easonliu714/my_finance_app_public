import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;
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

  Future<void> seed(
    Database db, {
    required String accountName,
    required int amount,
  }) async {
    await db.insert('accounts', <String, Object?>{
      'id': 'account-1',
      'name': accountName,
    });
    await db.insert('transactions', <String, Object?>{
      'id': 'ledger-1',
      'amount': amount,
    });
  }

  test('Scope9 exact row-value parity allows an unchanged restore', () async {
    final source = await openSyntheticLedger();
    final target = await openSyntheticLedger();
    addTearDown(source.close);
    addTearDown(target.close);
    await seed(source, accountName: 'source', amount: 200);
    await seed(target, accountName: 'preserved', amount: 300);
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'isolated');

    await const FullRestoreService().restoreFromEnvelope(
      target,
      envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect((await target.query('accounts')).single['name'], 'source');
    expect((await target.query('transactions')).single['amount'], 200);
  });

  test('Scope9 trigger rewriting a cell rolls back despite equal row counts',
      () async {
    final source = await openSyntheticLedger();
    final target = await openSyntheticLedger();
    addTearDown(source.close);
    addTearDown(target.close);
    await seed(source, accountName: 'source', amount: 200);
    await seed(target, accountName: 'preserved', amount: 300);
    // AFTER INSERT mutates a cell but leaves row-count parity unchanged.
    // Without the new post-restore audit, this would commit silently.
    await target.execute(
      "CREATE TRIGGER mutate_account_name AFTER INSERT ON accounts "
      "BEGIN UPDATE accounts SET name = 'trigger-mutated' "
      "WHERE id = NEW.id; END",
    );
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'isolated');

    await expectLater(
      const FullRestoreService().restoreFromEnvelope(
        target,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(
        isA<FullRestoreException>().having(
          (error) => error.message,
          'row-value fidelity failure',
          contains('CURRENT 資料內容與備份不一致'),
        ),
      ),
    );
    // All destructive writes, including ledger writes, must roll back.
    expect((await target.query('accounts')).single['name'], 'preserved');
    expect((await target.query('transactions')).single['amount'], 300);
  });

  // B3 V31: a late restore hook executes after the first integrity audit.
  // A same-count mutation there must still roll back the entire transaction.
  test('Scope9 late post-restore hook cell mutation rolls back atomically',
      () async {
    final source = await openSyntheticLedger();
    final target = await openSyntheticLedger();
    addTearDown(source.close);
    addTearDown(target.close);
    await seed(source, accountName: 'source', amount: 200);
    await seed(target, accountName: 'preserved', amount: 300);
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'isolated');

    await expectLater(
      const _LateHookMutationRestore().restoreFromEnvelope(
        target,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>().having(
        (error) => error.message,
        'late hook cell mutation rejected',
        contains('CURRENT 資料內容與備份不一致'),
      )),
    );
    expect((await target.query('accounts')).single['name'], 'preserved');
    expect((await target.query('transactions')).single['amount'], 300);
  });

  test('Scope9 late post-restore hook row removal rolls back atomically',
      () async {
    final source = await openSyntheticLedger();
    final target = await openSyntheticLedger();
    addTearDown(source.close);
    addTearDown(target.close);
    await seed(source, accountName: 'source', amount: 200);
    await seed(target, accountName: 'preserved', amount: 300);
    final envelope = await const FullBackupService()
        .buildFullBackupEnvelope(source, sourcePlatform: 'isolated');

    await expectLater(
      const _LateHookMutationRestore(removeLedger: true).restoreFromEnvelope(
        target,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>().having(
        (error) => error.message,
        'late hook row deletion rejected',
        contains('CURRENT 資料內容與備份不一致'),
      )),
    );
    expect((await target.query('accounts')).single['name'], 'preserved');
    expect((await target.query('transactions')).single['amount'], 300);
  });
}

class _LateHookMutationRestore extends FullRestoreService {
  const _LateHookMutationRestore({this.removeLedger = false});

  final bool removeLedger;

  @override
  Future<void> afterManagedRestoreTransaction(DatabaseExecutor txn) async {
    if (removeLedger) {
      await txn.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>['ledger-1'],
      );
      return;
    }
    await txn.update(
      'accounts',
      <String, Object?>{'name': 'late-hook-mutated'},
      where: 'id = ?',
      whereArgs: <Object?>['account-1'],
    );
  }
}
