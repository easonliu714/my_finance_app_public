import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_isolated_trust_protocol_lab.dart';

void main() {
  IsolatedTrustRequest request({
    String nonce = 'nonce-1',
    String key = 'operation-1',
    int revision = 0,
    int expiry = 2000,
    String operation = 'claim',
  }) => IsolatedTrustRequest(
    namespace: 'pseudonymous-device-account',
    nonce: nonce,
    idempotencyKey: key,
    expectedRevision: revision,
    expiresAtEpochMs: expiry,
    operation: operation,
  );

  test('synthetic reservation commits once and yields verifiable receipt', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 7));
    final first = request();
    final token = await service.reserve(first, 1000);
    expect(token, isNotNull);
    expect(service.reconcile(first.namespace, first.idempotencyKey), isNull);
    final receipt = await service.commit(first, token!, 1001);
    expect(receipt, isNotNull);
    expect(await service.verify(receipt!), isTrue);
    expect(service.revision(first.namespace), 1);
    expect(await service.commit(first, token, 1002), isNull);
    expect(service.reconcile(first.namespace, first.idempotencyKey), isNotNull);
    expect(service.canActivateProduction(), isFalse);
  });

  test('replay nonce, stale revision and expired reservation fail closed', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 8));
    final first = request();
    final token = (await service.reserve(first, 1000))!;
    expect(await service.reserve(request(nonce: 'nonce-1', key: 'other'), 1000), isNull);
    expect(await service.commit(first, token, 2000), isNull);
    expect(service.revision(first.namespace), 0);
    expect(service.reconcile(first.namespace, first.idempotencyKey), isNull);
    expect(await service.reserve(request(nonce: 'fresh', revision: 1), 1000), isNull);
  });

  test('revoke wins and prevents subsequent claim or restore', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 9));
    final revoke = request(operation: 'revoke');
    final token = (await service.reserve(revoke, 1000))!;
    expect(await service.commit(revoke, token, 1001), isNotNull);
    expect(await service.reserve(request(nonce: 'new', key: 'new',
        revision: 1), 1002), isNull);
    expect(await service.reserve(request(nonce: 'restore', key: 'restore',
        revision: 1, operation: 'restore'), 1002), isNull);
  });

  test('revoke preempts pending claim and stale claim cannot commit', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 11));
    final claim = request();
    final claimToken = (await service.reserve(claim, 1000))!;
    final revoke = request(nonce: 'revoke-nonce', key: 'revoke-key',
        operation: 'revoke');
    final revokeToken = await service.reserve(revoke, 1001);
    expect(revokeToken, isNotNull);
    expect(await service.commit(claim, claimToken, 1002), isNull);
    final receipt = await service.commit(revoke, revokeToken!, 1003);
    expect(receipt, isNotNull);
    expect(await service.verify(receipt!), isTrue);
    expect(service.revision(claim.namespace), 1);
    expect(await service.reserve(request(nonce: 'fresh', key: 'fresh',
        revision: 1), 1004), isNull);
  });

  test('blocked reservation does not burn nonce and can retry after expiry', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 12));
    final first = request();
    final firstToken = (await service.reserve(first, 1000))!;
    final blocked = request(nonce: 'retry-nonce', key: 'retry-key');
    expect(await service.reserve(blocked, 1001), isNull);
    expect(await service.commit(first, firstToken, 2000), isNull);
    // Expired pending reservations must be resolved explicitly, not silently
    // assumed committed; a terminal revoke can still supersede them.
    final revoke = request(nonce: 'revoke', key: 'revoke',
        operation: 'revoke', expiry: 3000);
    final revokeToken = await service.reserve(revoke, 2001);
    expect(revokeToken, isNotNull);
    expect(await service.commit(revoke, revokeToken!, 2002), isNotNull);
    expect(service.reconcile(blocked.namespace, blocked.idempotencyKey), isNull);
  });

  test('concurrent commits of one reservation produce exactly one receipt', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 13));
    final claim = request();
    final token = (await service.reserve(claim, 1000))!;
    final results = await Future.wait(<Future<IsolatedTrustReceipt?>>[
      service.commit(claim, token, 1001),
      service.commit(claim, token, 1001),
    ]);
    expect(results.where((receipt) => receipt != null).length, 1);
    expect(service.revision(claim.namespace), 1);
    expect(service.reconcile(claim.namespace, claim.idempotencyKey), isNotNull);
    expect(await service.commit(claim, token, 1002), isNull);
  });

  test('concurrent stale claim cannot produce a second signed receipt', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 14));
    final claim = request();
    final token = (await service.reserve(claim, 1000))!;
    final outcomes = await Future.wait(<Future<IsolatedTrustReceipt?>>[
      service.commit(claim, token, 1001),
      service.commit(claim, token, 1001),
      service.commit(claim, token, 1001),
    ]);
    expect(outcomes.where((receipt) => receipt != null).length, 1);
    expect(service.revision(claim.namespace), 1);
    expect(await service.reserve(request(nonce: 'stale', key: 'stale'), 1002), isNull);
  });

  test('delimiter collision cannot expose another namespace receipt', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 15));
    const first = IsolatedTrustRequest(
      namespace: 'device:account',
      nonce: 'first-nonce',
      idempotencyKey: 'claim',
      expectedRevision: 0,
      expiresAtEpochMs: 2000,
      operation: 'claim',
    );
    final token = (await service.reserve(first, 1000))!;
    final receipt = (await service.commit(first, token, 1001))!;
    expect(await service.verify(receipt), isTrue);
    expect(service.reconcile('device:account', 'claim'), same(receipt));
    // The old "namespace:key" index would return first's receipt here.
    expect(service.reconcile('device', 'account:claim'), isNull);
    expect(service.revision('device'), 0);
    expect(service.revision('device:account'), 1);
    expect(service.canActivateProduction(), isFalse);
  });

  test('namespace-scoped nonce tuples do not collide on delimiter', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 16));
    const first = IsolatedTrustRequest(
      namespace: 'device:account',
      nonce: 'challenge',
      idempotencyKey: 'operation-one',
      expectedRevision: 0,
      expiresAtEpochMs: 2000,
      operation: 'claim',
    );
    const second = IsolatedTrustRequest(
      namespace: 'device',
      nonce: 'account:challenge',
      idempotencyKey: 'operation-two',
      expectedRevision: 0,
      expiresAtEpochMs: 2000,
      operation: 'claim',
    );
    final firstToken = await service.reserve(first, 1000);
    final secondToken = await service.reserve(second, 1000);
    // Both are independent namespace challenges; old joined keys falsely
    // treated the second one as a replay of the first.
    expect(firstToken, isNotNull);
    expect(secondToken, isNotNull);
    expect(await service.commit(first, firstToken!, 1001), isNotNull);
    expect(await service.commit(second, secondToken!, 1001), isNotNull);
    expect(service.revision(first.namespace), 1);
    expect(service.revision(second.namespace), 1);
    expect(service.reconcile(first.namespace, first.idempotencyKey), isNotNull);
    expect(service.reconcile(second.namespace, second.idempotencyKey), isNotNull);
    expect(
      await service.reserve(
        IsolatedTrustRequest(
          namespace: second.namespace,
          nonce: second.nonce,
          idempotencyKey: 'new-operation',
          expectedRevision: 1,
          expiresAtEpochMs: 3000,
          operation: 'claim',
        ),
        1002,
      ),
      isNull,
    );
  });

  test('altered receipt signature is rejected', () async {
    final service = FakeIsolatedTrustService(List<int>.filled(32, 10));
    final first = request();
    final token = (await service.reserve(first, 1000))!;
    final receipt = (await service.commit(first, token, 1001))!;
    expect(await service.verify(IsolatedTrustReceipt(
      receipt.payload.replaceFirst('claim', 'restore'), receipt.signature)), isFalse);
  });
}
