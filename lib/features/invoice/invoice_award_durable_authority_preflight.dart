import 'package:sqflite/sqflite.dart';

/// Read-only custody gate for V25-B. This is NOT a consent authority and
/// deliberately cannot create tables, authorize posting, or migrate a ledger.
class InvoiceAwardDurableAuthorityPreflight {
  const InvoiceAwardDurableAuthorityPreflight();

  static const String authorityTable = 'invoice_award_durable_consent';

  /// Production activation stays blocked until schema migration, backup
  /// coverage and restore replay are all explicitly approved.
  Future<bool> canActivate(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[authorityTable],
    );
    if (rows.length != 1) return false;
    // A table's mere presence (including an untrusted restored table) is
    // never sufficient evidence of migration and backup custody.
    return false;
  }

  /// Verify only the exact candidate column layout; never authorize posting.
  /// An attacker-controlled restored table cannot become trusted by name alone.
  Future<bool> hasCandidateSchemaShape(DatabaseExecutor db) async {
    // A candidate is accepted only when its SQLite-owned DDL matches this
    // deliberately narrow, non-production fixture contract byte-for-byte.
    // PRAGMA table_info alone cannot establish CHECK constraints; permissive
    // substring/regex matching would accept SQL comments or weakened clauses.
    const expectedDdl = 'CREATE TABLE invoice_award_durable_consent '
        '(id TEXT NOT NULL PRIMARY KEY, '
        'revision INTEGER NOT NULL CHECK (revision >= 0), '
        "state TEXT NOT NULL CHECK (state IN ('granted', 'revoked')))";
    final rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[authorityTable],
    );
    if (rows.length != 1 || rows.single['sql'] != expectedDdl) return false;
    final columns = await db.rawQuery('PRAGMA table_info(invoice_award_durable_consent)');
    const names = <String>['id', 'revision', 'state'];
    const types = <String>['TEXT', 'INTEGER', 'TEXT'];
    if (columns.length != names.length) return false;
    for (var i = 0; i < names.length; i++) {
      if (columns[i]['name'] != names[i] ||
          columns[i]['type'] != types[i] ||
          columns[i]['notnull'] != 1 ||
          columns[i]['pk'] != (i == 0 ? 1 : 0)) {
        return false;
      }
    }
    // This proves a synthetic candidate shape only, never its provenance.
    return true;
  }

  /// Detect an unsafe partial migration without changing the database.
  Future<bool> hasUnapprovedAuthorityTable(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[authorityTable],
    );
    return rows.isNotEmpty;
  }
}
