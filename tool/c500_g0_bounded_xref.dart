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
    this.maxHeaderBytes = 64 * 1024,
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
  }) async {
    if (maxHeaderBytes < 256 ||
        maxCompressedBytes <= 0 ||
        maxDecodedBytes <= 0) {
      throw const C500G0BoundedXrefException('C500_G0L_INVALID_LIMITS');
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
      final streamMarker =
          RegExp(r'(?:\r\n|\r|\n)stream(?:\r\n|\r|\n)').firstMatch(header);
      if (streamMarker == null) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_HEADER_MISSING');
      }
      final dictionary = header.substring(0, streamMarker.start).trimRight();
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
        final match = RegExp('/' + key + r'\s+(\d+)\b').firstMatch(dictionary);
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
      return <String, Object?>{
        'gate': 'C500_G0L_BOUNDED_XREF_ONLY',
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
