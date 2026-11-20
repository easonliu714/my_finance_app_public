import 'package:sqflite/sqflite.dart';

/// Isolated revision-CAS primitive. No production schema, ledger or preferences.
/// Qualified main-table writes prevent same-connection TEMP namespace shadows
/// from reporting successful consent transitions without durable custody.
class InvoiceAwardIsolatedConsentCas {
  const InvoiceAwardIsolatedConsentCas();

  static const table = 'isolated_invoice_consent_cas';
  static const _maxBusyRetries = 16;
  static const _busyRetryDelay = Duration(milliseconds: 25);

  // SQLite normalizes CREATE TABLE IF NOT EXISTS main.<name> into the
  // following main.sqlite_master.sql text. Exact DDL plus the sole SQLite
  // autoindex is a candidate-only schema integrity boundary: extra triggers
  // or weakened CHECKs must never authorize isolated consent transitions.
  static const _expectedDdl =
      'CREATE TABLE $table (\n'
      '        id TEXT PRIMARY KEY,\n'
      '        revision INTEGER NOT NULL CHECK(revision > 0),\n'
      '        state TEXT NOT NULL CHECK(state IN (\'active\',\'claimed\',\'revoked\')),\n'
      '        posting_marker INTEGER NOT NULL DEFAULT 0 CHECK(posting_marker IN (0,1))\n'
      '      )';

  Future<bool> _hasExpectedSchema(DatabaseExecutor executor) async {
    // Qualified metadata prevents TEMP shadowing. Explicit triggers/indexes
    // change security semantics even if the table's own DDL remains intact.
    final objects = await executor.rawQuery(
      'SELECT type, name, sql FROM main.sqlite_master '
      "WHERE tbl_name = ? AND type IN ('table','index','trigger')",
      <Object>[table],
    );
    if (objects.length != 2) return false;
    final tables = objects.where((row) => row['type'] == 'table').toList();
    final indexes = objects.where((row) => row['type'] == 'index').toList();
    return tables.length == 1 &&
        tables.single['name'] == table &&
        tables.single['sql'] == _expectedDdl &&
        indexes.length == 1 &&
        indexes.single['name'] == 'sqlite_autoindex_${table}_1' &&
        indexes.single['sql'] == null;
  }

  Future<void> initialize(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS main.$table (
        id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL CHECK(revision > 0),
        state TEXT NOT NULL CHECK(state IN ('active','claimed','revoked')),
        posting_marker INTEGER NOT NULL DEFAULT 0 CHECK(posting_marker IN (0,1))
      )
    ''');
    // IF NOT EXISTS must not bless a restored or altered lookalike table.
    if (!await _hasExpectedSchema(db)) {
      throw StateError('ISOLATED_CONSENT_SCHEMA_MISMATCH');
    }
  }

  /// Reject unowned consent identity before durable SQLite insertion.
  Future<void> seed(Database db, String id) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id', 'EMPTY_CONSENT_ID');
    // INSERT OR IGNORE preserves existing durable rows without consulting a
    // same-named TEMP table created by another code path on this connection.
    // A duplicate ID must not silently acknowledge a claimed, revoked, or
    // advanced revision as a fresh active consent. Read durable main only.
    // The transaction also serializes this check with competing claim/revoke.
    await db.transaction<void>((txn) async {
      if (!await _hasExpectedSchema(txn)) {
        throw StateError('ISOLATED_CONSENT_SCHEMA_MISMATCH');
      }
      await txn.rawInsert('''
        INSERT OR IGNORE INTO main.$table
          (id, revision, state, posting_marker)
        VALUES (?, 1, 'active', 0)
      ''', <Object>[id]);
      final rows = await txn.rawQuery('''
        SELECT revision, state, posting_marker FROM main.$table WHERE id = ?
      ''', <Object>[id]);
      if (rows.length != 1 ||
          rows.single['revision'] != 1 ||
          rows.single['state'] != 'active' ||
          rows.single['posting_marker'] != 0) {
        throw StateError('ISOLATED_CONSENT_SEED_IDENTITY_CONFLICT');
      }
    });
  }

  /// Retry only SQLite BUSY at transaction acquisition, never change the
  /// caller's expected revision. Exhaustion must fail closed, not throw open.
  // sqflite_common_ffi exposes SQLite BUSY through its exception text, not
  // DatabaseException.isDatabaseLockedError() in this pinned dependency.
  // Require both SQLite code 5 and the locked diagnostic; fail closed otherwise.
  bool _isSqliteBusy(DatabaseException error) {
    final diagnostic = error.toString().toLowerCase();
    return diagnostic.contains('database is locked') &&
        (diagnostic.contains('sqliteexception(5)') ||
         diagnostic.contains('sqlite error 5') ||
         diagnostic.contains('sqlite_error 5'));
  }

  Future<bool> _withBoundedBusyRetry(
      Future<bool> Function() operation) async {
    for (var attempt = 0; attempt <= _maxBusyRetries; attempt++) {
      try {
        return await operation();
      } on DatabaseException catch (error) {
        if (!_isSqliteBusy(error)) rethrow;
        if (attempt == _maxBusyRetries) return false;
        await Future<void>.delayed(_busyRetryDelay);
      }
    }
    return false;
  }

  /// A pre-existing synthetic posting marker is inconsistent with active
  /// consent and must never be claimed or revoked into an accepted transition.
  /// Claim and synthetic marker are one SQLite transaction. A stale revision
  /// cannot claim after another connection has committed a revoke/claim.
  Future<bool> claim(Database db, String id, int expectedRevision,
      {bool injectFailure = false}) async {
    if (id.trim().isEmpty || expectedRevision <= 0) return false;
    return _withBoundedBusyRetry(() => db.transaction<bool>((txn) async {
      if (!await _hasExpectedSchema(txn)) return false;
      final changed = await txn.rawUpdate('''
        UPDATE main.$table SET state = 'claimed', revision = revision + 1,
          posting_marker = 1
        WHERE id = ? AND revision = ? AND state = 'active'
          AND posting_marker = 0
          AND typeof(revision) = 'integer'
          AND revision < 9223372036854775807
      ''', <Object>[id, expectedRevision]);
      if (changed != 1) return false;
      if (injectFailure) throw StateError('ISOLATED_CAS_ROLLBACK_PROBE');
      return true;
    }));
  }

  Future<bool> revoke(Database db, String id, int expectedRevision) async {
    if (id.trim().isEmpty || expectedRevision <= 0) return false;
    return _withBoundedBusyRetry(() => db.transaction<bool>((txn) async {
      if (!await _hasExpectedSchema(txn)) return false;
      final changed = await txn.rawUpdate('''
        UPDATE main.$table SET state = 'revoked', revision = revision + 1
        WHERE id = ? AND revision = ? AND state = 'active'
          AND posting_marker = 0
          AND typeof(revision) = 'integer'
          AND revision < 9223372036854775807
      ''', <Object>[id, expectedRevision]);
      return changed == 1;
    }));
  }
}
