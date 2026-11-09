import 'package:flutter_test/flutter_test.dart';
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
}
