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
    this.stage = 'PDFIUM_CANDIDATE_SEARCH',
    this.elapsed = Duration.zero,
    this.estimatedRemaining,
    this.sourceBytesRead = 0,
    this.sourceBytesTotal = 0,
  });

  final int candidateIndex;
  final int candidateCount;
  final int pageNumber;
  final int pageCount;
  final int pagesRead;
  final String stage;
  final Duration elapsed;
  final Duration? estimatedRemaining;
  final int sourceBytesRead;
  final int sourceBytesTotal;
}

typedef CloudAwardSortedPdfCandidateProgressCallback = void Function(
  CloudAwardSortedPdfCandidateProgress progress,
);

/// An invalid future timestamp must trigger the same liveness supervision
/// as an expired native heartbeat; neither is evidence of fresh progress.
bool cloudAwardNativeHeartbeatNeedsProbe(Duration heartbeatAge) {
  return heartbeatAge.isNegative ||
      heartbeatAge > PdfiumCloudAwardSortedPdfCandidateLookup
          .workerHeartbeatProbeAfter;
}

/// UI-only status classification. A stale/missing native heartbeat is not
/// evidence of additional pages, PDF opening progress, or task completion.
String cloudAwardNativeHeartbeatDisplayStage({
  required String nativeStage,
  required Duration heartbeatAge,
}) {
  if (cloudAwardNativeHeartbeatNeedsProbe(heartbeatAge)) {
    return 'PLATFORM_WORKER_HEARTBEAT_STALE';
  }
  return nativeStage;
}

/// Validate only Running fields already emitted by the current Kotlin
/// writeRunning() implementation. This does NOT prove source PDF SHA256 or
/// candidate-universe SHA256, which are absent from native Running payloads.
String? cloudAwardNativeRunningEnvelopeViolation({
  required Map<String, dynamic> running,
  required int expectedCandidateCount,
  required int expectedSourceBytes,
  required int priorWorkerPid,
  required DateTime observedAt,
  DateTime? priorHeartbeatAt,
}) {
  if (running['status'] != 'running' ||
      running['engine'] != 'android-platform-pdfrenderer-candidate-search') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_ENVELOPE_INVALID';
  }
  final pid = running['worker_pid'];
  if (pid is! int || pid <= 0 ||
      (priorWorkerPid > 0 && pid != priorWorkerPid)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PID_MISMATCH';
  }
  final count = running['candidate_count'];
  final index = running['candidate_index'];
  if (count is! int || count != expectedCandidateCount ||
      index is! int || index < 0 || index > count) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CANDIDATE_MISMATCH';
  }
  final total = running['source_bytes_total'];
  final read = running['source_bytes_read'];
  if (total is! int || total != expectedSourceBytes ||
      read is! int || read < 0 || read > total) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_BYTES_MISMATCH';
  }
  // Native writeRunning() has six known stages. A forged or malformed
  // stage/page tuple must never become visible progress or ETA authority.
  const allowedStages = <String>{
    'PLATFORM_SOURCE_SHA256',
    'PLATFORM_RENDERER_OPEN_BEGIN',
    'PLATFORM_RENDERER_OPEN_WAIT',
    'PLATFORM_RENDERER_OPEN_OK',
    'PLATFORM_RENDERER_PAGE_BEGIN',
    'PLATFORM_RENDERER_CANDIDATE_SEARCH',
  };
  final stage = running['stage'];
  if (stage is! String || !allowedStages.contains(stage)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_INVALID';
  }
  final pageNumber = running['page_number'];
  final pageCount = running['page_count'];
  final pagesRead = running['pages_read'];
  final stageElapsedMs = running['stage_elapsed_ms'];
  if (pageNumber is! int ||
      pageCount is! int ||
      pagesRead is! int ||
      stageElapsedMs is! int ||
      stageElapsedMs < 0 ||
      pageCount < 0 ||
      pageNumber < 0 ||
      pageNumber > pageCount ||
      pagesRead < 0 ||
      pagesRead > pageCount) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_EVIDENCE_INVALID';
  }
  if (stage == 'PLATFORM_SOURCE_SHA256') {
    if (index != 0 || pageNumber != 0 || pageCount != 0 || pagesRead != 0) {
      return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID';
    }
  } else if (stage == 'PLATFORM_RENDERER_OPEN_BEGIN' ||
      stage == 'PLATFORM_RENDERER_OPEN_WAIT') {
    if (index != 0 ||
        pageNumber != 0 ||
        pageCount != 0 ||
        pagesRead != 0 ||
        read != total) {
      return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID';
    }
  } else if (stage == 'PLATFORM_RENDERER_OPEN_OK') {
    if (index != 0 ||
        pageNumber != 0 ||
        pageCount <= 0 ||
        pagesRead != 0 ||
        read != total) {
      return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID';
    }
  } else if (index <= 0 ||
      pageNumber <= 0 ||
      pageCount <= 0 ||
      read != total ||
      (stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH' && pagesRead == 0)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_STAGE_PROGRESS_INVALID';
  }
  final updatedAtMs = running['updated_at_ms'];
  if (updatedAtMs is! int || updatedAtMs <= 0 ||
      updatedAtMs > observedAt.millisecondsSinceEpoch ||
      (priorHeartbeatAt != null &&
          updatedAtMs < priorHeartbeatAt.millisecondsSinceEpoch)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_CLOCK_INVALID';
  }
  return null;
}

