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
}
