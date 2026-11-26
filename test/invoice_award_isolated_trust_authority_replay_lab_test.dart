import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_trust_protocol_lab.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_trust_authority_replay_lab.dart';

void main() {
  const claim = IsolatedTrustRequest(
    namespace: 'synthetic-account', nonce: 'nonce-a',
    idempotencyKey: 'claim-a', expectedRevision: 0,
    expiresAtEpochMs: 3000, operation: 'claim',
  );
  const revoke = IsolatedTrustRequest(
    namespace: 'synthetic-account', nonce: 'nonce-b',
    idempotencyKey: 'revoke-b', expectedRevision: 1,
    expiresAtEpochMs: 3000, operation: 'revoke',
  );

  test('synthetic authority replay restores commit and lost-reply receipt',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-replay-');
    try {
      final file = File('${dir.path}/authority.json');
      final first = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 44));
      expect(await first.initializeEmptyFixture(), isTrue);
      final receipt = await first.commit(claim, 1000);
      expect(receipt, isNotNull);
      final restarted = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 44));
      expect(await restarted.recover(), isTrue);
      expect(restarted.reconcileCurrent(claim)?.signature, receipt!.signature);
      expect(await restarted.commit(claim, 1001), isNull);
      expect(restarted.canActivateProduction(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('revoke survives restart and old claim fails current reconciliation',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-replay-');
    try {
      final file = File('${dir.path}/authority.json');
      final first = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 45));
      expect(await first.initializeEmptyFixture(), isTrue);
      expect(await first.commit(claim, 1000), isNotNull);
      expect(await first.commit(revoke, 1001), isNotNull);
      final restarted = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 45));
      expect(await restarted.recover(), isTrue);
      expect(restarted.reconcileCurrent(claim), isNull);
      expect(restarted.reconcileCurrent(revoke), isNotNull);
      expect(await restarted.commit(claim, 1002), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('replay rejects tampered timestamp while preserving valid signed receipt',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-replay-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 48);
      final writer = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await writer.initializeEmptyFixture(), isTrue);
      final receipt = await writer.commit(claim, 1000);
      expect(receipt, isNotNull);
      final valid = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await valid.recover(), isTrue);
      expect(valid.reconcileCurrent(claim)?.signature, receipt!.signature);
      final events = jsonDecode(await file.readAsString()) as List<dynamic>;
      (events.first as Map<String, dynamic>)['committedAt'] = 'not-an-int';
      await file.writeAsString(jsonEncode(events), flush: true);
      final corrupted = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await corrupted.recover(), isFalse);
      expect(corrupted.reconcileCurrent(claim), isNull);
      expect(await corrupted.commit(revoke, 1001), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('corrupt checkpoint and wrong key fail closed, no silent reset',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-replay-');
    try {
      final file = File('${dir.path}/authority.json');
      final first = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 46));
      expect(await first.recover(), isFalse);
      expect(await first.initializeEmptyFixture(), isTrue);
      expect(await first.commit(claim, 1000), isNotNull);
      final wrongKey = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 47));
      expect(await wrongKey.recover(), isFalse);
      expect(await wrongKey.commit(revoke, 1001), isNull);
      await file.writeAsString('corrupt', flush: true);
      final restarted = IsolatedTrustAuthorityReplayLab(file, List<int>.filled(32, 46));
      expect(await restarted.recover(), isFalse);
      expect(await restarted.commit(revoke, 1001), isNull);
      expect(await restarted.initializeEmptyFixture(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('concurrent synthetic initializers elect exactly one creator', () async {
    final dir = await Directory.systemTemp.createTemp('authority-init-race-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 51);
      final creators = List.generate(
        12, (_) => IsolatedTrustAuthorityReplayLab(file, key),
      );
      final results = await Future.wait(
        creators.map((creator) => creator.initializeEmptyFixture()),
      );
      expect(results.where((result) => result).length, 1);
      final writer = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await writer.commit(claim, 1000), isNotNull);
      final restarted = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await restarted.recover(), isTrue);
      expect(restarted.reconcileCurrent(claim), isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('reinitialization cannot erase committed or revoked authority', () async {
    final dir = await Directory.systemTemp.createTemp('authority-init-race-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 52);
      final writer = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await writer.initializeEmptyFixture(), isTrue);
      expect(await writer.commit(claim, 1000), isNotNull);
      expect(await writer.commit(revoke, 1001), isNotNull);
      final attempts = await Future.wait(List.generate(
        12, (_) => IsolatedTrustAuthorityReplayLab(file, key)
            .initializeEmptyFixture(),
      ));
      expect(attempts, everyElement(isFalse));
      final restarted = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await restarted.recover(), isTrue);
      expect(restarted.reconcileCurrent(claim), isNull);
      expect(restarted.reconcileCurrent(revoke), isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('fixture recovery completes before exclusive lock release', () async {
    final dir = await Directory.systemTemp.createTemp('authority-lock-life-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 53);
      final events = <String>[];
      final lab = _RecoveryProbeLab(file, key, events);
      final initialization = lab.initializeEmptyFixture();
      await lab.entered.future;
      expect(events, ['lock']);
      lab.proceed.complete();
      expect(await initialization, isTrue);
      expect(events, ['lock', 'recover', 'unlock', 'close']);
      expect(lab.authority, isNotNull);
      final writer = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await writer.commit(claim, 1000), isNotNull);
      expect(writer.reconcileCurrent(claim), isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('recovery I/O failure invalidates authority and releases fixture lock',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-lock-fail-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 54);
      final events = <String>[];
      final lab = _RecoveryProbeLab(file, key, events, failRecovery: true);
      final initialization = lab.initializeEmptyFixture();
      await lab.entered.future;
      expect(events, ['lock']);
      lab.proceed.complete();
      expect(await initialization, isFalse);
      expect(events, ['lock', 'recover', 'unlock', 'close']);
      expect(lab.authority, isNull);
      expect(lab.reconcileCurrent(claim), isNull);
      // Recovery failed after publication; do not reset the checkpoint.
      expect(await file.readAsString(), '[]');
      final retry = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await retry.initializeEmptyFixture(), isFalse);
      expect(await retry.commit(claim, 1000), isNotNull);
      expect(await retry.commit(revoke, 1001), isNotNull);
      expect(retry.reconcileCurrent(claim), isNull);
      expect(retry.reconcileCurrent(revoke), isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('lock acquisition failure closes handle and permits legal retry',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-lock-deny-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 55);
      final events = <String>[];
      final lab = IsolatedTrustAuthorityReplayLab(
        file, key,
        fixtureLockOpener: (lock) async => _TrackingFixtureLock(
          await lock.open(mode: FileMode.append), events, failLock: true,
        ),
      );
      expect(await lab.initializeEmptyFixture(), isFalse);
      expect(events, ['lock', 'close']);
      expect(lab.authority, isNull);
      expect(await file.exists(), isFalse);
      final retry = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await retry.initializeEmptyFixture(), isTrue);
      expect(await retry.commit(claim, 1000), isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('lock open I/O failure stays closed without publishing checkpoint',
      () async {
    final dir = await Directory.systemTemp.createTemp('authority-open-deny-');
    try {
      final file = File('${dir.path}/authority.json');
      final key = List<int>.filled(32, 56);
      final lockDirectory = Directory('${file.path}.lock');
      await lockDirectory.create();
      final lab = IsolatedTrustAuthorityReplayLab(file, key);
      expect(await lab.initializeEmptyFixture(), isFalse);
      expect(lab.authority, isNull);
      expect(await file.exists(), isFalse);
      await lockDirectory.delete();
      expect(await lab.initializeEmptyFixture(), isTrue);
      expect(await lab.commit(claim, 1000), isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}


// Real file handle with deterministic lifecycle observations; no remote trust.
class _TrackingFixtureLock implements RandomAccessFile {
  _TrackingFixtureLock(this.delegate, this.events, {this.failLock = false});

  final RandomAccessFile delegate;
  final List<String> events;
  final bool failLock;

  @override
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive, int start = 0, int end = -1,
  ]) async {
    events.add('lock');
    if (failLock) {
      throw const FileSystemException('synthetic lock acquisition failure');
    }
    await delegate.lock(mode, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) async {
    events.add('unlock');
    await delegate.unlock(start, end);
    return this;
  }

  @override
  Future<void> close() async {
    events.add('close');
    await delegate.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryProbeLab extends IsolatedTrustAuthorityReplayLab {
  // Forward the fixture file and key without changing lock-test behavior.
  _RecoveryProbeLab(super.file, super.syntheticKey, this.events,
      {this.failRecovery = false})
      : super(fixtureLockOpener: (lock) async =>
            _TrackingFixtureLock(await lock.open(mode: FileMode.append), events));

  final List<String> events;
  final bool failRecovery;
  final entered = Completer<void>();
  final proceed = Completer<void>();

  @override
  Future<bool> recover() async {
    entered.complete();
    await proceed.future;
    final recovered = await super.recover();
    events.add('recover');
    if (failRecovery) {
      throw const FileSystemException('synthetic recovery failure');
    }
    return recovered;
  }
}
