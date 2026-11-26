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
      if (await FileSystemEntity.type(_file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError(unresolved);
      }
      final size = await _file.length();
      if (size <= 0 || size > 512) throw StateError(unresolved);
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded.length != record.length ||
          record.entries.any((entry) => decoded[entry.key] != entry.value)) {
        throw StateError(unresolved);
      }
    } catch (_) {
      throw StateError(unresolved);
    }
  }
}
