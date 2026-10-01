import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #13 cloud-500 >120 MiB successor contract', () {
    late String workerSource;

    setUpAll(() {
      workerSource = File(
        'packages/flutter_pdf_text/android/src/main/kotlin/'
        'me/movenext/flutter_pdf_text/PdfiumCandidateWorkerService.kt',
      ).readAsStringSync();
    });

    test('large worker remains native PDFium random-access, never PDFBox', () {
      expect(workerSource, contains('PdfiumCore'));
      expect(workerSource, contains('pdfiumCore.newDocument'));
      expect(workerSource, contains('document.openPage'));
      expect(
        workerSource,
        contains('pdfium-random-access-candidate-search'),
      );

      // Regression gate for the 115-07-08 cloud-500 OOM root cause: the
      // >120 MiB worker must never return to PDFBox whole-document loading.
      expect(workerSource, isNot(contains('PDDocument')));
      expect(workerSource, isNot(contains('PDFBox')));
      expect(workerSource, isNot(contains('MemoryUsageSetting')));
      expect(workerSource, isNot(contains('setupTempFileOnly')));
    });

    test('candidate authority is non-vacuous and provenance-bound', () {
      expect(workerSource, contains('candidates.isEmpty()'));
      expect(
        workerSource,
        contains('PDFIUM_WORKER_CANDIDATE_SCOPE_INVALID'),
      );
      expect(
        workerSource,
        contains('expectedCandidateUniverseSha256'),
      );
      expect(
        workerSource,
        contains('PDFIUM_WORKER_CANDIDATE_UNIVERSE_SHA256_MISMATCH'),
      );
      expect(workerSource, contains('PDFIUM_WORKER_SOURCE_SHA256_MISMATCH'));
      expect(workerSource, contains('matched_pages'));
    });

    test('worker exposes bounded progress stages and page evidence', () {
      for (final stage in <String>[
        'PDFIUM_SOURCE_SHA256',
        'PDFIUM_OPEN_BEGIN',
        'PDFIUM_OPEN_OK',
        'PDFIUM_PAGE_BEGIN',
        'PDFIUM_CANDIDATE_SEARCH',
        'PDFIUM_COMPLETE',
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
