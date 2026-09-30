import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud-500 foreground authority is routed through PDFium candidate lookup', () {
    final source = File(
      'lib/features/invoice/invoice_award_cloud_foreground_acquisition.dart',
    ).readAsStringSync();

    // The large cloud-500 successor must remain an exact-candidate PDFium path.
    // This guards against accidentally restoring the former whole-document
    // PDFBox materialization route that OOMed on the 115-07-08 official PDF.
    expect(
      source,
      contains(
        'sortedCandidateLookup ?? const PdfiumCloudAwardSortedPdfCandidateLookup()',
      ),
    );
    expect(
      source,
      contains("reference.tierCode == 'cloud-500' &&"),
    );
    expect(
      source,
      contains('final candidateMatch = await _sortedCandidateLookup.findMatches('),
    );

    // Durable authority must bind the exact official PDF, exact local candidate
    // universe and page evidence returned by the bounded PDFium lookup.
    expect(source, contains('pdfSha256: artifact.sha256.toLowerCase()'));
    expect(source, contains('candidateUniverseSha256: universeSha'));
    expect(
      source,
      contains('matchedPageNumbers: candidateMatch.matchedPageNumbers'),
    );

    // Cloud-500 must terminate its exact-candidate branch after authority is
    // persisted. It must never fall through to the generic index builder, whose
    // extractor is the historical PDFBox whole-document path for other tiers.
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
    final branchContinue = source.lastIndexOf(
      'continue;',
      genericIndexBuilder,
    );
    expect(cloud500Branch, greaterThanOrEqualTo(0));
    expect(candidateLookup, greaterThan(cloud500Branch));
    expect(genericIndexBuilder, greaterThan(candidateLookup));
    expect(branchContinue, greaterThan(candidateLookup));
    expect(branchContinue, lessThan(genericIndexBuilder));

    // The foreground service must not itself contain a PDFBox whole-document
    // open primitive. Native PDFium owns the >120 MiB candidate search.
    expect(source, isNot(contains('PDDocument.load')));
    expect(source, isNot(contains('PDFTextStripper')));
  });

  test('cloud-500 native worker keeps exact-candidate authority bounded and provenance-bearing', () {
    final worker = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PdfiumCandidateWorkerService.kt',
    ).readAsStringSync();

    // Regression guard for the 128.9 MiB failure mode: the isolated worker may
    // open the official PDF only through random-access PDFium. An executable
    // PDFBox whole-document load must never return to this production path.
    expect(worker, contains('ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)'));
    expect(worker, contains('pdfiumCore.newDocument(descriptor)'));
    expect(worker, isNot(matches(RegExp(r'PDDocument\s*\.\s*load\s*\('))));

    // Candidate scope stays local and exact. The worker normalizes only the
    // supplied candidate universe and never constructs a full-document index.
    expect(worker, contains('JSONArray(candidatesJson)'));
    expect(worker, contains('Regex("^[A-Z]{2}[0-9]{8}\$")'));
    expect(worker, contains('candidates.forEachIndexed'));
    expect(worker, contains('var low = 1'));
    expect(worker, contains('var high = pageCount'));
    expect(worker, contains('val middle = low + ((high - low) ushr 1)'));

    // Promotion evidence must independently bind source bytes/SHA, candidate
    // universe SHA and the page on which every positive match was observed.
    expect(worker, contains('actualSourceSha256'));
    expect(worker, contains('actualCandidateUniverseSha256'));
    expect(worker, contains('matchedPages[candidate] = middle'));
    expect(worker, contains('.put("source_sha256", actualSourceSha256)'));
    expect(worker, contains('.put("source_bytes", source.length())'));
    expect(worker, contains('.put("candidate_universe_sha256", actualCandidateUniverseSha256)'));
    expect(worker, contains('.put("matched_pages", matchedPagesJson)'));

    // Long source verification and page search remain observable; a killed or
    // partial worker cannot silently promote authority.
    expect(worker, contains('stage = "PDFIUM_SOURCE_SHA256"'));
    expect(worker, contains('stage = "PDFIUM_OPEN_BEGIN"'));
    expect(worker, contains('stage = "PDFIUM_PAGE_BEGIN"'));
    expect(worker, contains('stage = "PDFIUM_CANDIDATE_SEARCH"'));
    expect(worker, contains('.put("status", "complete")'));
    expect(worker, contains('.put("status", "failed")'));
  });
}
