import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

enum CloudAwardPdfXrefTopology {
  classicTable,
  xrefStream,
  hybrid,
}

class CloudAwardPdfStructureProbeException implements Exception {
  const CloudAwardPdfStructureProbeException(this.code);

  final String code;

  @override
  String toString() => code;
}

class CloudAwardPdfStructureProbeResult {
  const CloudAwardPdfStructureProbeResult({
    required this.sha256,
    required this.byteLength,
    required this.pdfVersion,
    required this.startXrefOffset,
    required this.xrefTopology,
    required this.hasIncrementalPreviousRevision,
    required this.hasEncryptionMarker,
    required this.objectStreamCount,
    required this.streamCount,
    required this.filterHistogram,
    required this.declaredPageCounts,
    required this.rawVisibleCandidateNumbers,
    required this.maxResidentScanWindowBytes,
  });

  final String sha256;
  final int byteLength;
  final String pdfVersion;
  final int startXrefOffset;
  final CloudAwardPdfXrefTopology xrefTopology;
  final bool hasIncrementalPreviousRevision;
  final bool hasEncryptionMarker;
  final int objectStreamCount;
  final int streamCount;
  final Map<String, int> filterHistogram;
  final List<int> declaredPageCounts;
  final Set<String> rawVisibleCandidateNumbers;
  final int maxResidentScanWindowBytes;
}

/// Bounded raw-byte characterization for an already validated official PDF.
///
/// This probe deliberately does not open a PDF document model. It uses fixed
/// random-access windows for header/tail/xref classification, then one bounded
/// sequential scan for non-sensitive structural markers and exact local
/// candidate visibility. It is diagnostic only: no result from this class is
/// sufficient to promote cloud-award authority.
class CloudAwardPdfStructureProbe {
  const CloudAwardPdfStructureProbe({
    this.scanChunkBytes = 64 * 1024,
    this.scanOverlapBytes = 1024,
    this.headProbeBytes = 4096,
    this.tailProbeBytes = 64 * 1024,
    this.xrefProbeBytes = 64 * 1024,
  })  : assert(scanChunkBytes >= 128),
        assert(scanOverlapBytes >= 32),
        assert(scanOverlapBytes < scanChunkBytes),
        assert(headProbeBytes >= 16),
        assert(tailProbeBytes >= 128),
        assert(xrefProbeBytes >= 128);

  final int scanChunkBytes;
  final int scanOverlapBytes;
  final int headProbeBytes;
  final int tailProbeBytes;
  final int xrefProbeBytes;

  static final RegExp _headerPattern = RegExp(r'%PDF-([0-9]+\.[0-9]+)');
  static final RegExp _startXrefPattern =
      RegExp(r'startxref\s+([0-9]+)', multiLine: true);
  static final RegExp _xrefStreamPattern = RegExp(r'/Type\s*/XRef\b');
  static final RegExp _xrefStmPattern = RegExp(r'/XRefStm\s+[0-9]+\b');
  static final RegExp _previousRevisionPattern = RegExp(r'/Prev\s+[0-9]+\b');
  static final RegExp _objectStreamPattern = RegExp(r'/Type\s*/ObjStm\b');
  static final RegExp _streamPattern =
      RegExp(r'(?:^|[\r\n])stream(?:\r?\n|$)', multiLine: true);
  static final RegExp _filterPattern = RegExp(
    r'/Filter\s*(\[[^\]]{0,256}\]|/[A-Za-z0-9]+)',
    dotAll: true,
  );
  static final RegExp _filterNamePattern = RegExp(r'/([A-Za-z][A-Za-z0-9]*)');
  static final RegExp _pagesPattern = RegExp(
    r'/Type\s*/Pages\b.{0,512}?/Count\s+([0-9]+)\b',
    dotAll: true,
  );
  static final RegExp _encryptionPattern = RegExp(r'/Encrypt\b');
  static final RegExp _invoicePattern = RegExp(r'^[A-Z]{2}[0-9]{8}$');

