import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud 500 lifecycle is bounded and retry-safe', () {
    final candidateSource = File(
      'lib/features/invoice/invoice_award_cloud_candidate_scope.dart',
    ).readAsStringSync();
    final foregroundSource = File(
      'lib/features/invoice/invoice_award_cloud_foreground_acquisition.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    final pluginGradle = File(
      'packages/flutter_pdf_text/android/build.gradle',
    ).readAsStringSync();

    expect(candidateSource, contains('CloudAwardCandidateLookupCancellation'));
    expect(candidateSource, contains("'openPdfiumSession'"));
    expect(candidateSource, contains("'closePdfiumSession'"));
    expect(candidateSource, contains('candidateBatchSize = 8'));
    expect(
      candidateSource,
      contains('maxInProcessPdfiumPdfBytes = 120 * 1024 * 1024'),
    );
    expect(
      candidateSource,
      contains('CLOUD_AWARD_PDFIUM_IN_PROCESS_SIZE_GUARD'),
    );
    expect(candidateSource, contains('for (var batchStart = 0;'));
    expect(candidateSource, contains('uniquePagesRead'));
    expect(candidateSource, contains('toSet()'));
    expect(candidateSource, contains('..sort()'));
    expect(foregroundSource, contains('candidateScopedEmptyVerified'));
    expect(
      foregroundSource,
      contains('本期沒有可比對的雲端候選，略過大型 500 元獎 PDF'),
    );
    expect(pageSource, contains('with WidgetsBindingObserver'));
    expect(pageSource, contains('_processRefreshActive'));
    expect(pageSource, contains('_activeCloudCancellation?.cancel()'));
    expect(pageSource, contains('on CloudAwardCandidateLookupCancelled'));
    expect(pageSource, contains('_cloudTierSummaries'));
    expect(pageSource, contains('雲端獎項解析摘要'));
    expect(pageSource, contains('_safeCloudFailureCode'));
    expect(
      foregroundSource,
      contains("const code = 'CLOUD_AWARD_CANDIDATE_LOOKUP_CANCELLED'"),
    );
    expect(
      foregroundSource,
      contains('Preserve already promoted earlier-tier authority'),
    );
    expect(pluginGradle, contains('io.legere:pdfiumandroid:1.0.35'));
  });
}
