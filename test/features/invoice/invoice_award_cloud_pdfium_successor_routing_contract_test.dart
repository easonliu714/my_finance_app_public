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

    // The foreground service must not itself contain a PDFBox whole-document
    // open primitive. Native PDFium owns the >120 MiB candidate search.
    expect(source, isNot(contains('PDDocument.load')));
    expect(source, isNot(contains('PDFTextStripper')));
  });
}
