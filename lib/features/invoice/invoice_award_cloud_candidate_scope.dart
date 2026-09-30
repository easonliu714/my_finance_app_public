import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'invoice_award_cloud_artifact_downloader.dart';
import 'invoice_award_cloud_pdf_index.dart';

class CloudAwardCandidateScopedAuthority {
  const CloudAwardCandidateScopedAuthority({
    required this.periodId,
    required this.tierCode,
    required this.officialSourceUri,
    required this.pdfSha256,
    required this.candidateUniverseSha256,
    required this.candidateNumbers,
    required this.matchedInvoiceNumbers,
    this.matchedPageNumbers = const <String, int>{},
  });

  final String periodId;
  final String tierCode;
  final Uri officialSourceUri;
  final String pdfSha256;
  final String candidateUniverseSha256;
  final Set<String> candidateNumbers;
  final Set<String> matchedInvoiceNumbers;
  final Map<String, int> matchedPageNumbers;

  bool covers({
    required String periodId,
    required String tierCode,
    required Iterable<String> invoiceNumbers,
  }) {
    if (this.periodId != periodId || this.tierCode != tierCode) return false;
    final normalized = normalizeCloudCandidateNumbers(invoiceNumbers);
    return normalized.length == candidateNumbers.length &&
        normalized.containsAll(candidateNumbers);
  }
}

Set<String> normalizeCloudCandidateNumbers(Iterable<String> values) =>
    Set<String>.unmodifiable(
      <String>{
        for (final raw in values)
          raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(),
      }.where((value) => RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(value)),
    );

Set<String> cloudCandidateNumbersForAwardPeriod({
  required Iterable<ExistingInvoiceAwardCandidate> candidates,
  required String awardPeriod,
}) =>
    normalizeCloudCandidateNumbers(
      candidates
          .where(
            (candidate) =>
                candidate.awardPeriod == awardPeriod &&
                candidate.identitySource ==
                    ExistingInvoiceAwardIdentitySource.cloudMetadata &&
                candidate.cloudEligibility !=
                    ExistingInvoiceAwardCloudEligibility.ineligible,
          )
          .map((candidate) => candidate.invoiceNumber),
    );

Future<String> cloudCandidateUniverseSha256(Iterable<String> values) async {
  final normalized = normalizeCloudCandidateNumbers(values).toList()..sort();
  final sink = Sha256().newHashSink();
  sink.add(utf8.encode(normalized.join('\n')));
  sink.close();
  final hash = await sink.hash();
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class CloudAwardSortedPdfCandidateMatchResult {
  const CloudAwardSortedPdfCandidateMatchResult({
    required this.pageCount,
    required this.pagesRead,
    required this.matchedInvoiceNumbers,
    this.matchedPageNumbers = const <String, int>{},
  });

  final int pageCount;
  final int pagesRead;
  final Set<String> matchedInvoiceNumbers;
  final Map<String, int> matchedPageNumbers;
}

class CloudAwardSortedPdfCandidateProgress {
  const CloudAwardSortedPdfCandidateProgress({
    required this.candidateIndex,
    required this.candidateCount,
    required this.pageNumber,
    required this.pageCount,
    required this.pagesRead,
  });

  final int candidateIndex;
  final int candidateCount;
  final int pageNumber;
  final int pageCount;
  final int pagesRead;
}

typedef CloudAwardSortedPdfCandidateProgressCallback = void Function(
  CloudAwardSortedPdfCandidateProgress progress,
);

class CloudAwardCandidateLookupCancelled implements Exception {
  const CloudAwardCandidateLookupCancelled();

  @override
  String toString() => 'CLOUD_AWARD_CANDIDATE_LOOKUP_CANCELLED';
}

class CloudAwardCandidateLookupCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const CloudAwardCandidateLookupCancelled();
  }
}

abstract class CloudAwardSortedPdfCandidateLookup {
  const CloudAwardSortedPdfCandidateLookup();

  Future<CloudAwardSortedPdfCandidateMatchResult> findMatches({
    required OfficialCloudAwardDownloadedArtifact artifact,
    required Iterable<String> candidateInvoiceNumbers,
    CloudAwardSortedPdfCandidateProgressCallback? onProgress,
    CloudAwardCandidateLookupCancellation? cancellation,
  });
}

