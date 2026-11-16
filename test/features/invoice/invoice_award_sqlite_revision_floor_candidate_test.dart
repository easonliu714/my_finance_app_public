import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_restore_floor_readback.dart';
import 'package:my_finance_app/features/invoice/invoice_award_revision_floor_custody.dart';
import 'package:my_finance_app/features/invoice/invoice_award_sqlite_revision_floor_candidate.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _table = InvoiceAwardSqliteRevisionFloorCandidate.table;
const _id = InvoiceAwardSqliteRevisionFloorCandidate.singletonId;
const _custody = InvoiceAwardRevisionFloorCustody();
const _restore = InvoiceAwardRestoreFloorReadback();

Future<void> _seed(Database db, int revision) async {
  await db.execute(InvoiceAwardSqliteRevisionFloorCandidate.candidateDdl);
  await db.insert(_table, <String, Object>{
    'id': _id,
    'revision': revision,
  });
}

InvoiceAwardSqliteRevisionFloorCandidate _store(Database db) =>
    InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(db);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('two independent disk SQLite connections allow exactly one CAS', () async {
    final dir = await Directory.systemTemp.createTemp('v25b_cas_');
    final path = dir.path + '/candidate-floor.db';
    final first = await openDatabase(path, singleInstance: false);
    final second = await openDatabase(path, singleInstance: false);
    try {
      await _seed(first, 7);
      final results = await Future.wait(<Future<bool>>[
        _custody.advanceCandidate(
          store: _store(first), independentlyAuthenticated: true,
          expectedFloor: 7, nextFloor: 8,
        ),
        _custody.advanceCandidate(
          store: _store(second), independentlyAuthenticated: true,
          expectedFloor: 7, nextFloor: 8,
        ),
      ]);
      expect(results.where((accepted) => accepted), hasLength(1));
      expect(await _store(first).readFloor(), 8);
      expect(await _store(second).readFloor(), 8);
      expect(await _custody.advanceCandidate(
        store: _store(second), independentlyAuthenticated: true,
        expectedFloor: 7, nextFloor: 9,
      ), isFalse);
    } finally {
      await first.close();
      await second.close();
      await dir.delete(recursive: true);
    }
  });

  test('on-disk restart persists floor, stale retry and restore reject', () async {
    final dir = await Directory.systemTemp.createTemp('v25b_restart_');
    final path = dir.path + '/candidate-floor.db';
    final first = await openDatabase(path, singleInstance: false);
    try {
      await _seed(first, 2);
      expect(await _custody.advanceCandidate(
        store: _store(first), independentlyAuthenticated: true,
        expectedFloor: 2, nextFloor: 3,
      ), isTrue);
    } finally {
      await first.close();
    }
    final reopened = await openDatabase(path, singleInstance: false);
    try {
      expect(await _store(reopened).readFloor(), 3);
      expect(await _custody.advanceCandidate(
        store: _store(reopened), independentlyAuthenticated: true,
        expectedFloor: 2, nextFloor: 4,
      ), isFalse);
      expect(await _restore.isCandidateCurrent(
        store: _store(reopened),
        independentlyAuthenticated: true,
        restoredRevision: 2,
      ), isFalse);
      expect(_store(reopened).canActivateProduction(), isFalse);
    } finally {
      await reopened.close();
      await dir.delete(recursive: true);
    }
  });

  test('restored separate ledger file cannot lower independently stored floor',
      () async {
    final dir = await Directory.systemTemp.createTemp('v25b_restore_');
    final ledgerPath = dir.path + '/synthetic-ledger.db';
    final backupPath = dir.path + '/synthetic-ledger-backup.db';
    final floorPath = dir.path + '/isolated-floor.db';
    final oldLedger = await openDatabase(ledgerPath, singleInstance: false);
    try {
      await oldLedger.execute('CREATE TABLE snapshot (revision INTEGER NOT NULL)');
      await oldLedger.insert('snapshot', <String, Object>{'revision': 5});
    } finally {
      await oldLedger.close();
    }
    await File(ledgerPath).copy(backupPath);
    final floor = await openDatabase(floorPath, singleInstance: false);
    try {
      await _seed(floor, 6);
      expect(await _custody.advanceCandidate(
        store: _store(floor), independentlyAuthenticated: true,
        expectedFloor: 6, nextFloor: 7,
      ), isTrue);
      await File(backupPath).copy(ledgerPath);
      final restoredLedger =
          await openDatabase(ledgerPath, singleInstance: false);
      try {
        final restoredRevision =
            (await restoredLedger.query('snapshot')).single['revision'] as int;
        expect(restoredRevision, 5);
        expect(await _store(floor).readFloor(), 7);
        expect(await _restore.isCandidateCurrent(
          store: _store(floor), independentlyAuthenticated: true,
          restoredRevision: restoredRevision,
        ), isFalse);
      } finally {
        await restoredLedger.close();
      }
    } finally {
      await floor.close();
      await dir.delete(recursive: true);
    }
  });

  test('missing or duplicated floor row cannot bootstrap authority', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute(InvoiceAwardSqliteRevisionFloorCandidate.candidateDdl);
      expect(await _store(db).readFloor(), isNull);
      expect(await _custody.advanceCandidate(
        store: _store(db), independentlyAuthenticated: true,
        expectedFloor: 0, nextFloor: 1,
      ), isFalse);
      expect(await db.query(_table), isEmpty);
      await db.insert(_table, <String, Object>{'id': _id, 'revision': 0});
      await db.insert(
          _table, <String, Object>{'id': 'injected', 'revision': 0});
      expect(await _store(db).readFloor(), isNull);
      expect(await _custody.advanceCandidate(
        store: _store(db), independentlyAuthenticated: true,
        expectedFloor: 0, nextFloor: 1,
      ), isFalse);
      expect((await db.query(_table)).every((row) => row['revision'] == 0), isTrue);
    } finally {
      await db.close();
    }
  });

  test('weakened DDL and injected trigger fail closed with no CAS write',
      () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute(
          'CREATE TABLE $_table (id TEXT PRIMARY KEY, revision INTEGER)');
      await db.insert(_table, <String, Object>{'id': _id, 'revision': 4});
      expect(await _store(db).readFloor(), isNull);
      expect(await _custody.advanceCandidate(
        store: _store(db), independentlyAuthenticated: true,
        expectedFloor: 4, nextFloor: 5,
      ), isFalse);
      await db.execute('DROP TABLE $_table');
      await _seed(db, 4);
      await db.execute(
        'CREATE TRIGGER injected_floor BEFORE UPDATE ON $_table '
        "BEGIN SELECT RAISE(ABORT, 'blocked'); END",
      );
      expect(await _store(db).readFloor(), isNull);
      expect(await _custody.advanceCandidate(
        store: _store(db), independentlyAuthenticated: true,
        expectedFloor: 4, nextFloor: 5,
      ), isFalse);
      expect((await db.query(_table)).single['revision'], 4);
    } finally {
      await db.close();
    }
  });

  test('SQLite rollback preserves the original revision', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await _seed(db, 11);
      try {
        await db.transaction<void>((txn) async {
          await txn.rawUpdate(
            'UPDATE $_table SET revision = 12 WHERE id = ?',
            <Object>[_id],
          );
          throw StateError('synthetic failure');
        });
        fail('rollback should throw');
      } on StateError {
        // This is a real SQLite rollback, not a mocked revision store.
      }
      expect(await _store(db).readFloor(), 11);
    } finally {
      await db.close();
    }
  });
}
