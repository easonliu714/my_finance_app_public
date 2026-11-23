import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:my_finance_app/features/invoice/invoice_award_restore_floor_readback.dart';
import 'package:my_finance_app/features/invoice/invoice_award_revision_floor_custody.dart';
import 'package:my_finance_app/features/invoice/invoice_award_sqlite_revision_floor_candidate.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Synthetic metadata exists ONLY in these isolated tests. It is not part
/// of Scope9 backup format or independently authenticated production custody.
const _isolatedRevisionKey = 'v25i_isolated_restored_revision';

class _IsolatedBoundaryRestore extends FullRestoreService {
  const _IsolatedBoundaryRestore({
    required this.floorStore,
    required this.independentlyAttested,
  });

  final InvoiceAwardIndependentRevisionStore? floorStore;
  final bool independentlyAttested;

  @override
  Future<Future<void> Function()?> prepareRestoreCommitCheck(
    Map<String, Object?> envelope,
  ) async {
    final metadata = envelope['metadata'];
    final revision = metadata is Map<String, Object?>
        ? metadata[_isolatedRevisionKey]
        : null;
    // Capture the same revision for both checks. An intervening mutation of
    // the caller's envelope must not refresh the original authorization.
    final capturedRevision = revision is int ? revision : null;
    Future<void> check() async {
      final accepted = await const InvoiceAwardRestoreFloorReadback()
          .isCandidateCurrent(
        store: floorStore,
        independentlyAuthenticated: independentlyAttested,
        restoredRevision: capturedRevision,
      );
      if (!accepted) {
        throw const FullRestoreException(
          '隔離測試：發票中獎版本權威失效，已取消還原交易',
        );
      }
    }

    await check();
    return check;
  }
}

// Advance a separate on-disk authority after the real destructive writes.
// No production ledger or trust provider is used by this test subclass.
class _AdvancingFloorRestore extends _IsolatedBoundaryRestore {
  const _AdvancingFloorRestore({
    required InvoiceAwardIndependentRevisionStore floorStore,
  }) : super(floorStore: floorStore, independentlyAttested: true);

  @override
  Future<void> afterManagedRestoreTransaction(DatabaseExecutor txn) async {
    final store = floorStore!;
    expect(await store.compareAndAdvance(80, 81), isTrue);
  }
}

// V25-L: block a REAL disposable ledger restore transaction while a
// separate SQLite floor connection attempts a competing revision CAS.
class _PausedManagedRestore extends FullRestoreService {
  _PausedManagedRestore(this.entered, this.release);
  final Completer<void> entered;
  final Future<void> release;

  @override
  Future<void> beforeManagedRestoreTransaction(DatabaseExecutor txn) async {
    entered.complete();
    await release;
  }
}

// V25-J negative witness: a hook is not allowed to modify managed rows and
// then rely on the pre-hook snapshot check to authorize destructive restore.
class _MutatingBoundaryRestore extends FullRestoreService {
  const _MutatingBoundaryRestore();

  @override
  Future<void> beforeDestructiveRestoreTransaction(
    DatabaseExecutor txn,
    Map<String, Object?> envelope,
  ) async {
    await txn.rawUpdate(
      'UPDATE accounts SET name = ? WHERE id = ?',
      <Object>['hook-tampered', 'account-1'],
    );
  }
}

class _RealDiskRestoreFixture {
  _RealDiskRestoreFixture(this.source, this.target, this.floor, this.envelope);

  final Database source;
  final Database target;
  final Database floor;
  final Map<String, Object?> envelope;

  InvoiceAwardIndependentRevisionStore get floorStore =>
      InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(floor);

  void setRestoredRevision(int? revision) {
    final metadata = envelope['metadata']! as Map<String, Object?>;
    if (revision == null) {
      metadata.remove(_isolatedRevisionKey);
    } else {
      metadata[_isolatedRevisionKey] = revision;
    }
  }
}

