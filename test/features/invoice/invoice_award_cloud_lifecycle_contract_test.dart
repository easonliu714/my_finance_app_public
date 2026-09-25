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

    expect(candidateSource, contains('CloudAwardCandidateLookupCancellation'));
    expect(candidateSource, contains("'openPdfiumSession'"));
    expect(candidateSource, contains("'closePdfiumSession'"));
    expect(candidateSource, contains('for (var candidateIndex = 0;'));
    expect(foregroundSource, contains('candidateScopedEmptyVerified'));
    expect(
      foregroundSource,
      contains('本期沒有可比對的雲端候選，略過大型 500 元獎 PDF'),
    );
    expect(pageSource, contains('with WidgetsBindingObserver'));
    expect(pageSource, contains('_processRefreshActive'));
    expect(pageSource, contains('_activeCloudCancellation?.cancel()'));
    expect(pageSource, contains('on CloudAwardCandidateLookupCancelled'));
  });
}
