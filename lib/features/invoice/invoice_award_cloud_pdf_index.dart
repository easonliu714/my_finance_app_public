import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';

import 'invoice_award_cloud_artifact_downloader.dart';

typedef CloudAwardPdfPageCallback = FutureOr<void> Function(
  int pageNumber,
  int pageCount,
  String text,
);

enum CloudAwardPdfExtractorStage {
  openingChunk,
  chunkOpened,
  pageStarted,
  pageCompleted,
  chunkClosed,
}

class CloudAwardPdfExtractorProgress {
  const CloudAwardPdfExtractorProgress({
    required this.stage,
    this.pageNumber,
    this.pageCount,
    this.chunkStart,
    this.chunkEnd,
  });

  final CloudAwardPdfExtractorStage stage;
  final int? pageNumber;
  final int? pageCount;
  final int? chunkStart;
  final int? chunkEnd;
}

typedef CloudAwardPdfExtractorProgressCallback = void Function(
  CloudAwardPdfExtractorProgress progress,
);

abstract class CloudAwardPdfTextExtractor {
  const CloudAwardPdfTextExtractor();

  String get extractorVersion;

  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage, {
    CloudAwardPdfExtractorProgressCallback? onProgress,
  });
}

/// Production text extractor backed by PDFBox Android / PDFKit iOS through
/// flutter_pdf_text. Pages are requested lazily rather than reading the whole
/// document text into a single Dart string.
class FlutterPdfTextCloudAwardExtractor extends CloudAwardPdfTextExtractor {
  const FlutterPdfTextCloudAwardExtractor();

  static const MethodChannel _channel = MethodChannel('pdf_text');
  static const int androidChunkPageCount = 8;

  @override
  String get extractorVersion =>
      'flutter_pdf_text-0.9.0-android-chunk8-diagnostic-v3';

