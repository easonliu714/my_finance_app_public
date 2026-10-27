import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #13 cloud-500 >120 MiB platform successor contract', () {
    late String workerSource;
    late String custodySource;

    setUpAll(() {
      workerSource = File(
        'packages/flutter_pdf_text/android/src/main/kotlin/'
        'me/movenext/flutter_pdf_text/PlatformPdfCandidateWorkerService.kt',
      ).readAsStringSync();
      custodySource = File(
        'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PlatformSourceSnapshotCustody.kt',
      ).readAsStringSync();
    });

    test('large worker is platform PdfRenderer, never PDFium or PDFBox', () {
      expect(workerSource, contains('android.graphics.pdf.PdfRenderer'));
      expect(workerSource, contains('PdfRenderer(descriptor)'));
      expect(workerSource, contains('renderer.openPage'));
      expect(workerSource, contains('textContents'));
      expect(
        workerSource,
        contains('android-platform-pdfrenderer-candidate-search'),
      );
      expect(workerSource, isNot(contains('PdfiumCore')));
      expect(
        RegExp(r'^import\s+com\.tom_roush\.pdfbox\.', multiLine: true)
            .hasMatch(workerSource),
        isFalse,
      );
      expect(
        RegExp(r'\bPDDocument\s*\.\s*load\s*\(').hasMatch(workerSource),
        isFalse,
      );
      expect(
        RegExp(r'\bPDFTextStripper\s*\(').hasMatch(workerSource),
        isFalse,
      );
    });

    test('candidate authority is non-vacuous and provenance-bound', () {
      expect(workerSource, contains('candidates.isEmpty()'));
      expect(workerSource, contains('PLATFORM_WORKER_CANDIDATE_SCOPE_INVALID'));
      expect(workerSource, contains('expectedCandidateUniverseSha256'));
      expect(
        workerSource,
        contains('PLATFORM_WORKER_CANDIDATE_UNIVERSE_SHA256_MISMATCH'),
      );
      expect(workerSource, contains('PlatformSourceSnapshotCustody.capture('));
      expect(workerSource, contains('val actualSourceSha256 = custody.sha256'));
      expect(custodySource, contains('throw IOException("SOURCE_CUSTODY_SHA256_MISMATCH")'));
      expect(workerSource, contains('platformSourceCustodyFailureCode(error)'));
      expect(workerSource, contains('writeFailure(resultPath, requestId, platformSourceCustodyFailureCode(error))'));
      expect(workerSource, contains('"PLATFORM_WORKER_SOURCE_SHA256_MISMATCH"'));
      expect(custodySource, contains('LinkOption.NOFOLLOW_LINKS'));
      expect(custodySource, contains('Files.delete(snapshot)'));
      expect(workerSource, contains('matched_pages'));
      expect(workerSource, contains('PLATFORM_RENDERER_API35_REQUIRED'));
    });

    test('worker exposes bounded progress stages and page evidence', () {
      for (final stage in <String>[
        'PLATFORM_SOURCE_SHA256',
        'PLATFORM_RENDERER_OPEN_BEGIN',
        'PLATFORM_RENDERER_OPEN_WAIT',
        'PLATFORM_RENDERER_OPEN_OK',
        'PLATFORM_RENDERER_PAGE_BEGIN',
        'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'PLATFORM_RENDERER_COMPLETE',
      ]) {
        expect(workerSource, contains(stage), reason: 'missing stage $stage');
      }
      expect(workerSource, contains('pages_read'));
      expect(workerSource, contains('page_count'));
      expect(workerSource, contains('candidate_universe_sha256'));
      expect(workerSource, contains('source_sha256'));
    });
  });
}
