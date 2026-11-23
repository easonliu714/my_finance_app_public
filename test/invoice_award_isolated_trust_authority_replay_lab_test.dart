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
}
