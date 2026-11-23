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
      "SELECT sql FROM main.sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[table],
    );
    if (schema.length != 1 || schema.single['sql'] != candidateDdl) {
      return false;
    }
    final attached = await executor.rawQuery(
      'SELECT type, name, sql FROM main.sqlite_master WHERE tbl_name = ? '
      "AND type IN ('index', 'trigger')",
      <Object>[table],
    );
    if (attached.length != 1) return false;
    // SQLite stores a TEMP trigger on main.$table in temp.sqlite_master,
    // outside main.sqlite_master. Reject it before any candidate floor read
    // or CAS: a hidden trigger could mutate other tables on floor advance.
    final tempTriggers = await executor.rawQuery(
      'SELECT name FROM temp.sqlite_master '
      "WHERE type = 'trigger' AND tbl_name = ?",
      <Object>[table],
    );
    if (tempTriggers.isNotEmpty) return false;
    final index = attached.single;
    return index['type'] == 'index' &&
        index['name'] ==
            'sqlite_autoindex_invoice_award_revision_floor_candidate_1' &&
        index['sql'] == null;
  }

  Future<int?> _readCandidate(DatabaseExecutor executor) async {
    if (!await _hasExpectedShape(executor)) return null;
    // An injected second row is malformed state, never a new authority.
    // Qualify the authority table: TEMP tables can shadow an unqualified name.
    final rows = await executor.rawQuery('SELECT id, revision FROM main.$table');
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
        'UPDATE main.$table SET revision = ? '
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

  /// V25-L: isolated laboratory experiment only. A read/recheck pair cannot
  /// fence an independent claim/revoke between the last read and ledger commit.
  /// Hold an exclusive SQLite transaction on the SAME floor file throughout a
  /// disposable full-restore callback. Cooperating floor CAS writers cannot
  /// advance until that callback has committed or rolled back.
  ///
  /// This is neither anti-rollback custody nor independent authentication,
  /// and cannot authorize production restore, consent or posting. The callback
  /// MUST NOT call this same Database outside [txn] (sqflite deadlock).
  Future<T> runIsolatedRestoreUnderFloorFence<T>({
    required int restoredRevision,
    required Future<T> Function() restoreAction,
  }) async {
    if (restoredRevision < 0) {
      throw StateError('ISOLATED_RESTORE_REVISION_INVALID');
    }
    return _db.transaction<T>((txn) async {
      if (await _readCandidate(txn) != restoredRevision) {
        throw StateError('ISOLATED_RESTORE_FLOOR_STALE_HOLD');
      }
      final result = await restoreAction();
      // Even our test-only exclusive transaction must not silently accept a
      // malformed or missing authority table after the ledger action.
      if (await _readCandidate(txn) != restoredRevision) {
        throw StateError('ISOLATED_RESTORE_FLOOR_CHANGED_HOLD');
      }
      return result;
    }, exclusive: true);
  }

  bool canActivateProduction() => false;
}
