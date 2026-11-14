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
