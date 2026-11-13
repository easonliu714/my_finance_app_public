import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_consent_cas.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  const cas = InvoiceAwardIsolatedConsentCas();

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
