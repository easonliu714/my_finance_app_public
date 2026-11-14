import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_durable_authority_preflight.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const preflight = InvoiceAwardDurableAuthorityPreflight();

  test('missing migration fails closed without creating a table', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
      await db.insert('transactions', <String, Object>{'id': 'synthetic-existing'});
      expect(await preflight.canActivate(db), isFalse);
      expect(await preflight.hasUnapprovedAuthorityTable(db), isFalse);
      expect((await db.query('transactions')).single['id'], 'synthetic-existing');
    } finally {
      await db.close();
    }
  });

  test('unapproved restored authority table never authorizes posting', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute(
        'CREATE TABLE invoice_award_durable_consent (id TEXT PRIMARY KEY)',
      );
      expect(await preflight.hasUnapprovedAuthorityTable(db), isTrue);
      expect(await preflight.canActivate(db), isFalse);
    } finally {
      await db.close();
    }
  });

  test('candidate schema inspection rejects restored/tampered layout', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute('CREATE TABLE invoice_award_durable_consent (id TEXT PRIMARY KEY)');
      expect(await preflight.hasCandidateSchemaShape(db), isFalse);
      expect(await preflight.canActivate(db), isFalse);
      await db.execute('DROP TABLE invoice_award_durable_consent');
      await db.execute('CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL, revision INTEGER NOT NULL, state TEXT NOT NULL, injected TEXT)');
      expect(await preflight.hasCandidateSchemaShape(db), isFalse);
      expect(await preflight.canActivate(db), isFalse);
    } finally {
      await db.close();
    }
  });

  test('candidate shape cannot bypass custody and rollback preserves ledger', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
      await db.insert('transactions', <String, Object>{'id': 'synthetic-existing'});
      try {
        await db.transaction((txn) async {
          await txn.execute("CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision INTEGER NOT NULL CHECK (revision >= 0), state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))");
          expect(await preflight.hasCandidateSchemaShape(txn), isTrue);
          expect(await preflight.canActivate(txn), isFalse);
          throw StateError('synthetic rollback');
        });
      } on StateError catch (error) {
        expect(error.message, 'synthetic rollback');
      }
      expect(await preflight.hasCandidateSchemaShape(db), isFalse);
      expect((await db.query('transactions')).single['id'], 'synthetic-existing');
    } finally {
      await db.close();
    }
  });

  test('strict candidate DDL accepts only constrained synthetic fixture', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute("CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision INTEGER NOT NULL CHECK (revision >= 0), state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))");
      expect(await preflight.hasCandidateSchemaShape(db), isTrue);
      expect(await preflight.canActivate(db), isFalse);
      await db.insert('invoice_award_durable_consent', <String, Object>{
        'id': 'synthetic', 'revision': 0, 'state': 'granted',
      });
      for (final values in <Map<String, Object?>>[
        <String, Object?>{'id': null, 'revision': 1, 'state': 'granted'},
        <String, Object?>{'id': 'bad-revision', 'revision': -1, 'state': 'granted'},
        <String, Object?>{'id': 'bad-state', 'revision': 1, 'state': 'unknown'},
      ]) {
        await expectLater(
          db.insert('invoice_award_durable_consent', values),
          throwsA(isA<Exception>()),
        );
      }
    } finally {
      await db.close();
    }
  });

  test('weakened type PK CHECK nullable ID and comment spoof fail closed', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      const invalid = <String>[
        "CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision TEXT NOT NULL CHECK (revision >= 0), state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))",
        "CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL, revision INTEGER NOT NULL CHECK (revision >= 0), state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))",
        "CREATE TABLE invoice_award_durable_consent (id TEXT PRIMARY KEY, revision INTEGER NOT NULL CHECK (revision >= 0), state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))",
        "CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision INTEGER NOT NULL, state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))",
        "CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision INTEGER NOT NULL CHECK (revision >= 0), state TEXT NOT NULL)",
        "CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision INTEGER NOT NULL, state TEXT NOT NULL) /* CHECK (revision >= 0) CHECK (state IN ('granted', 'revoked')) */",
        "CREATE TABLE invoice_award_durable_consent (id TEXT NOT NULL PRIMARY KEY, revision INTEGER NOT NULL CHECK (revision >= 0), state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')), injected TEXT)",
      ];
      await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
      await db.insert('transactions', <String, Object>{'id': 'synthetic-existing'});
      for (final sql in invalid) {
        await db.execute(sql);
        expect(await preflight.hasCandidateSchemaShape(db), isFalse, reason: sql);
        expect(await preflight.canActivate(db), isFalse);
        await db.execute('DROP TABLE invoice_award_durable_consent');
      }
      expect((await db.query('transactions')).single['id'], 'synthetic-existing');
    } finally {
      await db.close();
    }
  });

  test('read-only inspection preserves existing ledger and schema', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    try {
      await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
      await db.insert('transactions', <String, Object>{'id': 'synthetic-existing'});
      final before = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      expect(await preflight.canActivate(db), isFalse);
      expect(await preflight.hasUnapprovedAuthorityTable(db), isFalse);
      final after = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      expect(after, before);
      expect((await db.query('transactions')).single['id'], 'synthetic-existing');
    } finally {
      await db.close();
    }
  });
}
