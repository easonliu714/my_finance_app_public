import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_trust_protocol_lab.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_trust_receipt_disk_journal.dart';

void main() {
  const request = IsolatedTrustRequest(
    namespace: 'synthetic-pseudonym',
    nonce: 'nonce-a',
    idempotencyKey: 'operation-a',
    expectedRevision: 0,
    expiresAtEpochMs: 2000,
    operation: 'claim',
  );

  test('lost reply: verified receipt survives journal instance restart', () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-trust-');
    try {
      final authority = FakeIsolatedTrustService(List<int>.filled(32, 31));
      final reservation = (await authority.reserve(request, 1000))!;
      final receipt = (await authority.commit(request, reservation, 1001))!;
      final first = IsolatedTrustReceiptDiskJournal(dir, authority);
      expect(await first.record(request, receipt), isTrue);
      final restarted = IsolatedTrustReceiptDiskJournal(dir, authority);
      final recovered = await restarted.recover(request);
      expect(recovered, isNotNull);
      expect(recovered!.signature, receipt.signature);
      expect(await restarted.record(request, receipt), isTrue);
      expect(restarted.canActivateProduction(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('missing, forged, and cross-namespace receipt fail closed', () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-trust-');
    try {
      final authority = FakeIsolatedTrustService(List<int>.filled(32, 32));
      final journal = IsolatedTrustReceiptDiskJournal(dir, authority);
      expect(await journal.recover(request), isNull);
      final reservation = (await authority.reserve(request, 1000))!;
      final receipt = (await authority.commit(request, reservation, 1001))!;
      const other = IsolatedTrustRequest(
        namespace: 'other-pseudonym',
        nonce: 'nonce-a',
        idempotencyKey: 'operation-a',
        expectedRevision: 0,
        expiresAtEpochMs: 2000,
        operation: 'claim',
      );
      expect(await journal.record(other, receipt), isFalse);
      expect(await journal.record(request,
          IsolatedTrustReceipt(receipt.payload, 'forged')), isFalse);
      expect(await journal.record(request, receipt), isTrue);
      expect(await journal.recover(other), isNull);
      final files = await dir.list().where((item) => item.path.endsWith('.json')).toList();
      expect(files.length, 1);
      await File(files.single.path).writeAsString('corrupt', flush: true);
      expect(await journal.recover(request), isNull);
      expect(await journal.record(request, receipt), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('lost remote reply reconciles authoritative commit into empty cache',
      () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-trust-');
    try {
      final authority = FakeIsolatedTrustService(List<int>.filled(32, 33));
      final token = (await authority.reserve(request, 1000))!;
      final committed = (await authority.commit(request, token, 1001))!;
      final journal = IsolatedTrustReceiptDiskJournal(dir, authority);
      expect(await journal.recover(request), isNull);
      final reconciled = await journal.reconcileLostReply(request);
      expect(reconciled?.signature, committed.signature);
      expect((await journal.recover(request))?.signature, committed.signature);
      expect((await IsolatedTrustReceiptDiskJournal(dir, authority)
          .reconcileLostReply(request))?.signature, committed.signature);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('pending, stale after revoke, and forged cache fail closed',
      () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-trust-');
    try {
      final authority = FakeIsolatedTrustService(List<int>.filled(32, 34));
      final journal = IsolatedTrustReceiptDiskJournal(dir, authority);
      final token = (await authority.reserve(request, 1000))!;
      expect(await journal.reconcileLostReply(request), isNull);
      final receipt = (await authority.commit(request, token, 1001))!;
      expect(await journal.record(request, receipt), isTrue);
      const revoke = IsolatedTrustRequest(
        namespace: 'synthetic-pseudonym',
        nonce: 'nonce-revoke',
        idempotencyKey: 'operation-revoke',
        expectedRevision: 1,
        expiresAtEpochMs: 3000,
        operation: 'revoke',
      );
      final revokeToken = (await authority.reserve(revoke, 1002))!;
      expect(await authority.commit(revoke, revokeToken, 1003), isNotNull);
      // The old receipt still has a valid MAC and is on disk, but cannot
      // authorize a claim after a terminal revoke.
      expect(await journal.recover(request), isNotNull);
      expect(await journal.reconcileLostReply(request), isNull);
      expect(await journal.reconcileLostReply(revoke), isNotNull);
      expect(await journal.reconcileLostReply(
        const IsolatedTrustRequest(
          namespace: 'other-pseudonym',
          nonce: 'nonce-a',
          idempotencyKey: 'operation-a',
          expectedRevision: 0,
          expiresAtEpochMs: 2000,
          operation: 'claim',
        )), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