  @override
  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage, {
    CloudAwardPdfExtractorProgressCallback? onProgress,
  }) async {
    if (Platform.isAndroid) {
      await _forEachAndroidChunk(pdfFile, onPage, onProgress: onProgress);
      return;
    }

    final document = await PDFDoc.fromFile(pdfFile);
    final pageCount = document.length;
    if (pageCount <= 0) {
      throw StateError('CLOUD_AWARD_PDF_PAGE_COUNT_INVALID');
    }
    for (var page = 1; page <= pageCount; page += 1) {
      onProgress?.call(CloudAwardPdfExtractorProgress(
        stage: CloudAwardPdfExtractorStage.pageStarted,
        pageNumber: page,
        pageCount: pageCount,
      ));
      final text = await document.pageAt(page).text;
      await onPage(page, pageCount, text);
      onProgress?.call(CloudAwardPdfExtractorProgress(
        stage: CloudAwardPdfExtractorStage.pageCompleted,
        pageNumber: page,
        pageCount: pageCount,
      ));
    }
  }

  Future<void> _forEachAndroidChunk(
    File pdfFile,
    CloudAwardPdfPageCallback onPage, {
    CloudAwardPdfExtractorProgressCallback? onProgress,
  }) async {
    var chunkStart = 1;
    int? pageCount;

    while (pageCount == null || chunkStart <= pageCount) {
      final plannedEnd = pageCount == null
          ? chunkStart + androidChunkPageCount - 1
          : min(pageCount, chunkStart + androidChunkPageCount - 1);
      onProgress?.call(CloudAwardPdfExtractorProgress(
        stage: CloudAwardPdfExtractorStage.openingChunk,
        pageCount: pageCount,
        chunkStart: chunkStart,
        chunkEnd: plannedEnd,
      ));

      final opened = await _channel.invokeMapMethod<String, Object?>(
        'openDocSession',
        <String, Object?>{'path': pdfFile.path, 'password': ''},
      );
      final sessionId = opened?['sessionId']?.toString() ?? '';
      final openedPageCount = (opened?['length'] as num?)?.toInt() ?? 0;
      if (sessionId.isEmpty || openedPageCount <= 0) {
        throw StateError('CLOUD_AWARD_PDF_SESSION_INVALID');
      }
      pageCount ??= openedPageCount;
      if (pageCount != openedPageCount) {
        throw StateError('CLOUD_AWARD_PDF_PAGE_COUNT_CHANGED');
      }
      final chunkEnd = min(
        pageCount,
        chunkStart + androidChunkPageCount - 1,
      );
      onProgress?.call(CloudAwardPdfExtractorProgress(
        stage: CloudAwardPdfExtractorStage.chunkOpened,
        pageCount: pageCount,
        chunkStart: chunkStart,
        chunkEnd: chunkEnd,
      ));

      try {
        for (var page = chunkStart; page <= chunkEnd; page += 1) {
          onProgress?.call(CloudAwardPdfExtractorProgress(
            stage: CloudAwardPdfExtractorStage.pageStarted,
            pageNumber: page,
            pageCount: pageCount,
            chunkStart: chunkStart,
            chunkEnd: chunkEnd,
          ));
          final text = await _channel.invokeMethod<String>(
                'getDocSessionPageText',
                <String, Object?>{'sessionId': sessionId, 'number': page},
              ) ??
              '';
          await onPage(page, pageCount, text);
          onProgress?.call(CloudAwardPdfExtractorProgress(
            stage: CloudAwardPdfExtractorStage.pageCompleted,
            pageNumber: page,
            pageCount: pageCount,
            chunkStart: chunkStart,
            chunkEnd: chunkEnd,
          ));
        }
      } finally {
        try {
          await _channel.invokeMethod<void>(
            'closeDocSession',
            <String, Object?>{'sessionId': sessionId},
          );
        } catch (_) {
          // Cleanup failure must not mask the extraction result.
        }
        onProgress?.call(CloudAwardPdfExtractorProgress(
          stage: CloudAwardPdfExtractorStage.chunkClosed,
          pageCount: pageCount,
          chunkStart: chunkStart,
          chunkEnd: chunkEnd,
        ));
      }
      chunkStart = chunkEnd + 1;
    }

    await _channel.invokeMethod<void>(
      'markExtractionComplete',
      <String, Object?>{'path': pdfFile.path},
    );
  }

  Future<Map<String, Object?>?> readLastNativeDiagnostic() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMapMethod<String, Object?>('getLastDiagnostic');
  }

  static String? diagnosticText(Map<String, Object?>? diagnostic) {
    if (diagnostic == null || diagnostic.isEmpty) return null;
    final stage = diagnostic['stage']?.toString() ?? '';
    if (stage.isEmpty || stage == 'EXTRACTION_COMPLETE') return null;
    final page = (diagnostic['page_number'] as num?)?.toInt() ?? 0;
    final pageCount = (diagnostic['page_count'] as num?)?.toInt() ?? 0;
    final used = (diagnostic['heap_used_bytes'] as num?)?.toInt() ?? 0;
    final max = (diagnostic['heap_max_bytes'] as num?)?.toInt() ?? 0;
    final fileBytes = (diagnostic['file_bytes'] as num?)?.toInt() ?? 0;
    final pageText = page > 0
        ? ' · page ' + page.toString() +
            (pageCount > 0 ? '/' + pageCount.toString() : '')
        : '';
    final heapText = max > 0
        ? ' · heap ' +
            (used / 1048576).toStringAsFixed(1) + '/' +
            (max / 1048576).toStringAsFixed(1) + ' MB'
        : '';
    final fileText = fileBytes > 0
        ? ' · PDF ' + (fileBytes / 1048576).toStringAsFixed(1) + ' MB'
        : '';
    return stage + pageText + heapText + fileText;
  }
}

class CloudAwardLocalIndexManifest {
  const CloudAwardLocalIndexManifest({
    required this.periodId,
    required this.tierCode,
    required this.officialSourceUri,
    required this.pdfSha256,
    required this.indexSha256,
    required this.extractorVersion,
    required this.rowCount,
    required this.builtAt,
  });

  final String periodId;
  final String tierCode;
  final Uri officialSourceUri;
  final String pdfSha256;
  final String indexSha256;
  final String extractorVersion;
  final int rowCount;
  final DateTime builtAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'period_id': periodId,
        'tier_code': tierCode,
        'official_source_url': officialSourceUri.toString(),
        'pdf_sha256': pdfSha256,
        'index_sha256': indexSha256,
        'extractor_version': extractorVersion,
        'row_count': rowCount,
        'built_at': builtAt.toUtc().toIso8601String(),
      };
}

class CloudAwardIndexBuildResult {
  const CloudAwardIndexBuildResult({
    required this.candidateIndexFile,
    required this.manifest,
  });

  final File candidateIndexFile;
  final CloudAwardLocalIndexManifest manifest;
}

typedef CloudAwardIndexBuildProgressCallback = void Function(
  int pageNumber,
  int pageCount,
  int rowCount,
);

