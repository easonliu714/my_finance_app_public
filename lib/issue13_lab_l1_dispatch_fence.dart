import 'dart:convert';
import 'dart:io';

/// Lab-only native process custody; Dart timeout is not native process exit.
class LabL1DispatchFence {
  LabL1DispatchFence(Directory directory)
      : _file = File(
          '${directory.path}${Platform.pathSeparator}l1-native-inflight.json',
        );

  final File _file;
  static const unresolved = 'L1_NATIVE_INFLIGHT_UNRESOLVED';
  static final _requestPattern = RegExp(r'^[0-9]{1,24}$');
  static final _shaPattern = RegExp(r'^[0-9a-f]{64}$');

  Future<void> requireClear() async {
    if (await FileSystemEntity.type(_file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError(unresolved);
    }
  }

  /// Exclusive create preserves a torn marker as HOLD after any crash.
  Future<void> begin({
    required int firstPage,
    required String requestId,
    required String pdfSha256,
  }) async {
    if (firstPage < 1 ||
        firstPage > 100000 ||
        !_requestPattern.hasMatch(requestId) ||
        !_shaPattern.hasMatch(pdfSha256)) {
      throw ArgumentError('L1_NATIVE_DISPATCH_ID_INVALID');
    }
    final record = <String, Object>{
      'version': 1,
      'first_page': firstPage,
      'request_id': requestId,
      'pdf_sha256': pdfSha256,
    };
    await _beginRecord(record);
  }

  // Same durable marker as July/August export: neither operation may
  // dispatch over an unresolved worker from the other period.
  static Map<String, Object> _ownerOpenRecord(String role, String requestId) {
    if ((role != 'sorted' && role != 'draw_order') ||
        !_requestPattern.hasMatch(requestId)) {
      throw ArgumentError('L1_NATIVE_DISPATCH_ID_INVALID');
    }
    return <String, Object>{
      'version': 2,
      'operation': 'may_june_owner_open',
      'role': role,
      'request_id': requestId,
    };
  }

  Future<void> beginOwnerOpen({
    required String role,
    required String requestId,
  }) => _beginRecord(_ownerOpenRecord(role, requestId));

  // Only a matching renderer-closed terminal envelope can clear the marker.
  Future<void> completeOwnerOpen({
    required String role,
    required String requestId,
    required Map<String, dynamic> result,
  }) async {
    final record = _ownerOpenRecord(role, requestId);
    if (result['request_id'] != requestId ||
        result['status'] != 'complete' ||
        result['stage'] != 'L1_OWNER_RENDERER_OPEN_COMPLETE' ||
        result['role'] != role ||
        result['page_count'] != 77000 ||
        result['authority'] != 'LAB_OWNER_ATTESTED_BYTES_ONLY' ||
        result['global_not_win'] != 'HOLD') {
      throw StateError(unresolved);
    }
    await _completeRecord(record);
  }


  // V3 shares the exclusive marker with both older operations.
  static Map<String, Object> _drawRecord(
      int page, String requestId, String pdfSha256) {
    if (page < 1 || page > 77000 ||
        !_requestPattern.hasMatch(requestId) ||
        !_shaPattern.hasMatch(pdfSha256)) {
      throw ArgumentError('L1_NATIVE_DISPATCH_ID_INVALID');
    }
    return <String, Object>{
      'version': 3,
      'operation': 'may_june_draw_page',
      'role': 'draw_order',
      'page': page,
      'request_id': requestId,
      'pdf_sha256': pdfSha256,
    };
  }

  Future<void> beginDrawPage({
    required int page,
    required String requestId,
    required String pdfSha256,
  }) => _beginRecord(_drawRecord(page, requestId, pdfSha256));

  Future<void> completeDrawPage({
    required int page,
    required String requestId,
    required String pdfSha256,
    required Map<String, dynamic> result,
  }) async {
    final record = _drawRecord(page, requestId, pdfSha256);
    final tokens = result['tokens'];
    if (result['request_id'] != requestId ||
        result['status'] != 'complete' ||
        result['stage'] != 'L1_OWNER_DRAW_PAGE_COMPLETE' ||
        result['role'] != 'draw_order' ||
        result['page'] != page ||
        result['page_count'] != 77000 ||
        result['pages_read'] != 1 ||
        result['pdf_sha256'] != pdfSha256 ||
        result['authority'] != 'LAB_OWNER_ATTESTED_BYTES_ONLY' ||
        result['global_not_win'] != 'HOLD' ||
        tokens is! List ||
        tokens.length != 50 ||
        tokens.any((token) => token is! String ||
            !RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(token)) ||
        tokens.toSet().length != 50) {
      throw StateError(unresolved);
    }
    await _completeRecord(record);
  }

  /// Reconcile an owner-open or draw-page marker with its retained, closed-renderer
  /// terminal result. No timeout, age or missing process implies success.
  /// Called at startup before any UI dispatch is enabled.
  Future<bool> recoverOwnerOpen() async {
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    final marker = await _readBoundedObject(_file, 512);
    // The existing v1 export marker requires its own JSONL/cursor evidence.
    if (marker['version'] == 1) return false;
    if (marker['version'] == 3) {
      final page = marker['page'];
      final requestId = marker['request_id'];
      final sha = marker['pdf_sha256'];
      if (page is! int || page < 1 || page > 77000 ||
          requestId is! String || !_requestPattern.hasMatch(requestId) ||
          sha is! String || !_shaPattern.hasMatch(sha)) {
        throw StateError(unresolved);
      }
      await _verifyRecord(_drawRecord(page, requestId, sha));
      final terminal = File(
        '${_file.parent.path}${Platform.pathSeparator}platform_probe_$requestId.json',
      );
      final result = await _readBoundedObject(terminal, 4096);
      await completeDrawPage(
        page: page, requestId: requestId, pdfSha256: sha, result: result,
      );
      return true;
    }
    final role = marker['role'];
    final requestId = marker['request_id'];
    if (marker['version'] != 2 ||
        marker['operation'] != 'may_june_owner_open' ||
        role is! String ||
        requestId is! String ||
        (role != 'sorted' && role != 'draw_order') ||
        !_requestPattern.hasMatch(requestId)) {
      throw StateError(unresolved);
    }
    final record = _ownerOpenRecord(role, requestId);
    await _verifyRecord(record);
    final terminal = File(
      '${_file.parent.path}${Platform.pathSeparator}platform_probe_$requestId.json',
    );
    final result = await _readBoundedObject(terminal, 4096);
    await completeOwnerOpen(role: role, requestId: requestId, result: result);
    return true;
  }

  // Bound reads even if an unexpectedly large file replaces a prior result.
  // Refuse links and non-object JSON; never delete either file on read error.
  Future<Map<String, dynamic>> _readBoundedObject(File file, int limit) async {
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError(unresolved);
      }
      final handle = await file.open();
      try {
        final size = await handle.length();
        if (size <= 0 || size > limit) throw StateError(unresolved);
        final bytes = await handle.read(limit + 1);
        if (bytes.length != size || bytes.length > limit) {
          throw StateError(unresolved);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw StateError(unresolved);
        return decoded;
      } finally {
        await handle.close();
      }
    } catch (_) {
      throw StateError(unresolved);
    }
  }

