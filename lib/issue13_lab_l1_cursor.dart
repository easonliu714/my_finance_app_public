import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Lab-only crash recovery; JSONL structural checks are NOT official evidence.
class LabL1Batch {
  const LabL1Batch(this.file, this.last, this.count);
  final File file;
  final int last;
  final int count;
}

class LabL1Cursor {
  static final namePattern =
      RegExp(r'^l1-pages-([1-9][0-9]*)-([0-9]{1,24})\.jsonl$');

  static Future<LabL1Batch?> recover(
      Directory dir, int first, String sha) async {
    final matches = <File>[];
    await for (final entry in dir.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (!name.startsWith('l1-pages-$first-') ||
          !name.endsWith('.jsonl')) continue;
      if (entry is! File || namePattern.firstMatch(name) == null) {
        throw StateError('L1_CURSOR_UNTRUSTED_ENTRY');
      }
      matches.add(File(entry.path));
      if (matches.length > 1) throw StateError('L1_CURSOR_DUPLICATE_START');
    }
    if (matches.isEmpty) return null;
    return verify(dir, matches.single, first, sha);
  }

  static Future<LabL1Batch> verify(
      Directory dir, File file, int first, String sha,
      {int? last, int? count}) async {
    final name = file.uri.pathSegments.last;
    final match = namePattern.firstMatch(name);
    if (first < 1 || first > 100000 || match == null ||
        int.tryParse(match.group(1)!) != first ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() !=
            '${await dir.resolveSymbolicLinks()}${Platform.pathSeparator}$name') {
      throw StateError('L1_CURSOR_UNTRUSTED_FILE');
    }
    final size = await file.length();
    if (size <= 0 || size > 4000000) {
      throw StateError('L1_CURSOR_BATCH_SIZE');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != size || bytes.last != 10) {
      throw StateError('L1_CURSOR_TRUNCATED');
    }
    final lines = const LineSplitter().convert(utf8.decode(bytes));
    if (lines.isEmpty || lines.length > 4) {
      throw StateError('L1_CURSOR_PAGE_BUDGET');
    }
    int? total;
    for (var i = 0; i < lines.length; i++) {
      if (utf8.encode(lines[i]).length + 1 > 1000000) {
        throw StateError('L1_CURSOR_LINE_BUDGET');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(lines[i]);
      } on FormatException {
        throw StateError('L1_CURSOR_BAD_JSON');
      }
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().length != 7 ||
          !decoded.keys.toSet().containsAll(<String>{
            'page', 'page_count', 'pdf_sha256', 'engine',
            'period', 'tier', 'text',
          }) ||
          decoded['page'] is! int || decoded['page'] != first + i ||
          decoded['page_count'] is! int ||
          (decoded['page_count'] as int) < first + i ||
          (decoded['page_count'] as int) > 100000 ||
          decoded['pdf_sha256'] != sha ||
          decoded['engine'] != 'android.graphics.pdf.PdfRenderer' ||
          decoded['period'] != '115-07-08' ||
          decoded['tier'] != 'cloud-500' ||
          decoded['text'] is! String ||
          (decoded['text'] as String).isEmpty ||
          (decoded['text'] as String).length > 250000) {
        throw StateError('L1_CURSOR_SCOPE_OR_PAGE');
      }
      final pageCount = decoded['page_count'] as int;
      if (total != null && total != pageCount) {
        throw StateError('L1_CURSOR_COUNT_DRIFT');
      }
      total = pageCount;
    }
    final end = first + lines.length - 1;
    if (lines.length != min(4, total! - first + 1) ||
        (last != null && last != end) ||
        (count != null && count != total)) {
      throw StateError('L1_CURSOR_PARTIAL_BATCH');
    }
    return LabL1Batch(file, end, total);
  }
}
