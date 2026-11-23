import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Synthetic, in-memory protocol lab only. No network, account records,
/// production database, release authority or real signer.
class IsolatedTrustReceipt {
  const IsolatedTrustReceipt(this.payload, this.signature);
  final String payload;
  final String signature;
}

class IsolatedTrustRequest {
  const IsolatedTrustRequest({
    required this.namespace,
    required this.nonce,
    required this.idempotencyKey,
    required this.expectedRevision,
    required this.expiresAtEpochMs,
    required this.operation,
  });
  final String namespace;
  final String nonce;
  final String idempotencyKey;
  final int expectedRevision;
  final int expiresAtEpochMs;
  final String operation;

  String canonical() => jsonEncode(<String, Object>{
    'namespace': namespace,
    'nonce': nonce,
    'idempotencyKey': idempotencyKey,
    'expectedRevision': expectedRevision,
    'expiresAtEpochMs': expiresAtEpochMs,
    'operation': operation,
  });
}

/// Provider-neutral verifier: caller must verify the complete signed receipt,
/// not a boolean supplied by an untrusted response.
abstract class IsolatedTrustReceiptVerifier {
  Future<bool> verify(IsolatedTrustReceipt receipt);
}

/// A deterministic fake authority with a synthetic HMAC key. Never use this
/// key or this authority as production attestation or rollback protection.
class FakeIsolatedTrustService implements IsolatedTrustReceiptVerifier {
  FakeIsolatedTrustService(this._syntheticKey);
  final List<int> _syntheticKey;
  final Map<String, int> _revisions = <String, int>{};
  final Map<String, String> _pending = <String, String>{};
  final Map<String, IsolatedTrustReceipt> _committed =
      <String, IsolatedTrustReceipt>{};
  final Set<String> _nonces = <String>{};
  final Set<String> _revoked = <String>{};

  Future<String> _sign(String payload) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(payload), secretKey: SecretKey(_syntheticKey));
    return base64UrlEncode(mac.bytes);
  }

  @override
  Future<bool> verify(IsolatedTrustReceipt receipt) async {
    final expected = await _sign(receipt.payload);
    // Synthetic only: provider implementation must use vetted signature
    // verification and pinned authority keys.
    var difference = expected.length ^ receipt.signature.length;
    final a = utf8.encode(expected);
    final b = utf8.encode(receipt.signature);
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ (i < b.length ? b[i] : 0);
    }
    return difference == 0;
  }

  // A delimiter-joined key is ambiguous when either component contains ':';
  // use an unambiguous two-element JSON tuple for namespace-scoped indexes.
  static String _scopedKey(String namespace, String value) =>
      jsonEncode(<String>[namespace, value]);

  int revision(String namespace) => _revisions[namespace] ?? 0;

  /// Reservation is not authorization to mutate a local ledger.
  /// The fake uses an explicit clock to exercise expiry deterministically.
  Future<String?> reserve(IsolatedTrustRequest request, int nowEpochMs) async {
    if (request.namespace.trim().isEmpty ||
        request.nonce.trim().isEmpty ||
        request.idempotencyKey.trim().isEmpty ||
        request.expiresAtEpochMs <= nowEpochMs ||
        request.expectedRevision < 0 ||
        !<String>{'claim', 'restore', 'revoke'}.contains(request.operation)) {
      return null;
    }
    final key = _scopedKey(request.namespace, request.idempotencyKey);
    if (_committed.containsKey(key)) return null;
    if (_revoked.contains(request.namespace) && request.operation != 'revoke') {
      return null;
    }
    if (request.expectedRevision != revision(request.namespace)) return null;
    // A revoke must supersede an uncommitted claim/restore. A superseded
    // reservation is never a commit authority, including after retry.
    final pending = _pending[request.namespace];
    if (pending != null && request.operation != 'revoke') return null;
    final nonceKey = _scopedKey(request.namespace, request.nonce);
    if (_nonces.contains(nonceKey)) return null;
    _nonces.add(nonceKey);
    final reservation = request.canonical();
    _pending[request.namespace] = reservation;
    return reservation;
  }

  /// The reservation must be presented verbatim; stale/expired or replaced
  /// reservations fail closed. Revoke is terminal in this isolated lab.
  Future<IsolatedTrustReceipt?> commit(
      IsolatedTrustRequest request, String reservation, int nowEpochMs) async {
    if (request.expiresAtEpochMs <= nowEpochMs ||
        _pending[request.namespace] != reservation ||
        reservation != request.canonical() ||
        request.expectedRevision != revision(request.namespace)) {
      return null;
    }
    if (_revoked.contains(request.namespace) && request.operation != 'revoke') {
      return null;
    }
    final next = request.expectedRevision + 1;
    final payload = jsonEncode(<String, Object>{
      'authority': 'SYNTHETIC_TEST_ONLY',
      'namespace': request.namespace,
      'nonce': request.nonce,
      'idempotencyKey': request.idempotencyKey,
      'operation': request.operation,
      'revision': next,
    });
    final signature = await _sign(payload);
    // The asynchronous signer yields to competing commits. Recheck the
    // reservation and revision AFTER signing so only one caller can cross
    // the commit linearization point, including a concurrent revoke.
    if (_pending[request.namespace] != reservation ||
        request.expectedRevision != revision(request.namespace) ||
        (_revoked.contains(request.namespace) && request.operation != 'revoke') ||
        request.expiresAtEpochMs <= nowEpochMs) {
      return null;
    }
    final receipt = IsolatedTrustReceipt(payload, signature);
    _revisions[request.namespace] = next;
    if (request.operation == 'revoke') _revoked.add(request.namespace);
    _committed[_scopedKey(request.namespace, request.idempotencyKey)] = receipt;
    _pending.remove(request.namespace);
    return receipt;
  }

  /// Reconcile is read-only and returns only a committed signed receipt.
  /// Never infer success from a reservation or a network timeout.
  IsolatedTrustReceipt? reconcile(String namespace, String idempotencyKey) =>
      _committed[_scopedKey(namespace, idempotencyKey)];

  bool canActivateProduction() => false;
}
