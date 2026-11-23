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
}