/// Candidate-scoped membership lookup for the very large *sorted* MOF
/// cloud-500 PDF.
///
/// The official 500-dollar list contains millions of numbers. Building a full
/// local index would require tens of thousands of page text extractions.
/// Instead, this implementation opens the validated PDF with native PDFium and
/// binary-searches its globally sorted pages for the exact local candidate
/// universe. Authority is therefore valid only for that exact candidate set.
class PdfiumCloudAwardSortedPdfCandidateLookup
    extends CloudAwardSortedPdfCandidateLookup {
  const PdfiumCloudAwardSortedPdfCandidateLookup();

  static const MethodChannel _channel = MethodChannel('pdf_text');
  static const int candidateBatchSize = 8;

  // Above this real-device boundary, candidate lookup runs in a dedicated
  // Android process with disk-backed scratch. If that worker is killed, the
  // Flutter process survives and no partial candidate authority is promoted.
  static const int crashIsolatedPdfiumPdfBytes = 120 * 1024 * 1024;
  static const Duration workerResultTimeout = Duration(seconds: 120);

  @override
  Future<CloudAwardSortedPdfCandidateMatchResult> findMatches({
    required OfficialCloudAwardDownloadedArtifact artifact,
    required Iterable<String> candidateInvoiceNumbers,
    CloudAwardSortedPdfCandidateProgressCallback? onProgress,
    CloudAwardCandidateLookupCancellation? cancellation,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('CLOUD_AWARD_PDFIUM_ANDROID_ONLY');
    }
    if (!artifact.reference.isApprovedOfficialSource ||
        !artifact.reference.artifactId.toLowerCase().contains('_sorted_')) {
      throw StateError('CLOUD_AWARD_SORTED_PDF_SOURCE_INVALID');
    }

    final candidates = normalizeCloudCandidateNumbers(candidateInvoiceNumbers)
        .toList()
      ..sort();
    if (candidates.isEmpty) {
      return const CloudAwardSortedPdfCandidateMatchResult(
        pageCount: 0,
        pagesRead: 0,
        matchedInvoiceNumbers: <String>{},
      );
    }

    if (artifact.sizeBytes > crashIsolatedPdfiumPdfBytes) {
      return _findMatchesCrashIsolated(
        artifact: artifact,
        candidates: candidates,
        onProgress: onProgress,
        cancellation: cancellation,
      );
    }

    await _channel.invokeMethod<void>('clearLastDiagnostic');
    final matched = <String>{};
    final matchedPageNumbers = <String, int>{};
    final uniquePagesRead = <int>{};
    int? expectedPageCount;

    for (var batchStart = 0;
        batchStart < candidates.length;
        batchStart += candidateBatchSize) {
      cancellation?.throwIfCancelled();
      final batchEnd = min(batchStart + candidateBatchSize, candidates.length);
      String sessionId = '';
      try {
        final opened = await _channel.invokeMapMethod<String, Object?>(
          'openPdfiumSession',
          <String, Object?>{'path': artifact.file.path},
        );
        sessionId = opened?['sessionId']?.toString() ?? '';
        final pageCount = (opened?['length'] as num?)?.toInt() ?? 0;
        if (sessionId.isEmpty || pageCount <= 0) {
          throw StateError('CLOUD_AWARD_PDFIUM_SESSION_INVALID');
        }
        if (expectedPageCount != null && expectedPageCount != pageCount) {
          throw StateError('CLOUD_AWARD_PDFIUM_PAGE_COUNT_CHANGED');
        }
        expectedPageCount = pageCount;
        final pageCache = <int, List<String>>{};

        Future<List<String>> pageTokens(
          int pageNumber, {
          required int candidateIndex,
        }) async {
          cancellation?.throwIfCancelled();
          final cached = pageCache[pageNumber];
          if (cached != null) return cached;
          final text = await _channel.invokeMethod<String>(
                'getPdfiumSessionPageText',
                <String, Object?>{
                  'sessionId': sessionId,
                  'number': pageNumber,
                },
              ) ??
              '';
          cancellation?.throwIfCancelled();
          final tokens = CloudAwardPdfIndexBuilder.extractInvoiceNumbers(text)
              .toSet()
              .toList()
            ..sort();
          if (tokens.isEmpty) {
            throw StateError('CLOUD_AWARD_SORTED_PDF_PAGE_EMPTY');
          }
          pageCache[pageNumber] = List<String>.unmodifiable(tokens);
          uniquePagesRead.add(pageNumber);
          onProgress?.call(
            CloudAwardSortedPdfCandidateProgress(
              candidateIndex: candidateIndex + 1,
              candidateCount: candidates.length,
              pageNumber: pageNumber,
              pageCount: pageCount,
              pagesRead: uniquePagesRead.length,
            ),
          );
          return pageCache[pageNumber]!;
        }

        for (var candidateIndex = batchStart;
            candidateIndex < batchEnd;
            candidateIndex += 1) {
          cancellation?.throwIfCancelled();
          final candidate = candidates[candidateIndex];
          var low = 1;
          var high = pageCount;
          var resolved = false;

          while (low <= high) {
            cancellation?.throwIfCancelled();
            final middle = low + ((high - low) >> 1);
            final tokens = await pageTokens(
              middle,
              candidateIndex: candidateIndex,
            );
            final first = tokens.first;
            final last = tokens.last;
            if (candidate.compareTo(first) < 0) {
              high = middle - 1;
              continue;
            }
            if (candidate.compareTo(last) > 0) {
              low = middle + 1;
              continue;
            }

            if (tokens.contains(candidate)) {
              matched.add(candidate);
              matchedPageNumbers[candidate] = middle;
              resolved = true;
              break;
            }

            // PDFium text extraction can move a boundary token to an adjacent
            // visual page. Probe only the two neighbors; this stays bounded
            // while avoiding a false negative at an official sorted-page edge.
            for (final neighbor in <int>[middle - 1, middle + 1]) {
              if (neighbor < 1 || neighbor > pageCount) continue;
              final neighborTokens = await pageTokens(
                neighbor,
                candidateIndex: candidateIndex,
              );
              if (neighborTokens.contains(candidate)) {
                matched.add(candidate);
                matchedPageNumbers[candidate] = neighbor;
                resolved = true;
                break;
              }
            }
            break;
          }

          if (!resolved && low > high) {
            // Check the final insertion boundary once. This is useful when a
            // page's first/last token was reordered by native text extraction.
            final boundaryPages = <int>{low, high}
                .where((page) => page >= 1 && page <= pageCount);
            for (final page in boundaryPages) {
              final tokens = await pageTokens(
                page,
                candidateIndex: candidateIndex,
              );
              if (tokens.contains(candidate)) {
                matched.add(candidate);
                matchedPageNumbers[candidate] = page;
                break;
              }
            }
          }
        }
      } finally {
        if (sessionId.isNotEmpty) {
          try {
            await _channel.invokeMethod<void>(
              'closePdfiumSession',
              <String, Object?>{'sessionId': sessionId},
            );
          } catch (_) {
            // Cleanup is idempotent; never promote a partial lookup.
          }
        }
      }
    }

    cancellation?.throwIfCancelled();
    await _channel.invokeMethod<void>(
      'markExtractionComplete',
      <String, Object?>{'path': artifact.file.path},
    );
    return CloudAwardSortedPdfCandidateMatchResult(
      pageCount: expectedPageCount ?? 0,
      pagesRead: uniquePagesRead.length,
      matchedInvoiceNumbers: Set<String>.unmodifiable(matched),
      matchedPageNumbers: Map<String, int>.unmodifiable(matchedPageNumbers),
    );
  }

  Future<CloudAwardSortedPdfCandidateMatchResult> _findMatchesCrashIsolated({
    required OfficialCloudAwardDownloadedArtifact artifact,
    required List<String> candidates,
    CloudAwardSortedPdfCandidateProgressCallback? onProgress,
    CloudAwardCandidateLookupCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final expectedCandidateUniverseSha256 =
        await cloudCandidateUniverseSha256(candidates);
    final started = await _channel.invokeMapMethod<String, Object?>(
      'startPdfiumCandidateWorker',
      <String, Object?>{
        'path': artifact.file.path,
        'candidatesJson': jsonEncode(candidates),
        'sourceSha256': artifact.sha256,
        'sourceBytes': artifact.sizeBytes,
        'candidateUniverseSha256': expectedCandidateUniverseSha256,
      },
    );
    final requestId = started?['requestId']?.toString() ?? '';
    final resultPath = started?['resultPath']?.toString() ?? '';
    if (requestId.isEmpty || resultPath.isEmpty) {
      throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_START_INVALID');
    }

    final resultFile = File(resultPath);
    var deadline = DateTime.now().add(workerResultTimeout);
    var lastProgressSignature = '';
    var lastStage = 'STARTED';

    while (DateTime.now().isBefore(deadline)) {
      cancellation?.throwIfCancelled();
      if (await resultFile.exists()) {
        final decoded = jsonDecode(await resultFile.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['request_id']?.toString() != requestId) {
          throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
        }

        final status = decoded['status']?.toString();
        if (status == 'running') {
          final stage = decoded['stage']?.toString() ?? 'RUNNING';
          final candidateIndex =
              (decoded['candidate_index'] as num?)?.toInt() ?? 0;
          final candidateCount =
              (decoded['candidate_count'] as num?)?.toInt() ?? candidates.length;
          final pageNumber = (decoded['page_number'] as num?)?.toInt() ?? 0;
          final pageCount = (decoded['page_count'] as num?)?.toInt() ?? 0;
          final pagesRead = (decoded['pages_read'] as num?)?.toInt() ?? 0;
          final updatedAt = (decoded['updated_at_ms'] as num?)?.toInt() ?? 0;
          final signature =
              '$stage|$candidateIndex|$pageNumber|$pagesRead|$updatedAt';

          if (signature != lastProgressSignature) {
            lastProgressSignature = signature;
            lastStage = stage;
            deadline = DateTime.now().add(workerResultTimeout);
            if (candidateIndex > 0 &&
                candidateCount == candidates.length &&
                pageNumber > 0 &&
                pageCount > 0) {
              onProgress?.call(
                CloudAwardSortedPdfCandidateProgress(
                  candidateIndex: candidateIndex,
                  candidateCount: candidateCount,
                  pageNumber: pageNumber,
                  pageCount: pageCount,
                  pagesRead: pagesRead,
                ),
              );
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }

        try {
          if (status == 'failed') {
            throw StateError(
              decoded['error']?.toString() ??
                  'CLOUD_AWARD_CANDIDATE_WORKER_FAILED',
            );
          }
          if (status != 'complete') {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
          }
          final pageCount = (decoded['page_count'] as num?)?.toInt() ?? 0;
          final pagesRead = (decoded['pages_read'] as num?)?.toInt() ?? 0;
          final candidateCount =
              (decoded['candidate_count'] as num?)?.toInt() ?? -1;
          final sourceSha256 =
              decoded['source_sha256']?.toString().toLowerCase() ?? '';
          final sourceBytes =
              (decoded['source_bytes'] as num?)?.toInt() ?? -1;
          final candidateUniverseSha256 =
              decoded['candidate_universe_sha256']
                      ?.toString()
                      .toLowerCase() ??
                  '';
          final matchedRaw = decoded['matched'];
          final matchedPagesRaw = decoded['matched_pages'];
          if (pageCount <= 0 ||
              pagesRead < 0 ||
              candidateCount != candidates.length ||
              matchedRaw is! List<dynamic> ||
              matchedPagesRaw is! Map<String, dynamic>) {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
          }
          if (sourceSha256 != artifact.sha256.toLowerCase() ||
              sourceBytes != artifact.sizeBytes ||
              candidateUniverseSha256 != expectedCandidateUniverseSha256) {
            throw StateError(
              'CLOUD_AWARD_CANDIDATE_WORKER_PROVENANCE_MISMATCH',
            );
          }
          final matched = normalizeCloudCandidateNumbers(
            matchedRaw.map((value) => value.toString()),
          );
          if (!candidates.toSet().containsAll(matched)) {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH');
          }
          final matchedPageNumbers = <String, int>{};
          for (final entry in matchedPagesRaw.entries) {
            final normalizedKey =
                normalizeCloudCandidateNumbers(<String>[entry.key]);
            final pageNumber = (entry.value as num?)?.toInt() ?? 0;
            if (normalizedKey.length != 1 ||
                !matched.contains(normalizedKey.single) ||
                pageNumber < 1 ||
                pageNumber > pageCount) {
              throw StateError(
                'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH',
              );
            }
            matchedPageNumbers[normalizedKey.single] = pageNumber;
          }
          if (matchedPageNumbers.length != matched.length) {
            throw StateError(
              'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH',
            );
          }
          return CloudAwardSortedPdfCandidateMatchResult(
            pageCount: pageCount,
            pagesRead: pagesRead,
            matchedInvoiceNumbers: matched,
            matchedPageNumbers:
                Map<String, int>.unmodifiable(matchedPageNumbers),
          );
        } finally {
          try {
            if (await resultFile.exists()) await resultFile.delete();
          } catch (_) {
            // Best-effort transient worker-result cleanup only.
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final safeStage = lastStage.replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
    throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_TIMEOUT_$safeStage');
  }

}
