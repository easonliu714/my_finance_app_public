import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';

import 'invoice_award_cloud_artifact_downloader.dart';

typedef CloudAwardPdfPageCallback = FutureOr<void> Function(
  int pageNumber,
  int pageCount,
  String text,
);

abstract class CloudAwardPdfTextExtractor {
  const CloudAwardPdfTextExtractor();

  String get extractorVersion;

  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage,
  );
}

/// Production text extractor backed by PDFBox Android / PDFKit iOS through
/// flutter_pdf_text. Pages are requested lazily rather than reading the whole
/// document text into a single Dart string.
class FlutterPdfTextCloudAwardExtractor extends CloudAwardPdfTextExtractor {
  const FlutterPdfTextCloudAwardExtractor();

  static const MethodChannel _channel = MethodChannel('pdf_text');

  @override
  String get extractorVersion => 'flutter_pdf_text-0.9.0-android-session-page-v2';

  @override
  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage,
  ) async {
    if (Platform.isAndroid) {
      await _forEachAndroidSession(pdfFile, onPage);
      return;
    }

    final document = await PDFDoc.fromFile(pdfFile);
    final pageCount = document.length;
    if (pageCount <= 0) {
      throw StateError('CLOUD_AWARD_PDF_PAGE_COUNT_INVALID');
    }
    for (var page = 1; page <= pageCount; page += 1) {
      final text = await document.pageAt(page).text;
      await onPage(page, pageCount, text);
    }
  }

  Future<void> _forEachAndroidSession(
    File pdfFile,
    CloudAwardPdfPageCallback onPage,
  ) async {
    final opened = await _channel.invokeMapMethod<String, Object?>(
      'openDocSession',
      <String, Object?>{'path': pdfFile.path, 'password': ''},
    );
    final sessionId = opened?['sessionId']?.toString() ?? '';
    final pageCount = (opened?['length'] as num?)?.toInt() ?? 0;
    if (sessionId.isEmpty || pageCount <= 0) {
      throw StateError('CLOUD_AWARD_PDF_SESSION_INVALID');
    }

    try {
      for (var page = 1; page <= pageCount; page += 1) {
        final text = await _channel.invokeMethod<String>(
              'getDocSessionPageText',
              <String, Object?>{'sessionId': sessionId, 'number': page},
            ) ??
            '';
        await onPage(page, pageCount, text);
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
    }
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
