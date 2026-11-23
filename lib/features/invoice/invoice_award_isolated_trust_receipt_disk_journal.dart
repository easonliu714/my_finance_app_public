import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'invoice_award_isolated_trust_protocol_lab.dart';

/// Disposable synthetic receipt cache. Not a remote authority or a
/// production rollback floor. A missing cache entry is NEVER authorization.
class IsolatedTrustReceiptDiskJournal {
  IsolatedTrustReceiptDiskJournal(this.directory, this.verifier);
  final Directory directory;
  final FakeIsolatedTrustService verifier;

  Future<File> _entry(String namespace, String idempotencyKey) async {
    final digest = await Sha256().hash(utf8.encode(
      jsonEncode(<String>[namespace, idempotencyKey])));
    final name = base64UrlEncode(digest.bytes).replaceAll('=', '');
    return File('${directory.path}/$name.json');
  }

  /// Persist only a verified committed receipt. Rename avoids exposing a
  /// partially written JSON file; no crash-durability/fsync guarantee is made.
  Future<bool> record(IsolatedTrustRequest request,
      IsolatedTrustReceipt receipt) async {
    if (!await verifier.verifyBoundReceipt(receipt, request)) return false;
    await directory.create(recursive: true);
    final file = await _entry(request.namespace, request.idempotencyKey);
    final lock = File('${directory.path}/.journal.lock');
    final handle = await lock.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    try {
      if (await file.exists()) {
        final existing = await recover(request);
        // Fail closed on corrupt/conflicting entries, never overwrite them.
        return existing != null &&
            existing.payload == receipt.payload &&
            existing.signature == receipt.signature;
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(<String, String>{
        'payload': receipt.payload,
        'signature': receipt.signature,
      }), flush: true);
      await temp.rename(file.path);
      return true;
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }

  /// On restart, treat absent/corrupt/wrong-namespace receipts as unknown.
  /// Caller must reconcile with the external authority, never infer commit.
  Future<IsolatedTrustReceipt?> recover(IsolatedTrustRequest request) async {
    final file = await _entry(request.namespace, request.idempotencyKey);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['payload'] is! String ||
          decoded['signature'] is! String) {
        return null;
      }
      final receipt = IsolatedTrustReceipt(
          decoded['payload'] as String, decoded['signature'] as String);
      return await verifier.verifyBoundReceipt(receipt, request)
          ? receipt : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Lost-reply recovery must consult the authoritative current revision.
  /// A disk cache hit is not proof that a later revoke did not occur.
  /// Synthetic fake only; never substitute this for a vetted remote provider.
  Future<IsolatedTrustReceipt?> reconcileLostReply(
      IsolatedTrustRequest request) async {
    final current = verifier.reconcileCurrent(request);
    if (current == null ||
        !await verifier.verifyBoundReceipt(current, request)) {
      return null;
    }
    if (!await record(request, current)) return null;
    return current;
  }

  bool canActivateProduction() => false;
}