  Future<void> _beginRecord(Map<String, Object> record) async {
    await requireClear();
    RandomAccessFile? handle;
    try {
      // FileMode has no exclusive-open variant. Reserve the marker path
      // atomically before writing; never overwrite a stale/torn marker.
      await _file.create(exclusive: true);
      if (await FileSystemEntity.type(_file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError(unresolved);
      }
      // Append-only avoids truncation if a competing actor changes the path.
      // Any unexpected content is rejected by the strict readback below.
      handle = await _file.open(mode: FileMode.writeOnlyAppend);
      await handle.writeString('${jsonEncode(record)}\n');
      await handle.flush();
    } on FileSystemException {
      throw StateError(unresolved);
    } finally {
      await handle?.close();
    }
    await _verifyRecord(record);
  }

  /// Call only after terminal native success and strict JSONL verification.
  Future<void> complete({
    required int firstPage,
    required String requestId,
    required String pdfSha256,
  }) async {
    await _completeRecord(<String, Object>{
      'version': 1,
      'first_page': firstPage,
      'request_id': requestId,
      'pdf_sha256': pdfSha256,
    });
  }

  Future<void> _completeRecord(Map<String, Object> record) async {
    await _verifyRecord(record);
    try {
      await _file.delete();
    } on FileSystemException {
      throw StateError(unresolved);
    }
  }

  Future<void> _verifyRecord(Map<String, Object> record) async {
    try {
      final decoded = await _readBoundedObject(_file, 512);
      if (decoded.length != record.length ||
          record.entries.any((entry) => decoded[entry.key] != entry.value)) {
        throw StateError(unresolved);
      }
    } catch (_) {
      throw StateError(unresolved);
    }
  }
}
