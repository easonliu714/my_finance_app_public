import 'dart:convert';
import 'dart:io';

import 'invoice_award_isolated_trust_protocol_lab.dart';

/// Synthetic replay-only authority checkpoint. Not an external trust root:
/// deletion/rollback of this file cannot be detected without a remote anchor.
/// Only completed operations are replayed; pending operations fail closed.
class IsolatedTrustAuthorityReplayLab {
  IsolatedTrustAuthorityReplayLab(this.file, this.syntheticKey);

  final File file;
  final List<int> syntheticKey;
  FakeIsolatedTrustService? _authority;
  bool _invalid = false;

  FakeIsolatedTrustService? get authority => _invalid ? null : _authority;

  Future<bool> recover() async {
    _authority = null;
    _invalid = true;
    if (!await file.exists()) {
      // A missing checkpoint is unknown, never a new empty authority.
      return false;
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return false;
      final replay = FakeIsolatedTrustService(syntheticKey);
      for (final event in raw) {
        if (event is! Map<String, dynamic>) return false;
        final canonical = event['request'];
        final signature = event['signature'];
        final payload = event['payload'];
        final committedAt = event['committedAt'];
        if (canonical is! String || signature is! String ||
            payload is! String || committedAt is! int) {
          return false;
        }
        final data = jsonDecode(canonical);
        if (data is! Map<String, dynamic>) return false;
        final request = IsolatedTrustRequest(
          namespace: data['namespace'] as String,
          nonce: data['nonce'] as String,
          idempotencyKey: data['idempotencyKey'] as String,
          expectedRevision: data['expectedRevision'] as int,
          expiresAtEpochMs: data['expiresAtEpochMs'] as int,
          operation: data['operation'] as String,
        );
        if (request.canonical() != canonical) return false;
        final token = await replay.reserve(request, committedAt);
        if (token == null) return false;
        final receipt = await replay.commit(request, token, committedAt);
        if (receipt == null || receipt.payload != payload ||
            receipt.signature != signature ||
            !await replay.verifyBoundReceipt(receipt, request)) {
          return false;
        }
      }
      _authority = replay;
      _invalid = false;
      return true;
    } on FormatException {
      return false;
    } on FileSystemException {
      return false;
    } on TypeError {
      return false;
    }
  }

  /// A synthetic fixture creator; NEVER use as an automatic recovery fallback.
  Future<bool> initializeEmptyFixture() async {
    if (await file.exists()) return false;
    await file.parent.create(recursive: true);
    await file.writeAsString('[]', flush: true);
    return recover();
  }

  /// Replays only fully signed commits. A crash before checkpoint publication
  /// remains UNKNOWN and must be reconciled with a real remote authority.
  Future<IsolatedTrustReceipt?> commit(
      IsolatedTrustRequest request, int nowEpochMs) async {
    if (!await recover()) return null;
    final lock = File('${file.path}.lock');
    final handle = await lock.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    try {
      // Refresh under the cross-process lock; no stale in-memory writer.
      if (!await recover()) return null;
      final current = _authority!;
      final token = await current.reserve(request, nowEpochMs);
      if (token == null) return null;
      final receipt = await current.commit(request, token, nowEpochMs);
      if (receipt == null) return null;
      final events = jsonDecode(await file.readAsString()) as List<dynamic>;
      events.add(<String, Object>{
        'request': request.canonical(),
        'payload': receipt.payload,
        'signature': receipt.signature,
        'committedAt': nowEpochMs,
      });
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(events), flush: true);
      await temp.rename(file.path);
      return receipt;
    } on FileSystemException {
      _invalid = true;
      return null;
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }

  IsolatedTrustReceipt? reconcileCurrent(IsolatedTrustRequest request) =>
      authority?.reconcileCurrent(request);

  bool canActivateProduction() => false;
}
