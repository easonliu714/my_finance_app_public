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
}
