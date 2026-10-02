import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4.20.14 owner award findings are closed in the successor', () {
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final candidateRepo = File(
      'lib/features/invoice/existing_invoice_award_candidate_repository.dart',
    ).readAsStringSync();
    final worker = File(
      'packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/PdfiumCandidateWorkerService.kt',
    ).readAsStringSync();
    final scope = File(
      'lib/features/invoice/invoice_award_cloud_candidate_scope.dart',
    ).readAsStringSync();

    // Winner summary targets remain mounted even when far below the fold.
    expect(page, contains('SingleChildScrollView('));
    expect(page, contains('Scrollable.ensureVisible'));

    // Award amounts must interpolate instead of exposing a Dart expression.
    expect(page, isNot(contains(r'NT\${_formatAmount')));

    // Do not expose internal transaction UUIDs in the end-user award list.
    expect(page, isNot(contains(r'交易 ${candidate.transactionId}')));
    expect(page, contains('candidate.merchantDisplayName'));
    expect(page, contains('candidate.invoiceTypeLabel'));
    expect(page, contains('_formatCandidateDate(candidate.invoiceDate)'));
    expect(candidateRepo, contains('transaction.currency.code'));

    // The >120 MiB cloud-500 path uses a fresh process plus native PDFium
    // random-access candidate-only page search rather than PDFBox whole-
    // document object-graph loading or full indexing.
    expect(worker, contains('PdfiumCore(applicationContext)'));
    expect(worker, contains('ParcelFileDescriptor.MODE_READ_ONLY'));
    expect(worker, contains('pdfiumCore.newDocument(descriptor)'));
    expect(worker, contains('document.openPage(pageNumber - 1)'));
    expect(worker, contains('page.openTextPage()'));
    expect(worker, contains('pdfium-random-access-candidate-search'));
    expect(
      RegExp(r'PDDocument\.load\s*\(').hasMatch(worker),
      isFalse,
    );
    expect(worker, isNot(contains('PDFTextStripper()')));
    expect(scope, contains("status == 'running'"));
    expect(
      scope,
      contains('CLOUD_AWARD_CANDIDATE_WORKER_STALE_HEARTBEAT_'),
    );
    expect(
      scope,
      contains('workerHeartbeatStaleAfter = Duration(seconds: 45)'),
    );
    expect(
      scope,
      isNot(contains('workerResultTimeout = Duration(seconds: 120)')),
    );
  });
}
