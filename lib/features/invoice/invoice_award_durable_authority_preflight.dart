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
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[authorityTable],
    );
    if (rows.length != 1) return false;
    final columns = await db.rawQuery('PRAGMA table_info(invoice_award_durable_consent)');
    const expected = <String>['id', 'revision', 'state'];
    if (columns.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (columns[i]['name'] != expected[i] || columns[i]['notnull'] != 1) {
        return false;
      }
    }
    // Shape inspection is not migration provenance or backup/restore custody.
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
