// C500-G0l: isolated bounded XRef-stream object-access experiment.
// Reads only the pinned PDF's startxref stream; never opens a whole-document
// object graph or promotes any invoice/winning/NOT_WIN authority.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_bounded_stream_decoder.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';

class C500G0BoundedXrefException implements Exception {
  const C500G0BoundedXrefException(this.code);
  final String code;
  @override
  String toString() => code;
}

class C500G0BoundedXrefInspector {
  const C500G0BoundedXrefInspector({
    this.maxHeaderBytes = 1024 * 1024,
    this.maxCompressedBytes = 32 * 1024 * 1024,
    this.maxDecodedBytes = 64 * 1024 * 1024,
  });

  final int maxHeaderBytes;
  final int maxCompressedBytes;
  final int maxDecodedBytes;

  Future<Map<String, Object?>> inspect({
    required File file,
    required int expectedBytes,
    required String expectedSha256,
    bool verifyObjectOffsets = false,
    bool verifyCompressedMembers = false,
  }) async {
    if (maxHeaderBytes < 256 ||
        maxCompressedBytes <= 0 ||
        maxDecodedBytes <= 0) {
      throw const C500G0BoundedXrefException('C500_G0L_INVALID_LIMITS');
    }
    if (verifyCompressedMembers && !verifyObjectOffsets) {
      throw const C500G0BoundedXrefException('C500_G0O_REQUIRES_OFFSET_VERIFICATION');
    }
    // Reuse the existing fixed-window SHA/topology probe, not PDFBox/qpdf.
    final source = await const CloudAwardPdfStructureProbe().inspect(file: file);
    if (source.byteLength != expectedBytes ||
        source.sha256 != expectedSha256) {
      throw const C500G0BoundedXrefException('C500_G0L_SOURCE_PIN_MISMATCH');
    }
    if (source.xrefTopology != CloudAwardPdfXrefTopology.xrefStream ||
        source.hasEncryptionMarker ||
        source.hasIncrementalPreviousRevision) {
      throw const C500G0BoundedXrefException('C500_G0L_UNSUPPORTED_TOPOLOGY');
    }

    final handle = await file.open(mode: FileMode.read);
    try {
      await handle.setPosition(source.startXrefOffset);
      final headerBytes = await handle.read(
        min(maxHeaderBytes, source.byteLength - source.startXrefOffset),
      );
      final header = latin1.decode(headerBytes, allowInvalid: true);
      if (!RegExp(r'^\s*\d+\s+\d+\s+obj\b').hasMatch(header)) {
        throw const C500G0BoundedXrefException('C500_G0L_XREF_OBJECT_MISSING');
      }
      // G0m: real pinned XRef streams did not match the old 64 KiB,
      // newline-before-stream assumption. Only accept a bounded dictionary
      // terminator and stream token, never scan arbitrary PDF content.
      final streamMarker = RegExp(
        r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
      ).firstMatch(header);
      if (streamMarker == null) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_HEADER_MISSING');
      }
      final dictionary = header.substring(0, streamMarker.start + 2);
      if (!dictionary.endsWith('>>') ||
          !RegExp(r'/Type\s*/XRef\b').hasMatch(dictionary)) {
        throw const C500G0BoundedXrefException('C500_G0L_NOT_XREF_STREAM');
      }
      if (RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
        throw const C500G0BoundedXrefException('C500_G0L_INDIRECT_LENGTH');
      }
      if (!RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
              .hasMatch(dictionary) ||
          dictionary.contains('/DecodeParms')) {
        throw const C500G0BoundedXrefException('C500_G0L_UNSUPPORTED_FILTER');
      }
      int requiredNumber(String key) {
        final match = RegExp('/$key' r'\s+(\d+)\b').firstMatch(dictionary);
        if (match == null) {
          throw const C500G0BoundedXrefException('C500_G0L_REQUIRED_NUMBER_MISSING');
        }
        return int.parse(match.group(1)!);
      }

      final size = requiredNumber('Size');
      final compressedLength = requiredNumber('Length');
      final widthsMatch =
          RegExp(r'/W\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s*\]').firstMatch(dictionary);
      if (widthsMatch == null) {
        throw const C500G0BoundedXrefException('C500_G0L_W_MISSING');
      }
      final widths = <int>[
        int.parse(widthsMatch.group(1)!),
        int.parse(widthsMatch.group(2)!),
        int.parse(widthsMatch.group(3)!),
      ];
      final entryWidth = widths.reduce((a, b) => a + b);
      if (size <= 0 ||
          size > 8000000 ||
          widths.any((value) => value < 0 || value > 8) ||
          entryWidth == 0) {
        throw const C500G0BoundedXrefException('C500_G0L_INVALID_ENTRY_WIDTH');
      }

      final indexMatch = RegExp(r'/Index\s*\[([0-9\s]+)\]').firstMatch(dictionary);
      final indexes = indexMatch == null
          ? <int>[0, size]
          : RegExp(r'\d+')
              .allMatches(indexMatch.group(1)!)
              .map((match) => int.parse(match.group(0)!))
              .toList(growable: false);
      if (indexes.isEmpty || indexes.length.isOdd) {
        throw const C500G0BoundedXrefException('C500_G0L_INVALID_INDEX');
      }
      var entries = 0;
      for (var i = 0; i < indexes.length; i += 2) {
        if (indexes[i] < 0 ||
            indexes[i + 1] <= 0 ||
            indexes[i] + indexes[i + 1] > size) {
          throw const C500G0BoundedXrefException('C500_G0L_INVALID_INDEX');
        }
        entries += indexes[i + 1];
      }
      if (entries > maxDecodedBytes ~/ entryWidth) {
        throw const C500G0BoundedXrefException('C500_G0L_DECODED_LIMIT');
      }
      if (compressedLength <= 0 || compressedLength > maxCompressedBytes) {
        throw const C500G0BoundedXrefException('C500_G0L_COMPRESSED_LIMIT');
      }
      final streamOffset = source.startXrefOffset + streamMarker.end;
      if (streamOffset + compressedLength > source.byteLength) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_TRUNCATED');
      }
      await handle.setPosition(streamOffset);
      final compressed = await handle.read(compressedLength);
      if (compressed.length != compressedLength) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_TRUNCATED');
      }
      final decoded = CloudAwardPdfBoundedStreamDecoder(
        maxCompressedBytes: maxCompressedBytes,
        maxDecodedBytes: maxDecodedBytes,
      ).decode(bytes: compressed, filters: const <String>['FlateDecode']);
      if (decoded.length != entries * entryWidth) {
        throw const C500G0BoundedXrefException('C500_G0L_DECODED_LENGTH_MISMATCH');
      }
      final types = <int, int>{0: 0, 1: 0, 2: 0};
      for (var offset = 0; offset < decoded.length; offset += entryWidth) {
        var type = widths[0] == 0 ? 1 : 0;
        for (var i = 0; i < widths[0]; i++) {
          type = (type << 8) | decoded[offset + i];
        }
        if (!types.containsKey(type)) {
          throw const C500G0BoundedXrefException('C500_G0L_UNKNOWN_ENTRY_TYPE');
        }
        types[type] = types[type]! + 1;
      }
      final navigation = verifyObjectOffsets
          ? await _sampleAddresses(handle, source.byteLength, decoded,
              widths, indexes, entryWidth, size, verifyCompressedMembers)
          : const <String, Object?>{};
      return <String, Object?>{
        'gate': 'C500_G0L_BOUNDED_XREF_ONLY',
        ...navigation,
        'sha256': source.sha256,
        'bytes': source.byteLength,
        'startxref': source.startXrefOffset,
        'declared_size': size,
        'xref_entries': entries,
        'entry_width': entryWidth,
        'compressed_bytes': compressedLength,
        'decoded_bytes': decoded.length,
        'free_entries': types[0],
        'uncompressed_entries': types[1],
        'object_stream_entries': types[2],
        'all_pages': 'NOT_VERIFIED',
        'global_not_win': 'NOT_PROVEN',
        'award_authority': 'HOLD',
      };
    } finally {
      await handle.close();
    }
  }

  // G0n: at most five direct and five compressed-parent address samples.
  // Header samples are not a page-tree traversal or a NOT_WIN proof.
  Future<Map<String, Object?>> _sampleAddresses(
    RandomAccessFile file, int length, List<int> bytes,
    List<int> widths, List<int> indexes, int stride, int size,
    bool verifyCompressedMembers,
  ) async {
    int field(int offset, int count) {
      var result = 0;
      for (var i = 0; i < count; i++) {
        result = (result << 8) | bytes[offset + i];
      }
      return result;
    }
    Map<String, int>? lookup(int id) {
      var base = 0;
      for (var i = 0; i < indexes.length; i += 2) {
        final start = indexes[i], count = indexes[i + 1];
        if (id >= start && id < start + count) {
          final offset = (base + id - start) * stride;
          return <String, int>{
            'type': widths[0] == 0 ? 1 : field(offset, widths[0]),
            'second': field(offset + widths[0], widths[1]),
            'third': field(offset + widths[0] + widths[1], widths[2]),
          };
        }
        base += count;
      }
      return null;
    }
    final targets = <int>[0, size ~/ 4, size ~/ 2, size * 3 ~/ 4, size - 1];
    final direct = <Map<String, int>>[], compressed = <Map<String, int>>[];
    var d = 0, c = 0, base = 0;
    for (var i = 0; i < indexes.length; i += 2) {
      for (var j = 0; j < indexes[i + 1]; j++) {
        final id = indexes[i] + j, offset = (base + j) * stride;
        final type = widths[0] == 0 ? 1 : field(offset, widths[0]);
        if (type == 1 && d < targets.length && id >= targets[d]) {
          direct.add(<String, int>{
            'id': id,
            'offset': field(offset + widths[0], widths[1]),
            'generation': field(offset + widths[0] + widths[1], widths[2]),
          });
          d++;
        } else if (type == 2 && c < targets.length && id >= targets[c]) {
          compressed.add(<String, int>{
            'id': id,
            'parent': field(offset + widths[0], widths[1]),
            'index': field(offset + widths[0] + widths[1], widths[2]),
          });
          c++;
        }
      }
      base += indexes[i + 1];
    }
    Future<String> header(int id, int generation, int offset) async {
      if (offset < 0 || offset >= length) {
        throw const C500G0BoundedXrefException('C500_G0N_OBJECT_OFFSET_INVALID');
      }
      await file.setPosition(offset);
      final content = latin1.decode(
        await file.read(min(4096, length - offset)), allowInvalid: true,
      );
      if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(content)) {
        throw const C500G0BoundedXrefException('C500_G0N_OBJECT_HEADER_MISMATCH');
      }
      return content;
    }
    for (final sample in direct) {
      await header(sample['id']!, sample['generation']!, sample['offset']!);
    }
    var verifiedMembers = 0;
    for (final sample in compressed) {
      final id = sample['parent']!, parent = lookup(sample['parent']!);
      if (parent == null || parent['type'] != 1) {
        throw const C500G0BoundedXrefException('C500_G0N_PARENT_NOT_DIRECT');
      }
      final content = await header(id, parent['third']!, parent['second']!);
      if (!RegExp(r'/Type\s*/ObjStm\b').hasMatch(content)) {
        throw const C500G0BoundedXrefException('C500_G0N_PARENT_NOT_OBJSTM');
      }
      final match = RegExp(r'/N\s+(\d+)\b').firstMatch(content);
      final count = int.tryParse(match?.group(1) ?? '');
      if (count == null || count <= 0 || sample['index']! >= count) {
        throw const C500G0BoundedXrefException('C500_G0N_COMPRESSED_INDEX_INVALID');
      }
      if (verifyCompressedMembers) {
        await _verifyCompressedMember(file, length, parent['second']!, content, sample);
        verifiedMembers++;
      }
    }
    return <String, Object?>{
      'object_navigation': verifyCompressedMembers
          ? 'BOUNDED_OBJSTM_MEMBER_SAMPLES_ONLY'
          : 'BOUNDED_HEADER_SAMPLES_ONLY',
      'compressed_members_verified': verifiedMembers,
      'direct_headers_verified': direct.length,
      'objstm_parent_headers_verified': compressed.length,
      'page_tree': 'NOT_TRAVERSED',
    };
  }

  // G0o: decode only a selected size-capped ObjStm and prove that its
  // XRef compressed member id/index pair matches. Not full-page evidence.
  Future<void> _verifyCompressedMember(
    RandomAccessFile file, int sourceLength, int parentOffset,
    String header, Map<String, int> sample,
  ) async {
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(header);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_HEADER_MISSING');
    }
    final dictionary = header.substring(0, marker.start + 2);
    if (!RegExp(r'/Type\s*/ObjStm\b').hasMatch(dictionary) ||
        !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
            .hasMatch(dictionary) ||
        dictionary.contains('/DecodeParms') ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0O_UNSUPPORTED_STREAM');
    }
    int number(String key) {
      final match = RegExp('/$key' r'\s+(\d+)\b').firstMatch(dictionary);
      if (match == null) {
        throw const C500G0BoundedXrefException('C500_G0O_REQUIRED_NUMBER_MISSING');
      }
      return int.parse(match.group(1)!);
    }
    final count = number('N'), first = number('First');
    final compressedLength = number('Length');
    if (count <= 0 || count > 100000 ||
        first <= 0 || first > 1024 * 1024 ||
        compressedLength <= 0 || compressedLength > 2 * 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_LIMIT');
    }
    final offset = parentOffset + marker.end;
    if (offset < 0 || offset > sourceLength ||
        compressedLength > sourceLength - offset) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_TRUNCATED');
    }
    await file.setPosition(offset);
    final compressed = await file.read(compressedLength);
    if (compressed.length != compressedLength) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_TRUNCATED');
    }
    final decoded = const CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 2 * 1024 * 1024,
      maxDecodedBytes: 8 * 1024 * 1024,
    ).decode(bytes: compressed, filters: const <String>['FlateDecode']);
    if (first >= decoded.length) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_INVALID');
    }
    final words = latin1.decode(decoded.sublist(0, first))
        .trim().split(RegExp(r'\s+'));
    if (words.length != 2 * count ||
        words.any((word) => !RegExp(r'^\d+$').hasMatch(word))) {
      throw const C500G0BoundedXrefException('C500_G0O_INDEX_HEADER_INVALID');
    }
    final index = sample['index']!;
    if (index < 0 || index >= count ||
        int.parse(words[2 * index]) != sample['id']) {
      throw const C500G0BoundedXrefException('C500_G0O_MEMBER_ID_MISMATCH');
    }
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final start = int.parse(words[2 * i + 1]);
      if (start < 0 || start <= previous ||
          start >= decoded.length - first) {
        throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
      }
      previous = start;
    }
    final start = first + int.parse(words[2 * index + 1]);
    final end = index + 1 == count
        ? decoded.length
        : first + int.parse(words[2 * (index + 1) + 1]);
    if (end <= start || decoded.sublist(start, end).every((b) => b <= 32)) {
      throw const C500G0BoundedXrefException('C500_G0O_EMPTY_MEMBER');
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('C500_G0L_USAGE_NO_ARGUMENTS');
    exitCode = 64;
    return;
  }
  const sources = <Map<String, Object>>[
    <String, Object>{
      'period': '115-05-06',
      'env': 'G0_OLD_PDF',
      'bytes': 119769589,
      'sha': '1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe',
    },
    <String, Object>{
      'period': '115-07-08',
      'env': 'G0_NEW_PDF',
      'bytes': 135200798,
      'sha': 'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571',
    },
  ];
  var failures = 0;
  for (final source in sources) {
    final period = source['period']! as String;
    final path = Platform.environment[source['env']! as String];
    try {
      if (path == null || path.isEmpty) {
        throw const C500G0BoundedXrefException('C500_G0L_SOURCE_UNAVAILABLE');
      }
      final result = await const C500G0BoundedXrefInspector().inspect(
        file: File(path),
        expectedBytes: source['bytes']! as int,
        expectedSha256: source['sha']! as String,
        verifyObjectOffsets: true,
        verifyCompressedMembers: true,
      );
      stdout.writeln(jsonEncode(<String, Object?>{'period': period, ...result}));
    } catch (error) {
      failures++;
      stdout.writeln(jsonEncode(<String, Object?>{
        'period': period,
        'gate': 'C500_G0L_HOLD_BOUNDED_XREF',
        'failure': error.toString(),
        'global_not_win': 'NOT_PROVEN',
        'award_authority': 'HOLD',
      }));
    }
  }
  if (failures != 0) exitCode = 1;
}