Future<_RealDiskRestoreFixture> _newFixture() async {
  final directory = await Directory.systemTemp.createTemp('v25i_restore_');
  final source = await openDatabase(
    p.join(directory.path, 'source-ledger.sqlite'),
    singleInstance: false,
  );
  final target = await openDatabase(
    p.join(directory.path, 'target-ledger.sqlite'),
    singleInstance: false,
  );
  final floor = await openDatabase(
    p.join(directory.path, 'independent-floor.sqlite'),
    singleInstance: false,
  );
  addTearDown(() async {
    await source.close();
    await target.close();
    await floor.close();
    await directory.delete(recursive: true);
  });

  for (final ledger in <Database>[source, target]) {
    await ledger.execute(
      'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await ledger.execute(
      'CREATE TABLE transactions (id TEXT PRIMARY KEY, amount INTEGER NOT NULL)',
    );
  }
  await source.insert('accounts', <String, Object>{
    'id': 'account-1',
    'name': 'source',
  });
  await source.insert('transactions', <String, Object>{
    'id': 'ledger-1',
    'amount': 200,
  });
  await target.insert('accounts', <String, Object>{
    'id': 'account-1',
    'name': 'preserved',
  });
  await target.insert('transactions', <String, Object>{
    'id': 'ledger-1',
    'amount': 300,
  });

  await floor.execute(InvoiceAwardSqliteRevisionFloorCandidate.candidateDdl);
  await floor.insert(
    InvoiceAwardSqliteRevisionFloorCandidate.table,
    <String, Object>{
      'id': InvoiceAwardSqliteRevisionFloorCandidate.singletonId,
      'revision': 80,
    },
  );
  final envelope = await const FullBackupService().buildFullBackupEnvelope(
    source,
    sourcePlatform: 'isolated',
  );
  return _RealDiskRestoreFixture(source, target, floor, envelope);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('V25-J hook mutation fails closed and rolls back real SQLite rows',
      () async {
    final fixture = await _newFixture();
    await expectLater(
      const _MutatingBoundaryRestore().restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect((await fixture.target.query('accounts')).single['name'],
        'preserved');
    expect((await fixture.target.query('transactions')).single['amount'],
        300);
    expect(
      await fixture.target.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: <Object>['table', 'expense_categories'],
      ),
      isEmpty,
    );
  });

  test('V25-I stale disk floor blocks REAL restore before DDL or DML',
      () async {
    final fixture = await _newFixture();
    fixture.setRestoredRevision(79);
    await expectLater(
      _IsolatedBoundaryRestore(
        floorStore: fixture.floorStore,
        independentlyAttested: true,
      ).restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect((await fixture.target.query('accounts')).single['name'],
        'preserved');
    expect((await fixture.target.query('transactions')).single['amount'],
        300);
    // The boundary runs before the lazily created category table and any
    // trigger removal. A declined restore must not mutate even schema.
    expect(
      await fixture.target.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: <Object>['table', 'expense_categories'],
      ),
      isEmpty,
    );
    expect(await fixture.floorStore.readFloor(), 80);
  });

  test('V25-I missing authority, missing revision and unauthenticated '
      'floor never replace real SQLite ledger', () async {
    final fixture = await _newFixture();
    fixture.setRestoredRevision(80);
    for (final candidate in <_IsolatedBoundaryRestore>[
      const _IsolatedBoundaryRestore(
        floorStore: null,
        independentlyAttested: true,
      ),
      _IsolatedBoundaryRestore(
        floorStore: fixture.floorStore,
        independentlyAttested: false,
      ),
    ]) {
      await expectLater(
        candidate.restoreFromEnvelope(
          fixture.target,
          fixture.envelope,
          confirmationText: FullRestoreService.destructiveConfirmationText,
        ),
        throwsA(isA<FullRestoreException>()),
      );
    }
    fixture.setRestoredRevision(null);
    await expectLater(
      _IsolatedBoundaryRestore(
        floorStore: fixture.floorStore,
        independentlyAttested: true,
      ).restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect((await fixture.target.query('accounts')).single['name'],
        'preserved');
    expect((await fixture.target.query('transactions')).single['amount'],
        300);
  });

  test('V25-I independent floor advance invalidates old restore', () async {
    final fixture = await _newFixture();
    fixture.setRestoredRevision(80);
    expect(
      await fixture.floorStore.compareAndAdvance(80, 81),
      isTrue,
    );
    await expectLater(
      _IsolatedBoundaryRestore(
        floorStore: fixture.floorStore,
        independentlyAttested: true,
      ).restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect(await fixture.floorStore.readFloor(), 81);
    expect((await fixture.target.query('transactions')).single['amount'],
        300);
  });

  test('V25-H2 floor advances during REAL restore; rollback rows and DDL',
      () async {
    final fixture = await _newFixture();
    fixture.setRestoredRevision(80);
    await expectLater(
      _AdvancingFloorRestore(floorStore: fixture.floorStore)
          .restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    // The independent floor advanced, but the main restore transaction
    // cannot commit data or lazy schema under the stale revision.
    expect(await fixture.floorStore.readFloor(), 81);
    expect((await fixture.target.query('accounts')).single['name'],
        'preserved');
    expect((await fixture.target.query('transactions')).single['amount'],
        300);
    expect(
      await fixture.target.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: <Object>['table', 'expense_categories'],
      ),
      isEmpty,
    );
    // The old revision is now stale; current revision still works in the
    // disposable same-source fixture, without rewriting the external floor.
    fixture.setRestoredRevision(81);
    final result = await _IsolatedBoundaryRestore(
      floorStore: fixture.floorStore,
      independentlyAttested: true,
    ).restoreFromEnvelope(
      fixture.target,
      fixture.envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect(result.audit.passed, isTrue);
    expect((await fixture.target.query('transactions')).single['amount'], 200);
    expect(await fixture.floorStore.readFloor(), 81);
  });

  test('V25-I equal isolated floor permits REAL test-only restore, '
      'never production activation', () async {
    final fixture = await _newFixture();
    fixture.setRestoredRevision(80);
    final result = await _IsolatedBoundaryRestore(
      floorStore: fixture.floorStore,
      independentlyAttested: true,
    ).restoreFromEnvelope(
      fixture.target,
      fixture.envelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect(result.audit.passed, isTrue);
    expect((await fixture.target.query('accounts')).single['name'],
        'source');
    expect((await fixture.target.query('transactions')).single['amount'],
        200);
    expect(await fixture.floorStore.readFloor(), 80);
    expect(
      InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(fixture.floor)
          .canActivateProduction(),
      isFalse,
    );
  });
  test('V25-L floor-exclusive lease fences REAL restore vs competing CAS',
      () async {
    final fixture = await _newFixture();
    final peer = await openDatabase(fixture.floor.path, singleInstance: false);
    addTearDown(peer.close);
    // A blocked independent connection must fail closed promptly, not make
    // the test pass after the restore has already released its floor lock.
    await peer.execute('PRAGMA busy_timeout = 0');
    final gate = InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(
      fixture.floor,
    );
    final competitor = InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(
      peer,
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final pendingRestore = gate.runIsolatedRestoreUnderFloorFence(
      restoredRevision: 80,
      restoreAction: () => _PausedManagedRestore(
        entered,
        release.future,
      ).restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
    );
    await entered.future;
    try {
      // Two different database handles to one on-disk floor: CAS must NOT
      // advance during a real SQLite ledger restore transaction.
      expect(await competitor.compareAndAdvance(80, 81), isFalse);
    } finally {
      release.complete();
    }
    final result = await pendingRestore;
    expect(result.audit.passed, isTrue);
    expect((await fixture.target.query('transactions')).single['amount'], 200);
    expect(await gate.readFloor(), 80);
    // After the ledger commit the competing CAS can acquire its real lock.
    expect(await competitor.compareAndAdvance(80, 81), isTrue);
    expect(await gate.readFloor(), 81);
    expect(gate.canActivateProduction(), isFalse);
  });

  test('V25-L stale floor refuses REAL restore before destructive entry',
      () async {
    final fixture = await _newFixture();
    final gate = InvoiceAwardSqliteRevisionFloorCandidate.forIsolatedTest(
      fixture.floor,
    );
    var entered = false;
    await expectLater(
      gate.runIsolatedRestoreUnderFloorFence(
        restoredRevision: 79,
        restoreAction: () async {
          entered = true;
          return const FullRestoreService().restoreFromEnvelope(
            fixture.target,
            fixture.envelope,
            confirmationText: FullRestoreService.destructiveConfirmationText,
          );
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(entered, isFalse);
    expect((await fixture.target.query('accounts')).single['name'], 'preserved');
    expect((await fixture.target.query('transactions')).single['amount'], 300);
    expect(await gate.readFloor(), 80);
  });

  test('V25-K closed independent SQLite custody fails closed on read and CAS',
      () async {
    final fixture = await _newFixture();
    final custody = fixture.floorStore;
    await fixture.floor.close();
    expect(await custody.readFloor(), isNull);
    expect(await custody.compareAndAdvance(80, 81), isFalse);
    fixture.setRestoredRevision(80);
    await expectLater(
      _IsolatedBoundaryRestore(
        floorStore: custody,
        independentlyAttested: true,
      ).restoreFromEnvelope(
        fixture.target,
        fixture.envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
      ),
      throwsA(isA<FullRestoreException>()),
    );
    expect((await fixture.target.query('transactions')).single['amount'], 300);
  });
}
