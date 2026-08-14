import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_retry.dart';

void main() {
  test('residual diagnostics separate retry, estimate, source and conflict', () {
    final batch = OfficialInvoiceDetailBatchResult(
      requestedCount: 5,
      results: <OfficialInvoiceDetailEnrichment>[
        _success('AA00000001'),
        _estimatedTax('AA00000002'),
        _failure('AA00000003', 'DETAIL_RENDER_TIMEOUT'),
        _failure('AA00000004', 'DETAIL_ITEM_TABLE_NOT_FOUND'),
        _failure('AA00000005', 'DETAIL_TOTAL_CSV_MISMATCH'),
      ],
      cancelled: false,
      traces: <OfficialInvoiceDetailTraceItem>[
        _trace(1, 'AA00000001', OfficialInvoiceDetailTraceStatus.success),
        _trace(2, 'AA00000002', OfficialInvoiceDetailTraceStatus.review,
            'DETAIL_UNALLOCATED_DIFFERENCE'),
        _trace(3, 'AA00000003', OfficialInvoiceDetailTraceStatus.failed,
            'DETAIL_RENDER_TIMEOUT'),
        _trace(4, 'AA00000004', OfficialInvoiceDetailTraceStatus.review,
            'DETAIL_ITEM_TABLE_NOT_FOUND'),
        _trace(5, 'AA00000005', OfficialInvoiceDetailTraceStatus.review,
            'DETAIL_TOTAL_CSV_MISMATCH'),
      ],
    );

    expect(batch.successCount, 1);
    expect(batch.estimatedTaxReviewCount, 1);
    expect(batch.technicalRetryableCount, 1);
    expect(batch.safeRetryableCount, 1);
    expect(batch.sourceContentIncompleteCount, 1);
    expect(batch.identityOrTotalConflictCount, 1);
    expect(batch.failClosedCount, 2);
  });

  test('duplicate invoice identity is fail-closed for local retry', () {
    final batch = OfficialInvoiceDetailBatchResult(
      requestedCount: 2,
      results: <OfficialInvoiceDetailEnrichment>[
        _failure('AA00000003', 'DETAIL_RENDER_TIMEOUT'),
        _failure('AA00000003', 'DETAIL_NO_DIALOG'),
      ],
      cancelled: false,
      traces: <OfficialInvoiceDetailTraceItem>[
        _trace(1, 'AA00000003', OfficialInvoiceDetailTraceStatus.failed,
            'DETAIL_RENDER_TIMEOUT'),
        _trace(2, 'AA00000003', OfficialInvoiceDetailTraceStatus.failed,
            'DETAIL_NO_DIALOG'),
      ],
    );

    expect(batch.technicalRetryableCount, 2);
    expect(batch.safeRetryableCount, 0);
    expect(batch.residualItems.every((item) => !item.retryEligible), isTrue);
  });

  test('retry merge replaces only the matching original ordinal', () {
    final original = OfficialInvoiceDetailBatchResult(
      requestedCount: 3,
      results: <OfficialInvoiceDetailEnrichment>[
        _success('AA00000001'),
        _failure('AA00000002', 'DETAIL_RENDER_TIMEOUT'),
        _failure('AA00000003', 'DETAIL_TOTAL_CSV_MISMATCH'),
      ],
      cancelled: false,
      traces: <OfficialInvoiceDetailTraceItem>[
        _trace(1, 'AA00000001', OfficialInvoiceDetailTraceStatus.success),
        _trace(2, 'AA00000002', OfficialInvoiceDetailTraceStatus.failed,
            'DETAIL_RENDER_TIMEOUT'),
        _trace(3, 'AA00000003', OfficialInvoiceDetailTraceStatus.review,
            'DETAIL_TOTAL_CSV_MISMATCH'),
      ],
    );
    final retry = OfficialInvoiceDetailBatchResult(
      requestedCount: 1,
      results: <OfficialInvoiceDetailEnrichment>[_success('AA00000002')],
      cancelled: false,
      traces: <OfficialInvoiceDetailTraceItem>[
        _trace(1, 'AA00000002', OfficialInvoiceDetailTraceStatus.success),
      ],
    );

    final merged = original.mergeRetryOutcomes(
      <OfficialInvoiceDetailRetryOutcome>[
        OfficialInvoiceDetailRetryOutcome(
          originalOrdinal: 2,
          invoiceNumber: 'AA00000002',
          retryBatchResult: retry,
        ),
      ],
    );

    expect(merged.results, hasLength(3));
    expect(merged.successCount, 2);
    expect(merged.residualItems.map((item) => item.ordinal), <int>[3]);
    expect(
      merged.traces.singleWhere((item) => item.ordinal == 2).status,
      OfficialInvoiceDetailTraceStatus.success,
    );
    expect(
      merged.traces.singleWhere((item) => item.ordinal == 3).reasonCode,
      'DETAIL_TOTAL_CSV_MISMATCH',
    );
  });

  test('P4.12.25 UI remains explicit, foreground-only and version aligned', () {
    final review = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_review_page.dart',
    ).readAsStringSync();
    final retry = File(
      'lib/features/invoice/lab/official_invoice_detail_retry_page.dart',
    ).readAsStringSync();
    final config = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*([^\s]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(review, contains('OfficialInvoiceDetailRetryPage'));
    expect(retry, contains('OfficialInvoiceDetailSelectionScope.singleInvoice'));
    expect(retry, contains('我確認只在前景重試'));
    expect(retry, isNot(contains('background')));
    expect(versionMatch, isNotNull);
    expect(
      config,
      contains("validationVersion = '${versionMatch!.group(1)}'"),
    );
  });
}

