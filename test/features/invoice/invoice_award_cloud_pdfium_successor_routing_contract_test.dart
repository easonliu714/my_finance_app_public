import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud-500 foreground authority is routed through exact-candidate lookup', () {
    final source = File(
      'lib/features/invoice/invoice_award_cloud_foreground_acquisition.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'sortedCandidateLookup ?? const PdfiumCloudAwardSortedPdfCandidateLookup()',
      ),
    );
    expect(source, contains("reference.tierCode == 'cloud-500' &&"));
    expect(
      source,
      contains('final candidateMatch = await _sortedCandidateLookup.findMatches('),
    );

    expect(source, contains('pdfSha256: artifact.sha256.toLowerCase()'));
    expect(source, contains('candidateUniverseSha256: universeSha'));
    expect(
      source,
      contains('matchedPageNumbers: candidateMatch.matchedPageNumbers'),
    );

    final cloud500Branch = source.indexOf(
      "if (reference.tierCode == 'cloud-500' &&\n            normalizedCandidates.isNotEmpty)",
    );
    final candidateLookup = source.indexOf(
      'final candidateMatch = await _sortedCandidateLookup.findMatches(',
      cloud500Branch,
    );
    final genericIndexBuilder = source.indexOf(
      'final build = await _indexBuilder.buildCandidate(',
      candidateLookup,
    );
    final branchContinue = source.lastIndexOf('continue;', genericIndexBuilder);
    expect(cloud500Branch, greaterThanOrEqualTo(0));
    expect(candidateLookup, greaterThan(cloud500Branch));
    expect(genericIndexBuilder, greaterThan(candidateLookup));
    expect(branchContinue, greaterThan(candidateLookup));
    expect(branchContinue, lessThan(genericIndexBuilder));

    expect(source, isNot(contains('PDDocument.load')));
    expect(source, isNot(contains('PDFTextStripper')));
  });

  test('large native worker uses platform PdfRenderer with exact provenance', () {
    final worker = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/'
      'me/movenext/flutter_pdf_text/PlatformPdfCandidateWorkerService.kt',
    ).readAsStringSync();

    final custody = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PlatformSourceSnapshotCustody.kt',
    ).readAsStringSync();

    expect(worker, contains('PlatformSourceSnapshotCustody.capture('));
    expect(worker, contains('var descriptor: ParcelFileDescriptor? = custody.descriptor'));
    expect(custody, contains('ParcelFileDescriptor.MODE_READ_ONLY'));
    expect(custody, contains('LinkOption.NOFOLLOW_LINKS'));
    expect(custody, contains('Files.delete(snapshot)'));
    expect(worker, contains('PdfRenderer'));
    // Verify the nullable snapshot FD is checked before renderer ownership.
    expect(
      worker,
      contains('val rendererDescriptor = descriptor ?: throw IOException("SOURCE_CUSTODY_DESCRIPTOR_MISSING")'),
    );
    expect(worker, contains('renderer = PdfRenderer(rendererDescriptor)'));
    final guardAt = worker.indexOf(
      'val rendererDescriptor = descriptor ?: throw IOException(',
    );
    final rendererAt = worker.indexOf('renderer = PdfRenderer(rendererDescriptor)');
    expect(guardAt, greaterThanOrEqualTo(0));
    expect(rendererAt, greaterThan(guardAt));
    final handoffAt = worker.indexOf('descriptor = null', rendererAt);
    expect(handoffAt, greaterThan(rendererAt));
    expect(worker, contains('try { renderer?.close() }'));
    expect(worker, contains('try { descriptor?.close() }'));
    expect(worker, contains('renderer.openPage(pageNumber - 1)'));
    expect(worker, contains('it.textContents'));
    expect(worker, contains('Build.VERSION.SDK_INT < 35'));
    expect(worker, isNot(matches(RegExp(r'PDDocument\s*\.\s*load\s*\('))));
    expect(worker, isNot(contains('PdfiumCore')));

    expect(worker, contains('JSONArray(candidatesJson)'));
    expect(worker, contains('Regex("^[A-Z]{2}[0-9]{8}\$")'));
    expect(worker, contains('candidates.forEachIndexed'));
    expect(worker, contains('var low = 1'));
    expect(worker, contains('var high = pageCount'));
    expect(worker, contains('val middle = low + ((high - low) ushr 1)'));
    expect(worker, isNot(matches(RegExp(r'for\s*\([^)]*1\s*\.\.\s*pageCount'))));
    expect(worker, isNot(matches(RegExp(r'for\s*\([^)]*0\s+until\s+pageCount'))));

    expect(worker, contains('val actualSourceSha256 = custody.sha256'));
    expect(custody, contains('if (total != expectedBytes)'));
    expect(custody, contains('SOURCE_CUSTODY_SHA256_MISMATCH'));
    expect(worker, contains('actualCandidateUniverseSha256'));
    expect(worker, contains('matchedPages[candidate] = middle'));
    expect(worker, contains('.put("source_sha256", actualSourceSha256)'));
    expect(worker, contains('.put("source_bytes", custody.bytes)'));
    expect(
      worker,
      contains('.put("candidate_universe_sha256", actualCandidateUniverseSha256)'),
    );
    expect(worker, contains('.put("matched_pages", matchedPagesJson)'));

    for (final stage in <String>[
      'PLATFORM_SOURCE_SHA256',
      'PLATFORM_RENDERER_OPEN_BEGIN',
      'PLATFORM_RENDERER_OPEN_WAIT',
      'PLATFORM_RENDERER_OPEN_OK',
      'PLATFORM_RENDERER_PAGE_BEGIN',
      'PLATFORM_RENDERER_CANDIDATE_SEARCH',
      'PLATFORM_RENDERER_COMPLETE',
    ]) {
      expect(worker, contains(stage), reason: 'missing stage $stage');
    }
    expect(worker, contains('.put("status", "complete")'));
    expect(worker, contains('.put("status", "failed")'));
    expect(worker, contains('.put("updated_at_ms", System.currentTimeMillis())'));
  });

  test('large Dart route invokes platform worker and retries atomic read races', () {
    final source = File(
      'lib/features/invoice/invoice_award_cloud_candidate_scope.dart',
    ).readAsStringSync();

    final largeStart = source.indexOf(
      'Future<CloudAwardSortedPdfCandidateMatchResult> _findMatchesCrashIsolated',
    );
    expect(largeStart, greaterThanOrEqualTo(0));
    final largeSource = source.substring(largeStart);
    expect(largeSource, contains("'startPlatformCandidateWorker'"));
    expect(largeSource, contains("'getPlatformCandidateWorkerLiveness'"));
    expect(
      largeSource,
      contains('android-platform-pdfrenderer-candidate-search'),
    );
    expect(largeSource, contains('on FileSystemException'));
    expect(largeSource, contains('on FormatException'));
  });
}
