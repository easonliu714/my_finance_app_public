import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_consent_cas.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  const cas = InvoiceAwardIsolatedConsentCas();

  test('blank consent identity fails closed before any SQLite mutation', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await cas.initialize(db);
      for (final invalidId in <String>['', '   ', '\t\n']) {
        await expectLater(cas.seed(db, invalidId), throwsArgumentError);
        expect(await cas.claim(db, invalidId, 1), isFalse);
        expect(await cas.revoke(db, invalidId, 1), isFalse);
      }
      expect(await db.query(InvoiceAwardIsolatedConsentCas.table), isEmpty);
      await cas.seed(db, 'synthetic-valid');
      expect(await cas.claim(db, 'synthetic-valid', 1), isTrue);
      final row = (await db.query(InvoiceAwardIsolatedConsentCas.table)).single;
      expect(row['id'], 'synthetic-valid');
      expect(row['revision'], 2);
      expect(row['posting_marker'], 1);
    } finally {
      await db.close();
    }
  });

  test('seed replay refuses claimed or revoked durable identity', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await cas.initialize(db);
      await cas.seed(db, 'replay-claim');
      await cas.seed(db, 'replay-claim'); // Safe idempotent active seed.
      expect(await cas.claim(db, 'replay-claim', 1), isTrue);
      await expectLater(cas.seed(db, 'replay-claim'),
          throwsA(isA<StateError>()));
      await cas.seed(db, 'replay-revoke');
      expect(await cas.revoke(db, 'replay-revoke', 1), isTrue);
      await expectLater(cas.seed(db, 'replay-revoke'),
          throwsA(isA<StateError>()));
      final rows = await db.rawQuery(
          'SELECT id, revision, state, posting_marker FROM main.${InvoiceAwardIsolatedConsentCas.table} ORDER BY id');
      expect(rows, hasLength(2));
      expect(rows[0]['state'], 'claimed');
      expect(rows[0]['revision'], 2);
      expect(rows[0]['posting_marker'], 1);
      expect(rows[1]['state'], 'revoked');
      expect(rows[1]['revision'], 2);
      expect(rows[1]['posting_marker'], 0);
    } finally {
      await db.close();
    }
  });

  test('weakened restored SQLite schema is rejected before custody writes', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    const table = InvoiceAwardIsolatedConsentCas.table;
    try {
      // Mimic a restored table with the right columns but no CHECK contract.
      await db.execute('''
        CREATE TABLE main.$table (
          id TEXT PRIMARY KEY,
          revision INTEGER,
          state TEXT,
          posting_marker INTEGER
        )
      ''');
      await expectLater(cas.initialize(db), throwsStateError);
      await expectLater(cas.seed(db, 'restore-spoof'), throwsStateError);
      expect(await cas.claim(db, 'restore-spoof', 1), isFalse);
      expect(await cas.revoke(db, 'restore-spoof', 1), isFalse);
      expect(await db.rawQuery('SELECT * FROM main.$table'), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('injected trigger blocks every isolated consent mutation', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    const table = InvoiceAwardIsolatedConsentCas.table;
    try {
      await cas.initialize(db);
      await cas.seed(db, 'canonical');
      await db.execute('''
        CREATE TRIGGER malicious_consent_hook BEFORE UPDATE ON $table
        BEGIN SELECT RAISE(ABORT, 'TRIGGER_MUST_NOT_EXECUTE'); END
      ''');
      // Trigger is an unauthorized modification even though the original
      // main table definition has not changed.
      await expectLater(cas.initialize(db), throwsStateError);
      await expectLater(cas.seed(db, 'new-after-trigger'), throwsStateError);
      expect(await cas.claim(db, 'canonical', 1), isFalse);
      expect(await cas.revoke(db, 'canonical', 1), isFalse);
      final rows = await db.rawQuery(
          'SELECT id, revision, state, posting_marker FROM main.$table');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'canonical');
      expect(rows.single['revision'], 1);
      expect(rows.single['state'], 'active');
      expect(rows.single['posting_marker'], 0);
    } finally {
      await db.close();
    }
  });

  test('TEMP table shadow cannot claim or seed against durable main authority', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    const table = InvoiceAwardIsolatedConsentCas.table;
    try {
      await cas.initialize(db);
      await cas.seed(db, 'synthetic-shadow');
      // Same connection, intentionally conflicting SQLite namespaces. The
      // TEMP row is a stale revision-1 decoy; durable main is revision 2.
      await db.execute('''
        CREATE TEMP TABLE $table (
          id TEXT PRIMARY KEY,
          revision INTEGER NOT NULL,
          state TEXT NOT NULL,
          posting_marker INTEGER NOT NULL
        )
      ''');
      await db.rawInsert('''
        INSERT INTO temp.$table (id, revision, state, posting_marker)
        VALUES (?, 1, 'active', 0)
      ''', <Object>['synthetic-shadow']);
      await db.rawUpdate(
        'UPDATE main.$table SET revision = 2 WHERE id = ?',
        <Object>['synthetic-shadow'],
      );

      // Negative: never report a success from the stale TEMP decoy.
      expect(await cas.claim(db, 'synthetic-shadow', 1), isFalse);
      expect(await cas.revoke(db, 'synthetic-shadow', 1), isFalse);
      // Positive: the current durable revision is still claimable.
      expect(await cas.claim(db, 'synthetic-shadow', 2), isTrue);
      // New seeds must land in main even while TEMP shadows the table name.
      await cas.seed(db, 'synthetic-main-only');
      expect(await cas.revoke(db, 'synthetic-main-only', 1), isTrue);

      final durable = await db.rawQuery(
        'SELECT id, revision, state, posting_marker FROM main.$table ORDER BY id',
      );
      expect(durable, hasLength(2));
      expect(durable[0]['id'], 'synthetic-main-only');
      expect(durable[0]['revision'], 2);
      expect(durable[0]['state'], 'revoked');
      expect(durable[0]['posting_marker'], 0);
      expect(durable[1]['id'], 'synthetic-shadow');
      expect(durable[1]['revision'], 3);
      expect(durable[1]['state'], 'claimed');
      expect(durable[1]['posting_marker'], 1);

      final decoy = await db.rawQuery(
        'SELECT id, revision, state, posting_marker FROM temp.$table',
      );
      expect(decoy, hasLength(1));
      expect(decoy.single['id'], 'synthetic-shadow');
      expect(decoy.single['revision'], 1);
      expect(decoy.single['state'], 'active');
      expect(decoy.single['posting_marker'], 0);
    } finally {
      await db.close();
    }
  });

  test('two independent connections: exactly one claim, stale claim fails', () async {
    final dir = await Directory.systemTemp.createTemp('v25a_cas_');
    final path = '${dir.path}/isolated.db';
    final first = await openDatabase(path, singleInstance: false);
    final second = await openDatabase(path, singleInstance: false);
    try {
      await cas.initialize(first);
      await cas.seed(first, 'synthetic-only');
      final results = await Future.wait(<Future<bool>>[
        cas.claim(first, 'synthetic-only', 1),
        cas.claim(second, 'synthetic-only', 1),
      ]);
      expect(results.where((value) => value).length, 1);
      expect(await cas.claim(second, 'synthetic-only', 1), isFalse);
      expect(await cas.revoke(first, 'synthetic-only', 1), isFalse);
      final rows = await second.query(InvoiceAwardIsolatedConsentCas.table);
      expect(rows.single['posting_marker'], 1);
      expect(rows.single['revision'], 2);
    } finally {
      await first.close(); await second.close(); await dir.delete(recursive: true);
    }
  });

  test('BUSY exhaustion fails closed without changing synthetic marker', () async {
    final dir = await Directory.systemTemp.createTemp('v25a_busy_');
    final path = '${dir.path}/isolated.db';
    final first = await openDatabase(path, singleInstance: false);
    final second = await openDatabase(path, singleInstance: false);
    final entered = Completer<void>();
    final release = Completer<void>();
    try {
      await cas.initialize(first);
      await cas.seed(first, 'synthetic-only');
      final blocker = first.transaction<void>((txn) async {
        await txn.rawUpdate('''
          UPDATE ${InvoiceAwardIsolatedConsentCas.table}
          SET revision = revision WHERE id = ?
        ''', <Object>['synthetic-only']);
        entered.complete();
        await release.future;
      });
      await entered.future;
      expect(await cas.claim(second, 'synthetic-only', 1), isFalse);
      release.complete();
      await blocker;
      final rows = await second.query(InvoiceAwardIsolatedConsentCas.table);
      expect(rows.single['revision'], 1);
      expect(rows.single['state'], 'active');
      expect(rows.single['posting_marker'], 0);
    } finally {
      if (!release.isCompleted) release.complete();
      await first.close(); await second.close(); await dir.delete(recursive: true);
    }
  });

  test('non-BUSY closed database exception is not converted to false', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.close();
    await expectLater(
      cas.claim(db, 'synthetic-only', 1),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('inconsistent active posting marker rejects claim and revoke without write', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await cas.initialize(db);
      await cas.seed(db, 'synthetic-only');
      // Simulate a stale/partially restored marker in isolated custody.
      await db.update(InvoiceAwardIsolatedConsentCas.table,
          <String, Object>{'posting_marker': 1},
          where: 'id = ?', whereArgs: <Object>['synthetic-only']);
      expect(await cas.claim(db, 'synthetic-only', 1), isFalse);
      expect(await cas.revoke(db, 'synthetic-only', 1), isFalse);
      final row = (await db.query(InvoiceAwardIsolatedConsentCas.table)).single;
      expect(row['revision'], 1);
      expect(row['state'], 'active');
      expect(row['posting_marker'], 1);
      // Positive control: valid marker zero remains claimable.
      await db.update(InvoiceAwardIsolatedConsentCas.table,
          <String, Object>{'posting_marker': 0},
          where: 'id = ?', whereArgs: <Object>['synthetic-only']);
      expect(await cas.claim(db, 'synthetic-only', 1), isTrue);
    } finally {
      await db.close();
    }
  });

  test('revoke wins, restart cannot revive stale revision', () async {
    final dir = await Directory.systemTemp.createTemp('v25a_revoke_');
    final path = '${dir.path}/isolated.db';
    final first = await openDatabase(path, singleInstance: false);
    try {
      await cas.initialize(first);
      await cas.seed(first, 'synthetic-only');
      expect(await cas.revoke(first, 'synthetic-only', 1), isTrue);
    } finally { await first.close(); }
    final reopened = await openDatabase(path, singleInstance: false);
    try {
      expect(await cas.claim(reopened, 'synthetic-only', 1), isFalse);
      final rows = await reopened.query(InvoiceAwardIsolatedConsentCas.table);
      expect(rows.single['state'], 'revoked');
      expect(rows.single['posting_marker'], 0);
    } finally { await reopened.close(); await dir.delete(recursive: true); }
  });

  test('injected exception rolls back revision and synthetic marker', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await cas.initialize(db); await cas.seed(db, 'synthetic-only');
      await expectLater(
        cas.claim(db, 'synthetic-only', 1, injectFailure: true),
        throwsStateError,
      );
      final rows = await db.query(InvoiceAwardIsolatedConsentCas.table);
      expect(rows.single['state'], 'active');
      expect(rows.single['revision'], 1);
      expect(rows.single['posting_marker'], 0);
      expect(await cas.claim(db, 'synthetic-only', 1), isTrue);
      expect(await cas.claim(db, 'synthetic-only', 0), isFalse);
    } finally { await db.close(); }
  });
}
