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
    await requireClear();
    final record = <String, Object>{
      'version': 1,
      'first_page': firstPage,
      'request_id': requestId,
      'pdf_sha256': pdfSha256,
    };
    RandomAccessFile? handle;
    try {
      handle = await _file.open(mode: FileMode.writeOnlyExclusive);
      await handle.writeString('${jsonEncode(record)}\n');
      await handle.flush();
    } on FileSystemException {
      throw StateError(unresolved);
    } finally {
      await handle?.close();
    }
    await _verify(firstPage, requestId, pdfSha256);
  }

  /// Call only after terminal native success and strict JSONL verification.
  Future<void> complete({
    required int firstPage,
    required String requestId,
    required String pdfSha256,
  }) async {
    await _verify(firstPage, requestId, pdfSha256);
    try {
      await _file.delete();
    } on FileSystemException {
      throw StateError(unresolved);
    }
  }

  Future<void> _verify(int firstPage, String requestId, String sha) async {
    try {
      if (await FileSystemEntity.type(_file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError(unresolved);
      }
      final size = await _file.length();
      if (size <= 0 || size > 512) throw StateError(unresolved);
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 4 ||
          decoded['version'] != 1 ||
          decoded['first_page'] != firstPage ||
          decoded['request_id'] != requestId ||
          decoded['pdf_sha256'] != sha) {
        throw StateError(unresolved);
      }
    } catch (_) {
      throw StateError(unresolved);
    }
  }
}
