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

  /// Detect an unsafe partial migration without changing the database.
  Future<bool> hasUnapprovedAuthorityTable(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[authorityTable],
    );
    return rows.isNotEmpty;
  }
}