  Future<CloudAwardPdfStructureProbeResult> inspect({
    required File file,
    Iterable<String> exactCandidateNumbers = const <String>[],
  }) async {
    if (!await file.exists()) {
      throw const CloudAwardPdfStructureProbeException(
        'CLOUD_AWARD_PDF_STRUCTURE_SOURCE_MISSING',
      );
    }

    final handle = await file.open(mode: FileMode.read);
    try {
      final byteLength = await handle.length();
      if (byteLength < 16) {
        throw const CloudAwardPdfStructureProbeException(
          'CLOUD_AWARD_PDF_STRUCTURE_TOO_SMALL',
        );
      }

      final head = await _readTextWindow(
        handle,
        offset: 0,
        count: min(headProbeBytes, byteLength),
      );
      final headerMatch = _headerPattern.firstMatch(head);
      if (headerMatch == null) {
        throw const CloudAwardPdfStructureProbeException(
          'CLOUD_AWARD_PDF_STRUCTURE_HEADER_INVALID',
        );
      }
      final pdfVersion = headerMatch.group(1)!;

      final tailOffset = max(0, byteLength - tailProbeBytes);
      final tail = await _readTextWindow(
        handle,
        offset: tailOffset,
        count: byteLength - tailOffset,
      );
      if (!tail.contains('%%EOF')) {
        throw const CloudAwardPdfStructureProbeException(
          'CLOUD_AWARD_PDF_STRUCTURE_EOF_MISSING',
        );
      }

      final startXrefMatches = _startXrefPattern.allMatches(tail).toList();
      if (startXrefMatches.isEmpty) {
        throw const CloudAwardPdfStructureProbeException(
          'CLOUD_AWARD_PDF_STRUCTURE_STARTXREF_MISSING',
        );
      }
      final startXrefOffset = int.tryParse(startXrefMatches.last.group(1) ?? '');
      if (startXrefOffset == null ||
          startXrefOffset < 0 ||
          startXrefOffset >= byteLength) {
        throw const CloudAwardPdfStructureProbeException(
          'CLOUD_AWARD_PDF_STRUCTURE_STARTXREF_INVALID',
        );
      }

      final xrefText = await _readTextWindow(
        handle,
        offset: startXrefOffset,
        count: min(xrefProbeBytes, byteLength - startXrefOffset),
      );
      final initialTopology = _classifyXref(xrefText);
      final normalizedCandidates = _normalizeCandidates(exactCandidateNumbers);

      await handle.setPosition(0);
      final hashSink = Sha256().newHashSink();
      final filterHistogram = <String, int>{};
      final declaredPageCounts = <int>{};
      final rawVisibleCandidates = <String>{};
      var objectStreamCount = 0;
      var streamCount = 0;
      var hasEncryptionMarker = false;
      var hasXrefStmMarker = _xrefStmPattern.hasMatch(xrefText);
      var hasPreviousRevision = _previousRevisionPattern.hasMatch(xrefText);

      var position = 0;
      var processedThrough = 0;
      var carry = '';

      while (position < byteLength) {
        final readLength = min(scanChunkBytes, byteLength - position);
        final bytes = await handle.read(readLength);
        if (bytes.isEmpty) break;
        hashSink.add(bytes);

        final chunk = latin1.decode(bytes, allowInvalid: true);
        final combined = carry + chunk;
        final combinedStart = position - carry.length;
        final nextPosition = position + bytes.length;
        final isLastChunk = nextPosition >= byteLength;
        final safeEnd = isLastChunk
            ? nextPosition
            : max(processedThrough, nextPosition - scanOverlapBytes);

        bool eligible(Match match) {
          final globalEnd = combinedStart + match.end;
          return globalEnd > processedThrough && globalEnd <= safeEnd;
        }

        for (final match in _objectStreamPattern.allMatches(combined)) {
          if (eligible(match)) objectStreamCount += 1;
        }
        for (final match in _streamPattern.allMatches(combined)) {
          if (eligible(match)) streamCount += 1;
        }
        for (final match in _filterPattern.allMatches(combined)) {
          if (!eligible(match)) continue;
          final value = match.group(1) ?? '';
          for (final nameMatch in _filterNamePattern.allMatches(value)) {
            final name = nameMatch.group(1)!;
            filterHistogram[name] = (filterHistogram[name] ?? 0) + 1;
          }
        }
        for (final match in _pagesPattern.allMatches(combined)) {
          if (!eligible(match)) continue;
          final count = int.tryParse(match.group(1) ?? '');
          if (count != null && count > 0) declaredPageCounts.add(count);
        }
        for (final match in _encryptionPattern.allMatches(combined)) {
          if (eligible(match)) {
            hasEncryptionMarker = true;
            break;
          }
        }
        for (final match in _xrefStmPattern.allMatches(combined)) {
          if (eligible(match)) {
            hasXrefStmMarker = true;
            break;
          }
        }
        for (final match in _previousRevisionPattern.allMatches(combined)) {
          if (eligible(match)) {
            hasPreviousRevision = true;
            break;
          }
        }

        for (final candidate in normalizedCandidates) {
          if (rawVisibleCandidates.contains(candidate)) continue;
          var searchFrom = 0;
          while (true) {
            final found = combined.indexOf(candidate, searchFrom);
            if (found < 0) break;
            final globalEnd = combinedStart + found + candidate.length;
            if (globalEnd > processedThrough && globalEnd <= safeEnd) {
              rawVisibleCandidates.add(candidate);
              break;
            }
            searchFrom = found + 1;
          }
        }

        processedThrough = safeEnd;
        final carryStart = max(0, combined.length - scanOverlapBytes);
        carry = combined.substring(carryStart);
        position = nextPosition;
      }

      hashSink.close();
      final hash = await hashSink.hash();
      final sha256 = hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      final topology =
          initialTopology == CloudAwardPdfXrefTopology.classicTable &&
                  hasXrefStmMarker
              ? CloudAwardPdfXrefTopology.hybrid
              : initialTopology;
      final orderedFilters = filterHistogram.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final orderedPageCounts = declaredPageCounts.toList()..sort();

      return CloudAwardPdfStructureProbeResult(
        sha256: sha256,
        byteLength: byteLength,
        pdfVersion: pdfVersion,
        startXrefOffset: startXrefOffset,
        xrefTopology: topology,
        hasIncrementalPreviousRevision: hasPreviousRevision,
        hasEncryptionMarker: hasEncryptionMarker,
        objectStreamCount: objectStreamCount,
        streamCount: streamCount,
        filterHistogram: Map<String, int>.unmodifiable(
          <String, int>{
            for (final entry in orderedFilters) entry.key: entry.value,
          },
        ),
        declaredPageCounts: List<int>.unmodifiable(orderedPageCounts),
        rawVisibleCandidateNumbers:
            Set<String>.unmodifiable(rawVisibleCandidates),
        maxResidentScanWindowBytes: scanChunkBytes + scanOverlapBytes,
      );
    } finally {
      await handle.close();
    }
  }

  CloudAwardPdfXrefTopology _classifyXref(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('xref')) {
      return _xrefStmPattern.hasMatch(text)
          ? CloudAwardPdfXrefTopology.hybrid
          : CloudAwardPdfXrefTopology.classicTable;
    }
    if (RegExp(r'^[0-9]+\s+[0-9]+\s+obj\b').hasMatch(trimmed) &&
        _xrefStreamPattern.hasMatch(text)) {
      return CloudAwardPdfXrefTopology.xrefStream;
    }
    throw const CloudAwardPdfStructureProbeException(
      'CLOUD_AWARD_PDF_STRUCTURE_UNSUPPORTED_XREF',
    );
  }

  Future<String> _readTextWindow(
    RandomAccessFile file, {
    required int offset,
    required int count,
  }) async {
    await file.setPosition(offset);
    final bytes = await file.read(count);
    return latin1.decode(bytes, allowInvalid: true);
  }

  Set<String> _normalizeCandidates(Iterable<String> values) {
    final normalized = <String>{};
    for (final raw in values) {
      final value = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
      if (_invoicePattern.hasMatch(value)) normalized.add(value);
    }
    return normalized;
  }
}
