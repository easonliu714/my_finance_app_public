import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';

import 'invoice_award_revision_floor_custody.dart';

/// Real SQLite CAS over an explicitly supplied *isolated* candidate database.
///
/// This proves persistence across file reopen and atomicity across independent
/// SQLite connections, NOT Android noBackup provenance, process isolation,
/// authenticatable monotonic authority, or protection against device rollback.
/// Do not connect to the production ledger or formal posting/restore.
@visibleForTesting
class InvoiceAwardSqliteRevisionFloorCandidate
    implements InvoiceAwardIndependentRevisionStore {
  const InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(this._db);

  final Database _db;

  static const String table = 'invoice_award_revision_floor_candidate';
  static const String singletonId = 'v25b-isolated-floor';
  static const String candidateDdl =
      'CREATE TABLE invoice_award_revision_floor_candidate '
      '(id TEXT NOT NULL PRIMARY KEY, '
      'revision INTEGER NOT NULL CHECK (revision >= 0))';

  Future<bool> _hasExpectedShape(DatabaseExecutor executor) async {
    final schema = await executor.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[table],
    );
    if (schema.length != 1 || schema.single['sql'] != candidateDdl) {
      return false;
    }
    final attached = await executor.rawQuery(
      'SELECT type, name, sql FROM sqlite_master WHERE tbl_name = ? '
      "AND type IN ('index', 'trigger')",
      <Object>[table],
    );
    if (attached.length != 1) return false;
    final index = attached.single;
    return index['type'] == 'index' &&
        index['name'] ==
            'sqlite_autoindex_invoice_award_revision_floor_candidate_1' &&
        index['sql'] == null;
  }

  Future<int?> _readCandidate(DatabaseExecutor executor) async {
    if (!await _hasExpectedShape(executor)) return null;
    // An injected second row is malformed state, never a new authority.
    final rows = await executor.query(table, columns: const ['id', 'revision']);
    if (rows.length != 1 || rows.single['id'] != singletonId) return null;
    final revision = rows.single['revision'];
    return revision is int && revision >= 0 ? revision : null;
  }

  @override
  Future<int?> readFloor() async {
    // Closed or unavailable isolated custody is UNKNOWN, never authority.
    try {
      return await _readCandidate(_db);
    } catch (_) {
      return null;
    }
  }

  /// SQLite's conditional UPDATE under a real write transaction is the CAS
  /// linearization point, not an in-memory compare/SharedPreferences lock.
  /// Never bootstrap missing schema or missing floor on a read.
  @override
  Future<bool> compareAndAdvance(int expectedFloor, int nextFloor) async {
    if (expectedFloor < 0 || nextFloor <= expectedFloor) return false;
    try {
      return await _db.transaction<bool>((txn) async {
        if (await _readCandidate(txn) != expectedFloor) return false;
        final changed = await txn.rawUpdate(
        'UPDATE $table SET revision = ? '
        'WHERE id = ? AND revision = ?',
        <Object>[nextFloor, singletonId, expectedFloor],
      );
        return changed == 1;
      });
    } catch (_) {
      // A failed SQLite custody read/write cannot authorize advancement.
      return false;
    }
  }

  bool canActivateProduction() => false;
}