/// Validate native COMPLETE identity before accepting any PDF match result.
/// This is metadata continuity only, not a global negative-search proof.
String? cloudAwardNativeCompleteTerminalViolation({
  required Map<String, dynamic> terminal,
  required int priorWorkerPid,
  required DateTime observedAt,
  required DateTime priorHeartbeatAt,
}) {
  if (terminal['engine'] != 'android-platform-pdfrenderer-candidate-search') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH';
  }
  if (terminal['stage'] != 'PLATFORM_RENDERER_COMPLETE') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_STAGE_MISMATCH';
  }
  final workerPid = terminal['worker_pid'];
  if (workerPid is! int || workerPid <= 0) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_PID_MISSING';
  }
  if (priorWorkerPid > 0 && workerPid != priorWorkerPid) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_PID_MISMATCH';
  }
  final updatedAtMs = terminal['updated_at_ms'];
  if (updatedAtMs is! int ||
      updatedAtMs <= 0 ||
      updatedAtMs > observedAt.millisecondsSinceEpoch ||
      updatedAtMs < priorHeartbeatAt.millisecondsSinceEpoch) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_TERMINAL_CLOCK_INVALID';
  }
  return null;
}

/// Reject lossy numeric coercion in native COMPLETE evidence. A fractional,
/// textual, or boolean JSON value must not become an authoritative page,
/// candidate count, or source byte count through num.toInt().
/// This is shape validation only, not global negative-search coverage.
String? cloudAwardNativeCompleteNumericEvidenceViolation({
  required Map<String, dynamic> terminal,
}) {
  for (final field in <String>[
    'page_count',
    'pages_read',
    'candidate_count',
    'source_bytes',
  ]) {
    if (terminal[field] is! int) {
      return 'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID';
    }
  }
  final matchedPages = terminal['matched_pages'];
  if (matchedPages is! Map<String, dynamic>) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID';
  }
  for (final page in matchedPages.values) {
    if (page is! int) {
      return 'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH';
    }
  }
  return null;
}

