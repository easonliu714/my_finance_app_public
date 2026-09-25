import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  });

  final String periodId;
  final String tierCode;
  final Uri officialSourceUri;
  final String pdfSha256;
  final String candidateUniverseSha256;
  final Set<String> candidateNumbers;
  final Set<String> matchedInvoiceNumbers;

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
  });

  final int pageCount;
  final int pagesRead;
  final Set<String> matchedInvoiceNumbers;
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

    await _channel.invokeMethod<void>('clearLastDiagnostic');
    final matched = <String>{};
    var pagesRead = 0;
    int? expectedPageCount;

    for (var candidateIndex = 0;
        candidateIndex < candidates.length;
        candidateIndex += 1) {
      cancellation?.throwIfCancelled();
      final candidate = candidates[candidateIndex];
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

        Future<List<String>> pageTokens(int pageNumber) async {
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
          final tokens = CloudAwardPdfIndexBuilder.extractInvoiceNumbers(text);
          if (tokens.isEmpty) {
            throw StateError('CLOUD_AWARD_SORTED_PDF_PAGE_EMPTY');
          }
          for (var index = 1; index < tokens.length; index += 1) {
            if (tokens[index - 1].compareTo(tokens[index]) > 0) {
              throw StateError('CLOUD_AWARD_SORTED_PDF_PAGE_NOT_SORTED');
            }
          }
          pageCache[pageNumber] = List<String>.unmodifiable(tokens);
          pagesRead += 1;
          onProgress?.call(
            CloudAwardSortedPdfCandidateProgress(
              candidateIndex: candidateIndex + 1,
              candidateCount: candidates.length,
              pageNumber: pageNumber,
              pageCount: pageCount,
              pagesRead: pagesRead,
            ),
          );
          return pageCache[pageNumber]!;
        }

        var low = 1;
        var high = pageCount;
        while (low <= high) {
          cancellation?.throwIfCancelled();
          final middle = low + ((high - low) >> 1);
          final tokens = await pageTokens(middle);
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
          if (tokens.contains(candidate)) matched.add(candidate);
          break;
        }
      } finally {
        if (sessionId.isNotEmpty) {
          try {
            await _channel.invokeMethod<void>(
              'closePdfiumSession',
              <String, Object?>{'sessionId': sessionId},
            );
          } catch (_) {
            // Session cleanup is idempotent and must not mask lookup results.
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
      pagesRead: pagesRead,
      matchedInvoiceNumbers: Set<String>.unmodifiable(matched),
    );
  }
}
