import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV review result-producing actions keep explicit focus anchors', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_import_page.dart',
    ).readAsStringSync();

    expect(source, contains('Scrollable.ensureVisible'));
    expect(source, contains('_sourceSummaryAnchor'));
    expect(source, contains('_completedReviewAnchor'));
    expect(source, contains('_unmatchedSectionAnchor'));
    expect(source, contains('_enrichmentResultAnchor'));
    expect(source, contains('_unmatchedResultAnchor'));
    expect(source, contains('_focusAfterFrame(_completedReviewAnchor)'));
    expect(source, contains('_focusAfterFrame(_enrichmentResultAnchor)'));
    expect(source, contains('_focusAfterFrame(_unmatchedSectionAnchor)'));
    expect(source, contains('_focusAfterFrame(_unmatchedResultAnchor)'));
  });

  test('draft promotion focuses its result after processing', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();

    expect(source, contains('Scrollable.ensureVisible'));
    expect(source, contains('_resultAnchor'));
    expect(source, contains('_focusAfterFrame(_resultAnchor)'));
  });

  test('pending draft account inheritance is explicit and non-destructive', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_import_service.dart',
    ).readAsStringSync();

    expect(source, contains('AccountRecord explicitAccount'));
    expect(source, contains("resolutionStatus == 'unresolved'"));
    expect(source, contains("'account_resolution_status': 'selected'"));
    expect(source, contains('never overwrite'));
  });
}
