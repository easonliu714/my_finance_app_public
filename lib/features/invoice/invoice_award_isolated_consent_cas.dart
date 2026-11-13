import 'package:sqflite/sqflite.dart';

/// Isolated revision-CAS primitive. No production schema, ledger or preferences.
class InvoiceAwardIsolatedConsentCas {
  const InvoiceAwardIsolatedConsentCas();

  static const table = 'isolated_invoice_consent_cas';
  static const _maxBusyRetries = 16;
  static const _busyRetryDelay = Duration(milliseconds: 25);

  Future<void> initialize(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL CHECK(revision > 0),
        state TEXT NOT NULL CHECK(state IN ('active','claimed','revoked')),
        posting_marker INTEGER NOT NULL DEFAULT 0 CHECK(posting_marker IN (0,1))
      )
    ''');
  }

  Future<void> seed(Database db, String id) async {
    await db.insert(table, <String, Object>{
      'id': id, 'revision': 1, 'state': 'active', 'posting_marker': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Retry only SQLite BUSY at transaction acquisition, never change the
  /// caller's expected revision. Exhaustion must fail closed, not throw open.
  Future<bool> _withBoundedBusyRetry(
      Future<bool> Function() operation) async {
    for (var attempt = 0; attempt <= _maxBusyRetries; attempt++) {
      try {
        return await operation();
      } on DatabaseException catch (error) {
        if (!error.isDatabaseLockedError()) rethrow;
        if (attempt == _maxBusyRetries) return false;
        await Future<void>.delayed(_busyRetryDelay);
      }
    }
    return false;
  }

  /// Claim and synthetic marker are one SQLite transaction. A stale revision
  /// cannot claim after another connection has committed a revoke/claim.
  Future<bool> claim(Database db, String id, int expectedRevision,
      {bool injectFailure = false}) async {
    if (expectedRevision <= 0) return false;
    return _withBoundedBusyRetry(() => db.transaction<bool>((txn) async {
      final changed = await txn.rawUpdate('''
        UPDATE $table SET state = 'claimed', revision = revision + 1,
          posting_marker = 1
        WHERE id = ? AND revision = ? AND state = 'active'
      ''', <Object>[id, expectedRevision]);
      if (changed != 1) return false;
      if (injectFailure) throw StateError('ISOLATED_CAS_ROLLBACK_PROBE');
      return true;
    }));
  }

  Future<bool> revoke(Database db, String id, int expectedRevision) async {
    if (expectedRevision <= 0) return false;
    return _withBoundedBusyRetry(() => db.transaction<bool>((txn) async {
      final changed = await txn.rawUpdate('''
        UPDATE $table SET state = 'revoked', revision = revision + 1
        WHERE id = ? AND revision = ? AND state = 'active'
      ''', <Object>[id, expectedRevision]);
      return changed == 1;
    }));
  }
}