/// Validate native COMPLETE matched identities before lossy normalization.
/// Invalid, duplicated, non-string or unrequested values cannot be silently
/// discarded and then misrepresented as an all-positive candidate result.
/// Empty or partial sets remain UNKNOWN; this is not global negative proof.
String? cloudAwardNativeCompleteMatchedIdentityViolation({
  required Object? matchedRaw,
  required Object? matchedPagesRaw,
  required Set<String> expectedCandidates,
}) {
  if (matchedRaw is! List<dynamic> ||
      matchedPagesRaw is! Map<String, dynamic>) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID';
  }
  final seen = <String>{};
  for (final value in matchedRaw) {
    if (value is! String ||
        !RegExp(r'^[A-Z]{2}[0-9]{8}
/// This does not establish native PID/stage custody or durable retention.
String? cloudAwardNativeFailedTerminalViolation({
  required Map<String, dynamic> terminal,
  required DateTime observedAt,
  DateTime? priorHeartbeatAt,
}) {
  if (terminal['status'] != 'failed') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_STATUS_INVALID';
  }
  if (terminal['engine'] != 'android-platform-pdfrenderer-candidate-search') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH';
  }
  final updatedAtMs = terminal['updated_at_ms'];
  if (updatedAtMs is! int ||
      updatedAtMs <= 0 ||
      updatedAtMs > observedAt.millisecondsSinceEpoch ||
      (priorHeartbeatAt != null &&
          updatedAtMs < priorHeartbeatAt.millisecondsSinceEpoch)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_CLOCK_INVALID';
  }
  final error = terminal['error'];
  if (error is! String ||
      error.length > 128 ||
      !RegExp(r'^PLATFORM_[A-Z0-9_]+(?::[A-Za-z][A-Za-z0-9_$]{0,79})?$')
          .hasMatch(error)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_ERROR_INVALID';
  }
  return null;
}

/// Preserve native failure, invalid-terminal, and partial/unknown search
/// evidence for diagnosis. Only a fully validated, all-positive COMPLETE
/// result is disposable. This does not guarantee native atomic publication,
/// a retention quota, or persistent forensic custody.
Future<void> cloudAwardCleanupNativeTerminalEvidence({
  required File resultFile,
  required String? terminalStatus,
  required bool terminalValidated,
  required int candidateCount,
  required int matchedCount,
}) async {
  if (terminalStatus != 'complete' ||
      !terminalValidated ||
      candidateCount <= 0 ||
      matchedCount != candidateCount) {
    return;
  }
  try {
    if (await resultFile.exists()) await resultFile.delete();
  } catch (_) {
    // Successful result cleanup is best-effort; never mask the lookup.
  }
}

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
/// Instead, this implementation binary-searches globally sorted pages for the
/// exact local candidate universe. <=120 MiB keeps the proven in-process PDFium
/// path; >120 MiB uses Android platform PdfRenderer in a dedicated process on
/// API 35+, because owner evidence proved third-party PDFium crashes natively
/// on the exact 115-07-08 87,000-page source.
/// Authority is therefore valid only for that exact candidate set.
class PdfiumCloudAwardSortedPdfCandidateLookup
    extends CloudAwardSortedPdfCandidateLookup {
  const PdfiumCloudAwardSortedPdfCandidateLookup();

  static const MethodChannel _channel = MethodChannel('pdf_text');
  static const int candidateBatchSize = 8;

  // Above this real-device boundary, candidate lookup runs in a dedicated
  // Android process with disk-backed scratch. If that worker is killed, the
  // Flutter process survives and no partial candidate authority is promoted.
  static const int crashIsolatedPdfiumPdfBytes = 120 * 1024 * 1024;
  // A stale worker-file heartbeat triggers an OS liveness probe, not a
  // timeout or evidence of new processing. Report an explicit STALE status
  // while native progress cannot be verified, even if the PID is alive.
  static const Duration workerHeartbeatProbeAfter = Duration(seconds: 15);
  static const Duration workerLivenessProbeEvery = Duration(seconds: 2);
  static const Duration staleHeartbeatNoticeEvery = Duration(seconds: 10);

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
      'startPlatformCandidateWorker',
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
    final workerStartedAt = DateTime.now();
    DateTime lastHeartbeatAt = workerStartedAt;
    DateTime? candidateSearchStartedAt;
    var lastProgressSignature = '';
    var lastStage = 'STARTED';
    var lastWorkerPid = 0;
    var lastLivenessProbeAt = workerStartedAt;
    var lastStaleNoticeAt = workerStartedAt;

    while (true) {
      cancellation?.throwIfCancelled();
      if (await resultFile.exists()) {
        Map<String, dynamic>? decoded;
        try {
          final rawResult = await resultFile.readAsString();
          final parsed = jsonDecode(rawResult);
          if (parsed is Map<String, dynamic>) {
            decoded = parsed;
          }
        } on FileSystemException {
          // Producer-side atomic replacement can create a sub-millisecond
          // exists/read race. Treat it as transient, never as authority failure.
        } on FormatException {
          // A fallback write can briefly expose partial JSON. Retry safely.
        }
        if (decoded == null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        if (decoded['request_id']?.toString() != requestId) {
          throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
        }

        final status = decoded['status']?.toString();
        if (status == 'running') {
          final runningViolation = cloudAwardNativeRunningEnvelopeViolation(
            running: decoded,
            expectedCandidateCount: candidates.length,
            expectedSourceBytes: artifact.sizeBytes,
            priorWorkerPid: lastWorkerPid,
            observedAt: DateTime.now(),
            priorHeartbeatAt:
                lastProgressSignature.isEmpty ? null : lastHeartbeatAt,
          );
          if (runningViolation != null) {
            throw StateError(runningViolation);
          }
          final stage = decoded['stage']?.toString() ?? 'RUNNING';
          final candidateIndex =
              (decoded['candidate_index'] as num?)?.toInt() ?? 0;
          final candidateCount =
              (decoded['candidate_count'] as num?)?.toInt() ?? candidates.length;
          final pageNumber = (decoded['page_number'] as num?)?.toInt() ?? 0;
          final engine = decoded['engine']?.toString() ?? '';
          if (engine != 'android-platform-pdfrenderer-candidate-search') {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH');
          }
          final pageCount = (decoded['page_count'] as num?)?.toInt() ?? 0;
          final pagesRead = (decoded['pages_read'] as num?)?.toInt() ?? 0;
          final sourceBytesRead =
              (decoded['source_bytes_read'] as num?)?.toInt() ?? 0;
          final sourceBytesTotal =
              (decoded['source_bytes_total'] as num?)?.toInt() ?? 0;
          final updatedAt = (decoded['updated_at_ms'] as num?)?.toInt() ?? 0;
          final stageElapsedMs =
              (decoded['stage_elapsed_ms'] as num?)?.toInt() ?? 0;
          final workerPid = (decoded['worker_pid'] as num?)?.toInt() ?? 0;
          if (workerPid > 0) lastWorkerPid = workerPid;
          if (updatedAt > 0) {
            lastHeartbeatAt =
                DateTime.fromMillisecondsSinceEpoch(updatedAt);
          }
          final signature =
              '$stage|$candidateIndex|$pageNumber|$pagesRead|$updatedAt';

          if (signature != lastProgressSignature) {
            lastProgressSignature = signature;
            lastStage = stage;
            final now = DateTime.now();
            // Never display an invalid native clock value as fresh progress.
            final displayStage = cloudAwardNativeHeartbeatDisplayStage(
              nativeStage: stage,
              heartbeatAge: now.difference(lastHeartbeatAt),
            );
            final elapsed = now.difference(workerStartedAt);
            Duration? eta;

            if (stage == 'PLATFORM_SOURCE_SHA256' &&
                sourceBytesRead > 0 &&
                sourceBytesTotal > sourceBytesRead &&
                elapsed.inMilliseconds > 0) {
              final remainingRatio =
                  (sourceBytesTotal - sourceBytesRead) / sourceBytesRead;
              eta = Duration(
                milliseconds:
                    (elapsed.inMilliseconds * remainingRatio).round(),
              );
            } else if ((stage == 'PLATFORM_RENDERER_PAGE_BEGIN' ||
                    stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') &&
                candidateIndex > 0 &&
                candidateCount > 0) {
              candidateSearchStartedAt ??= now;
              final completed = max(candidateIndex - 1, 0);
              if (completed > 0) {
                final searchElapsed =
                    now.difference(candidateSearchStartedAt);
                final remaining = max(candidateCount - completed, 0);
                eta = Duration(
                  milliseconds:
                      (searchElapsed.inMilliseconds * remaining / completed)
                          .round(),
                );
              }
            }

            onProgress?.call(
              CloudAwardSortedPdfCandidateProgress(
                candidateIndex: candidateIndex,
                candidateCount: candidateCount,
                pageNumber: pageNumber,
                pageCount: pageCount,
                pagesRead: pagesRead,
                stage: displayStage,
                elapsed: stageElapsedMs > 0
                    ? Duration(milliseconds: stageElapsedMs)
                    : elapsed,
                estimatedRemaining:
                    displayStage == 'PLATFORM_WORKER_HEARTBEAT_STALE'
                        ? null
                        : eta,
                sourceBytesRead: sourceBytesRead,
                sourceBytesTotal: sourceBytesTotal,
              ),
            );
          }

          final now = DateTime.now();
          if (cloudAwardNativeHeartbeatNeedsProbe(
              now.difference(lastHeartbeatAt))) {
            if (lastWorkerPid <= 0) {
              throw StateError(
                'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_PID_MISSING',
              );
            }
            if (now.difference(lastLivenessProbeAt) >=
                workerLivenessProbeEvery) {
              lastLivenessProbeAt = now;
              final liveness =
                  await _channel.invokeMapMethod<String, Object?>(
                'getPlatformCandidateWorkerLiveness',
                <String, Object?>{'workerPid': lastWorkerPid},
              );
              if (liveness?['alive'] != true) {
                final safeStage =
                    lastStage.replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
                final exitReasonCode =
                    (liveness?['exitReasonCode'] as num?)?.toInt() ?? -1;
                final exitReasonSuffix = exitReasonCode < 0
                    ? ''
                    : '_OS_EXIT_$exitReasonCode';
                throw StateError(
                  'CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_'
                  '$safeStage$exitReasonSuffix',
                );
              }
            }
            if (now.difference(lastStaleNoticeAt) >=
                staleHeartbeatNoticeEvery) {
              lastStaleNoticeAt = now;
              onProgress?.call(
                CloudAwardSortedPdfCandidateProgress(
                  candidateIndex: candidateIndex,
                  candidateCount: candidateCount,
                  pageNumber: pageNumber,
                  pageCount: pageCount,
                  pagesRead: pagesRead,
                  stage: cloudAwardNativeHeartbeatDisplayStage(
                    nativeStage: stage,
                    heartbeatAge: now.difference(lastHeartbeatAt),
                  ),
                  elapsed: now.difference(workerStartedAt),
                  estimatedRemaining: null,
                  sourceBytesRead: sourceBytesRead,
                  sourceBytesTotal: sourceBytesTotal,
                ),
              );
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }

        // A native terminal is retained unless it has passed all Dart
        // checks AND every candidate has a positive, page-backed match.
        // Failed, malformed, and partial/unknown results remain available
        // for native failure investigation; this is not durable custody.
        var terminalValidated = false;
        var terminalMatchedCount = -1;
        try {
          if (status == 'failed') {
            // Reject forged or malformed native FAILED metadata before
            // surfacing the bounded native error code to the caller.
            final failureViolation = cloudAwardNativeFailedTerminalViolation(
              terminal: decoded,
              observedAt: DateTime.now(),
              priorHeartbeatAt:
                  lastProgressSignature.isEmpty ? null : lastHeartbeatAt,
            );
            if (failureViolation != null) {
              throw StateError(failureViolation);
            }
            throw StateError(decoded['error'] as String);
          }
          if (status != 'complete') {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
          }
          // Native terminal metadata is not inferred from PID liveness.
          final terminalViolation = cloudAwardNativeCompleteTerminalViolation(
            terminal: decoded,
            priorWorkerPid: lastWorkerPid,
            observedAt: DateTime.now(),
            priorHeartbeatAt: lastHeartbeatAt,
          );
          if (terminalViolation != null) {
            throw StateError(terminalViolation);
          }
          // Fail closed before any lossy num.toInt() conversion can
          // turn fractional native evidence into apparently valid authority.
          final numericViolation =
              cloudAwardNativeCompleteNumericEvidenceViolation(
            terminal: decoded,
          );
          if (numericViolation != null) {
            throw StateError(numericViolation);
          }
          final pageCount = decoded['page_count'] as int;
          final pagesRead = decoded['pages_read'] as int;
          final candidateCount = decoded['candidate_count'] as int;
          final sourceSha256 =
              decoded['source_sha256']?.toString().toLowerCase() ?? '';
          final sourceBytes = decoded['source_bytes'] as int;
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
          // Check native JSON identities before normalization can discard
          // malformed or duplicate entries and fabricate full coverage.
          final matchIdentityViolation =
              cloudAwardNativeCompleteMatchedIdentityViolation(
            matchedRaw: matchedRaw,
            matchedPagesRaw: matchedPagesRaw,
            expectedCandidates: candidates.toSet(),
          );
          if (matchIdentityViolation != null) {
            throw StateError(matchIdentityViolation);
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
            final pageNumber = entry.value as int;
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
          final verifiedResult = CloudAwardSortedPdfCandidateMatchResult(
            pageCount: pageCount,
            pagesRead: pagesRead,
            matchedInvoiceNumbers: matched,
            matchedPageNumbers:
                Map<String, int>.unmodifiable(matchedPageNumbers),
          );
          terminalValidated = true;
          terminalMatchedCount = matched.length;
          return verifiedResult;
        } finally {
          await cloudAwardCleanupNativeTerminalEvidence(
            resultFile: resultFile,
            terminalStatus: status,
            terminalValidated: terminalValidated,
            candidateCount: candidates.length,
            matchedCount: terminalMatchedCount,
          );
        }
      }
      final now = DateTime.now();
      if (cloudAwardNativeHeartbeatNeedsProbe(
              now.difference(lastHeartbeatAt)) &&
          lastWorkerPid > 0 &&
          now.difference(lastLivenessProbeAt) >= workerLivenessProbeEvery) {
        lastLivenessProbeAt = now;
        final liveness = await _channel.invokeMapMethod<String, Object?>(
          'getPlatformCandidateWorkerLiveness',
          <String, Object?>{'workerPid': lastWorkerPid},
        );
        if (liveness?['alive'] != true) {
          final safeStage =
              lastStage.replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
          final exitReasonCode =
              (liveness?['exitReasonCode'] as num?)?.toInt() ?? -1;
          final exitReasonSuffix =
              exitReasonCode < 0 ? '' : '_OS_EXIT_$exitReasonCode';
          throw StateError(
            'CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_'
            '$safeStage$exitReasonSuffix',
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

}
).hasMatch(value) ||
        !expectedCandidates.contains(value) ||
        !seen.add(value)) {
      return 'CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH';
    }
  }
  if (matchedPagesRaw.length != seen.length ||
      !seen.containsAll(matchedPagesRaw.keys)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH';
  }
  return null;
}

/// Validate only fields currently emitted by Kotlin's FAILED publisher.
/// This does not establish native PID/stage custody or durable retention.
String? cloudAwardNativeFailedTerminalViolation({
  required Map<String, dynamic> terminal,
  required DateTime observedAt,
  DateTime? priorHeartbeatAt,
}) {
  if (terminal['status'] != 'failed') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_STATUS_INVALID';
  }
  if (terminal['engine'] != 'android-platform-pdfrenderer-candidate-search') {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH';
  }
  final updatedAtMs = terminal['updated_at_ms'];
  if (updatedAtMs is! int ||
      updatedAtMs <= 0 ||
      updatedAtMs > observedAt.millisecondsSinceEpoch ||
      (priorHeartbeatAt != null &&
          updatedAtMs < priorHeartbeatAt.millisecondsSinceEpoch)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_CLOCK_INVALID';
  }
  final error = terminal['error'];
  if (error is! String ||
      error.length > 128 ||
      !RegExp(r'^PLATFORM_[A-Z0-9_]+(?::[A-Za-z][A-Za-z0-9_$]{0,79})?$')
          .hasMatch(error)) {
    return 'CLOUD_AWARD_CANDIDATE_WORKER_FAILED_ERROR_INVALID';
  }
  return null;
}

/// Preserve native failure, invalid-terminal, and partial/unknown search
/// evidence for diagnosis. Only a fully validated, all-positive COMPLETE
/// result is disposable. This does not guarantee native atomic publication,
/// a retention quota, or persistent forensic custody.
Future<void> cloudAwardCleanupNativeTerminalEvidence({
  required File resultFile,
  required String? terminalStatus,
  required bool terminalValidated,
  required int candidateCount,
  required int matchedCount,
}) async {
  if (terminalStatus != 'complete' ||
      !terminalValidated ||
      candidateCount <= 0 ||
      matchedCount != candidateCount) {
    return;
  }
  try {
    if (await resultFile.exists()) await resultFile.delete();
  } catch (_) {
    // Successful result cleanup is best-effort; never mask the lookup.
  }
}

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
/// Instead, this implementation binary-searches globally sorted pages for the
/// exact local candidate universe. <=120 MiB keeps the proven in-process PDFium
/// path; >120 MiB uses Android platform PdfRenderer in a dedicated process on
/// API 35+, because owner evidence proved third-party PDFium crashes natively
/// on the exact 115-07-08 87,000-page source.
/// Authority is therefore valid only for that exact candidate set.
class PdfiumCloudAwardSortedPdfCandidateLookup
    extends CloudAwardSortedPdfCandidateLookup {
  const PdfiumCloudAwardSortedPdfCandidateLookup();

  static const MethodChannel _channel = MethodChannel('pdf_text');
  static const int candidateBatchSize = 8;

  // Above this real-device boundary, candidate lookup runs in a dedicated
  // Android process with disk-backed scratch. If that worker is killed, the
  // Flutter process survives and no partial candidate authority is promoted.
  static const int crashIsolatedPdfiumPdfBytes = 120 * 1024 * 1024;
  // A stale worker-file heartbeat triggers an OS liveness probe, not a
  // timeout or evidence of new processing. Report an explicit STALE status
  // while native progress cannot be verified, even if the PID is alive.
  static const Duration workerHeartbeatProbeAfter = Duration(seconds: 15);
  static const Duration workerLivenessProbeEvery = Duration(seconds: 2);
  static const Duration staleHeartbeatNoticeEvery = Duration(seconds: 10);

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
      'startPlatformCandidateWorker',
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
    final workerStartedAt = DateTime.now();
    DateTime lastHeartbeatAt = workerStartedAt;
    DateTime? candidateSearchStartedAt;
    var lastProgressSignature = '';
    var lastStage = 'STARTED';
    var lastWorkerPid = 0;
    var lastLivenessProbeAt = workerStartedAt;
    var lastStaleNoticeAt = workerStartedAt;

    while (true) {
      cancellation?.throwIfCancelled();
      if (await resultFile.exists()) {
        Map<String, dynamic>? decoded;
        try {
          final rawResult = await resultFile.readAsString();
          final parsed = jsonDecode(rawResult);
          if (parsed is Map<String, dynamic>) {
            decoded = parsed;
          }
        } on FileSystemException {
          // Producer-side atomic replacement can create a sub-millisecond
          // exists/read race. Treat it as transient, never as authority failure.
        } on FormatException {
          // A fallback write can briefly expose partial JSON. Retry safely.
        }
        if (decoded == null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        if (decoded['request_id']?.toString() != requestId) {
          throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
        }

        final status = decoded['status']?.toString();
        if (status == 'running') {
          final runningViolation = cloudAwardNativeRunningEnvelopeViolation(
            running: decoded,
            expectedCandidateCount: candidates.length,
            expectedSourceBytes: artifact.sizeBytes,
            priorWorkerPid: lastWorkerPid,
            observedAt: DateTime.now(),
            priorHeartbeatAt:
                lastProgressSignature.isEmpty ? null : lastHeartbeatAt,
          );
          if (runningViolation != null) {
            throw StateError(runningViolation);
          }
          final stage = decoded['stage']?.toString() ?? 'RUNNING';
          final candidateIndex =
              (decoded['candidate_index'] as num?)?.toInt() ?? 0;
          final candidateCount =
              (decoded['candidate_count'] as num?)?.toInt() ?? candidates.length;
          final pageNumber = (decoded['page_number'] as num?)?.toInt() ?? 0;
          final engine = decoded['engine']?.toString() ?? '';
          if (engine != 'android-platform-pdfrenderer-candidate-search') {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_ENGINE_MISMATCH');
          }
          final pageCount = (decoded['page_count'] as num?)?.toInt() ?? 0;
          final pagesRead = (decoded['pages_read'] as num?)?.toInt() ?? 0;
          final sourceBytesRead =
              (decoded['source_bytes_read'] as num?)?.toInt() ?? 0;
          final sourceBytesTotal =
              (decoded['source_bytes_total'] as num?)?.toInt() ?? 0;
          final updatedAt = (decoded['updated_at_ms'] as num?)?.toInt() ?? 0;
          final stageElapsedMs =
              (decoded['stage_elapsed_ms'] as num?)?.toInt() ?? 0;
          final workerPid = (decoded['worker_pid'] as num?)?.toInt() ?? 0;
          if (workerPid > 0) lastWorkerPid = workerPid;
          if (updatedAt > 0) {
            lastHeartbeatAt =
                DateTime.fromMillisecondsSinceEpoch(updatedAt);
          }
          final signature =
              '$stage|$candidateIndex|$pageNumber|$pagesRead|$updatedAt';

          if (signature != lastProgressSignature) {
            lastProgressSignature = signature;
            lastStage = stage;
            final now = DateTime.now();
            // Never display an invalid native clock value as fresh progress.
            final displayStage = cloudAwardNativeHeartbeatDisplayStage(
              nativeStage: stage,
              heartbeatAge: now.difference(lastHeartbeatAt),
            );
            final elapsed = now.difference(workerStartedAt);
            Duration? eta;

            if (stage == 'PLATFORM_SOURCE_SHA256' &&
                sourceBytesRead > 0 &&
                sourceBytesTotal > sourceBytesRead &&
                elapsed.inMilliseconds > 0) {
              final remainingRatio =
                  (sourceBytesTotal - sourceBytesRead) / sourceBytesRead;
              eta = Duration(
                milliseconds:
                    (elapsed.inMilliseconds * remainingRatio).round(),
              );
            } else if ((stage == 'PLATFORM_RENDERER_PAGE_BEGIN' ||
                    stage == 'PLATFORM_RENDERER_CANDIDATE_SEARCH') &&
                candidateIndex > 0 &&
                candidateCount > 0) {
              candidateSearchStartedAt ??= now;
              final completed = max(candidateIndex - 1, 0);
              if (completed > 0) {
                final searchElapsed =
                    now.difference(candidateSearchStartedAt);
                final remaining = max(candidateCount - completed, 0);
                eta = Duration(
                  milliseconds:
                      (searchElapsed.inMilliseconds * remaining / completed)
                          .round(),
                );
              }
            }

            onProgress?.call(
              CloudAwardSortedPdfCandidateProgress(
                candidateIndex: candidateIndex,
                candidateCount: candidateCount,
                pageNumber: pageNumber,
                pageCount: pageCount,
                pagesRead: pagesRead,
                stage: displayStage,
                elapsed: stageElapsedMs > 0
                    ? Duration(milliseconds: stageElapsedMs)
                    : elapsed,
                estimatedRemaining:
                    displayStage == 'PLATFORM_WORKER_HEARTBEAT_STALE'
                        ? null
                        : eta,
                sourceBytesRead: sourceBytesRead,
                sourceBytesTotal: sourceBytesTotal,
              ),
            );
          }

          final now = DateTime.now();
          if (cloudAwardNativeHeartbeatNeedsProbe(
              now.difference(lastHeartbeatAt))) {
            if (lastWorkerPid <= 0) {
              throw StateError(
                'CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_PID_MISSING',
              );
            }
            if (now.difference(lastLivenessProbeAt) >=
                workerLivenessProbeEvery) {
              lastLivenessProbeAt = now;
              final liveness =
                  await _channel.invokeMapMethod<String, Object?>(
                'getPlatformCandidateWorkerLiveness',
                <String, Object?>{'workerPid': lastWorkerPid},
              );
              if (liveness?['alive'] != true) {
                final safeStage =
                    lastStage.replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
                final exitReasonCode =
                    (liveness?['exitReasonCode'] as num?)?.toInt() ?? -1;
                final exitReasonSuffix = exitReasonCode < 0
                    ? ''
                    : '_OS_EXIT_$exitReasonCode';
                throw StateError(
                  'CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_'
                  '$safeStage$exitReasonSuffix',
                );
              }
            }
            if (now.difference(lastStaleNoticeAt) >=
                staleHeartbeatNoticeEvery) {
              lastStaleNoticeAt = now;
              onProgress?.call(
                CloudAwardSortedPdfCandidateProgress(
                  candidateIndex: candidateIndex,
                  candidateCount: candidateCount,
                  pageNumber: pageNumber,
                  pageCount: pageCount,
                  pagesRead: pagesRead,
                  stage: cloudAwardNativeHeartbeatDisplayStage(
                    nativeStage: stage,
                    heartbeatAge: now.difference(lastHeartbeatAt),
                  ),
                  elapsed: now.difference(workerStartedAt),
                  estimatedRemaining: null,
                  sourceBytesRead: sourceBytesRead,
                  sourceBytesTotal: sourceBytesTotal,
                ),
              );
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }

        // A native terminal is retained unless it has passed all Dart
        // checks AND every candidate has a positive, page-backed match.
        // Failed, malformed, and partial/unknown results remain available
        // for native failure investigation; this is not durable custody.
        var terminalValidated = false;
        var terminalMatchedCount = -1;
        try {
          if (status == 'failed') {
            // Reject forged or malformed native FAILED metadata before
            // surfacing the bounded native error code to the caller.
            final failureViolation = cloudAwardNativeFailedTerminalViolation(
              terminal: decoded,
              observedAt: DateTime.now(),
              priorHeartbeatAt:
                  lastProgressSignature.isEmpty ? null : lastHeartbeatAt,
            );
            if (failureViolation != null) {
              throw StateError(failureViolation);
            }
            throw StateError(decoded['error'] as String);
          }
          if (status != 'complete') {
            throw StateError('CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID');
          }
          // Native terminal metadata is not inferred from PID liveness.
          final terminalViolation = cloudAwardNativeCompleteTerminalViolation(
            terminal: decoded,
            priorWorkerPid: lastWorkerPid,
            observedAt: DateTime.now(),
            priorHeartbeatAt: lastHeartbeatAt,
          );
          if (terminalViolation != null) {
            throw StateError(terminalViolation);
          }
          // Fail closed before any lossy num.toInt() conversion can
          // turn fractional native evidence into apparently valid authority.
          final numericViolation =
              cloudAwardNativeCompleteNumericEvidenceViolation(
            terminal: decoded,
          );
          if (numericViolation != null) {
            throw StateError(numericViolation);
          }
          final pageCount = decoded['page_count'] as int;
          final pagesRead = decoded['pages_read'] as int;
          final candidateCount = decoded['candidate_count'] as int;
          final sourceSha256 =
              decoded['source_sha256']?.toString().toLowerCase() ?? '';
          final sourceBytes = decoded['source_bytes'] as int;
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
            final pageNumber = entry.value as int;
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
          final verifiedResult = CloudAwardSortedPdfCandidateMatchResult(
            pageCount: pageCount,
            pagesRead: pagesRead,
            matchedInvoiceNumbers: matched,
            matchedPageNumbers:
                Map<String, int>.unmodifiable(matchedPageNumbers),
          );
          terminalValidated = true;
          terminalMatchedCount = matched.length;
          return verifiedResult;
        } finally {
          await cloudAwardCleanupNativeTerminalEvidence(
            resultFile: resultFile,
            terminalStatus: status,
            terminalValidated: terminalValidated,
            candidateCount: candidates.length,
            matchedCount: terminalMatchedCount,
          );
        }
      }
      final now = DateTime.now();
      if (cloudAwardNativeHeartbeatNeedsProbe(
              now.difference(lastHeartbeatAt)) &&
          lastWorkerPid > 0 &&
          now.difference(lastLivenessProbeAt) >= workerLivenessProbeEvery) {
        lastLivenessProbeAt = now;
        final liveness = await _channel.invokeMapMethod<String, Object?>(
          'getPlatformCandidateWorkerLiveness',
          <String, Object?>{'workerPid': lastWorkerPid},
        );
        if (liveness?['alive'] != true) {
          final safeStage =
              lastStage.replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
          final exitReasonCode =
              (liveness?['exitReasonCode'] as num?)?.toInt() ?? -1;
          final exitReasonSuffix =
              exitReasonCode < 0 ? '' : '_OS_EXIT_$exitReasonCode';
          throw StateError(
            'CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_'
            '$safeStage$exitReasonSuffix',
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

}