OfficialInvoiceDetailTraceItem _trace(
  int ordinal,
  String invoiceNumber,
  OfficialInvoiceDetailTraceStatus status, [
  String? reasonCode,
]) {
  return OfficialInvoiceDetailTraceItem(
    invoiceNumber: invoiceNumber,
    ordinal: ordinal,
    status: status,
    reasonCode: reasonCode,
  );
}

OfficialInvoiceDetailEnrichment _success(String invoiceNumber) {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: invoiceNumber,
    invoiceNumber: invoiceNumber,
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 26),
    success: true,
    invoiceIdentityMatches: true,
    detailTotalInternallyConsistent: true,
    detailTotalMatchesCsv: true,
    sellerIdentifierConsistent: true,
    lineItems: const <OfficialInvoiceDetailLineItem>[
      OfficialInvoiceDetailLineItem(name: '商品', amount: 100),
    ],
    exactTimestamp: DateTime.utc(2026, 6, 26),
    expectedTotal: 100,
    detailTotal: 100,
    lineItemSubtotal: 100,
    unallocatedDifference: 0,
  );
}

OfficialInvoiceDetailEnrichment _failure(String invoiceNumber, String code) {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: invoiceNumber,
    invoiceNumber: invoiceNumber,
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 26),
    success: false,
    invoiceIdentityMatches: code != 'DETAIL_INVOICE_IDENTITY_MISMATCH',
    detailTotalInternallyConsistent: false,
    detailTotalMatchesCsv: code != 'DETAIL_TOTAL_CSV_MISMATCH',
    sellerIdentifierConsistent: true,
    lineItems: const <OfficialInvoiceDetailLineItem>[],
    errorCode: code,
  );
}

OfficialInvoiceDetailEnrichment _estimatedTax(String invoiceNumber) {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: invoiceNumber,
    invoiceNumber: invoiceNumber,
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 26),
    success: false,
    invoiceIdentityMatches: true,
    detailTotalInternallyConsistent: false,
    detailTotalMatchesCsv: true,
    sellerIdentifierConsistent: true,
    lineItems: const <OfficialInvoiceDetailLineItem>[
      OfficialInvoiceDetailLineItem(name: 'Example App Store', amount: 190),
    ],
    exactTimestamp: DateTime.utc(2026, 6, 26),
    expectedTotal: 200,
    detailTotal: 200,
    lineItemSubtotal: 190,
    unallocatedDifference: 10,
    errorCode: 'DETAIL_UNALLOCATED_DIFFERENCE',
  );
}