/// Converts one already-downloaded official sorted PDF into a bounded,
/// line-oriented local membership index.
///
/// This builder deliberately writes a *candidate* index only. LKG promotion is
/// a separate gate so a parse/build failure cannot overwrite a previously
/// validated cloud-award index.
class CloudAwardPdfIndexBuilder {
  const CloudAwardPdfIndexBuilder({
    required this.extractor,
  });

  final CloudAwardPdfTextExtractor extractor;

  Future<CloudAwardIndexBuildResult> buildCandidate({
    required OfficialCloudAwardDownloadedArtifact artifact,
    required File candidateIndexFile,
    CloudAwardIndexBuildProgressCallback? onProgress,
    CloudAwardPdfExtractorProgressCallback? onExtractorProgress,
    DateTime? builtAt,
  }) async {
    if (!artifact.reference.isApprovedOfficialSource ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(artifact.sha256)) {
      await _deleteIfExists(candidateIndexFile);
      throw StateError('CLOUD_AWARD_INDEX_SOURCE_AUTHORITY_INVALID');
    }

    await candidateIndexFile.parent.create(recursive: true);
    await _deleteIfExists(candidateIndexFile);

    IOSink? sink;
    var rowCount = 0;
    try {
      sink = candidateIndexFile.openWrite(mode: FileMode.writeOnly);
      await extractor.forEachPage(
        artifact.file,
        (pageNumber, pageCount, text) async {
          final tokens = _extractInvoiceNumbers(text);
          for (final token in tokens) {
            sink!.writeln(token);
            rowCount += 1;
          }
          onProgress?.call(pageNumber, pageCount, rowCount);
        },
        onProgress: onExtractorProgress,
      );
      await sink.flush();
      await sink.close();
      sink = null;

      if (rowCount <= 0) {
        throw StateError('CLOUD_AWARD_INDEX_EMPTY');
      }

      final indexSha256 = await _sha256File(candidateIndexFile);
      return CloudAwardIndexBuildResult(
        candidateIndexFile: candidateIndexFile,
        manifest: CloudAwardLocalIndexManifest(
          periodId: artifact.reference.periodId,
          tierCode: artifact.reference.tierCode,
          officialSourceUri: artifact.reference.sourceUri,
          pdfSha256: artifact.sha256.toLowerCase(),
          indexSha256: indexSha256,
          extractorVersion: extractor.extractorVersion,
          rowCount: rowCount,
          builtAt: (builtAt ?? DateTime.now()).toUtc(),
        ),
      );
    } catch (_) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      await _deleteIfExists(candidateIndexFile);
      rethrow;
    }
  }

  static List<String> _extractInvoiceNumbers(String text) {
    final normalized = text.toUpperCase();
    final matches = RegExp(r'[A-Z]{2}\s*[0-9]{8}').allMatches(normalized);
    final result = <String>[];
    for (final match in matches) {
      final before = match.start == 0 ? null : normalized[match.start - 1];
      final after = match.end == normalized.length ? null : normalized[match.end];
      if (_isAsciiAlphaNumeric(before) || _isAsciiAlphaNumeric(after)) {
        continue;
      }
      final token = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(token)) {
        result.add(token);
      }
    }
    return result;
  }

  static bool _isAsciiAlphaNumeric(String? value) =>
      value != null && RegExp(r'^[A-Z0-9]$').hasMatch(value);

  static Future<String> _sha256File(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}

/// Exact local membership query over one newline index. Memory use is bounded
/// by the user's small candidate set; the official multi-million-number index
/// is streamed once and never loaded as a Dart Set.
class CloudAwardLocalIndexLookup {
  const CloudAwardLocalIndexLookup();

  Future<Set<String>> findMatches({
    required File indexFile,
    required Iterable<String> invoiceNumbers,
  }) async {
    final wanted = <String>{
      for (final raw in invoiceNumbers)
        raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(),
    };
    if (wanted.any((item) => !RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(item))) {
      throw const FormatException('invalid cloud award lookup candidate');
    }
    if (wanted.isEmpty) return const <String>{};

    final matches = <String>{};
    final lines = indexFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(line)) {
        throw const FormatException('malformed cloud award local index');
      }
      if (wanted.contains(line)) {
        matches.add(line);
        if (matches.length == wanted.length) break;
      }
    }
    return Set<String>.unmodifiable(matches);
  }
}
