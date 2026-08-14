import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_v2_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_trace_script.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('batch trace preserves one terminal record per requested invoice', () {
    final result = OfficialInvoiceDetailBatchResult(
      requestedCount: 3,
      results: <OfficialInvoiceDetailEnrichment>[
        _enrichment('AA00000001', DateTime(2026, 6, 26, 10)),
      ],
      cancelled: true,
      traces: <OfficialInvoiceDetailTraceItem>[
        OfficialInvoiceDetailTraceItem(
          invoiceNumber: 'AA00000001',
          ordinal: 1,
          status: OfficialInvoiceDetailTraceStatus.success,
          completedAt: DateTime.utc(2026, 6, 26, 2, 1),
        ),
        const OfficialInvoiceDetailTraceItem(
          invoiceNumber: 'AA00000002',
          ordinal: 2,
          status: OfficialInvoiceDetailTraceStatus.cancelledActive,
          reasonCode: 'DETAIL_CANCELLED_ACTIVE',
        ),
        const OfficialInvoiceDetailTraceItem(
          invoiceNumber: 'AA00000003',
          ordinal: 3,
          status: OfficialInvoiceDetailTraceStatus.notStartedAfterCancel,
          reasonCode: 'DETAIL_NOT_STARTED_AFTER_CANCEL',
        ),
      ],
    );

    expect(result.terminalTraceCount, 3);
    expect(result.unprocessedCount, 2);
    expect(
      result.unprocessedTraces.map((item) => item.invoiceNumber),
      <String>['AA00000002', 'AA00000003'],
    );
    expect(result.failureCounts['DETAIL_CANCELLED_ACTIVE'], 1);
    expect(result.failureCounts['DETAIL_NOT_STARTED_AFTER_CANCEL'], 1);
  });

  test('trace script registers target identity and ordinal before processing', () {
    final script = buildOfficialInvoiceDetailEnrichmentTraceScript(
      scope: OfficialInvoiceDetailSelectionScope.currentPage,
      handlerName: 'traceHandler',
    );

    expect(script, contains("type: 'started'"));
    expect(script, contains('targets: targets.map'));
    expect(script, contains('invoiceNumber: target.invoiceNumber'));
    expect(script, contains('ordinal: index + 1'));
  });

  test('runtime separates hard timeout from explicit user cancellation', () {
    final source = File(
      'lib/features/invoice/lab/flutter_landing_webview_session_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('Duration(minutes: 30)'));
    expect(source, isNot(contains('Duration(minutes: 4)')));
    expect(source, contains('_signalOfficialDetailCancellation'));
    expect(source, contains("errorCode: 'DETAIL_BATCH_TIMEOUT'"));
    expect(source, contains('OfficialInvoiceDetailTraceStatus'));
    expect(source, contains('_finalizeDetailTraces'));
  });

  test('preflight excludes exact formal identity and flags timestamp conflict',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV15Tables(db);
    await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
    await db.insert('transactions', <String, Object?>{
      'id': 'transaction-exact',
    });
    await db.insert('transactions', <String, Object?>{
      'id': 'transaction-conflict',
    });

    final exactTimestamp = DateTime(2026, 6, 26, 10, 11, 12);
    final conflictTimestamp = DateTime(2026, 6, 26, 11, 22, 33);
    await _insertMetadata(
      db,
      invoiceNumber: 'AA00000001',
      invoiceDate: exactTimestamp,
      transactionId: 'transaction-exact',
    );
    await _insertMetadata(
      db,
      invoiceNumber: 'AA00000002',
      invoiceDate: conflictTimestamp.add(const Duration(seconds: 1)),
      transactionId: 'transaction-conflict',
    );

    final batch = OfficialInvoiceDetailBatchResult(
      requestedCount: 3,
      results: <OfficialInvoiceDetailEnrichment>[
        _enrichment('AA00000001', exactTimestamp),
        _enrichment('AA00000002', conflictTimestamp),
        _enrichment('AA00000003', DateTime(2026, 6, 26, 12, 34, 56)),
      ],
      cancelled: false,
    );
    final service = OfficialInvoiceDetailDraftImportV2Service(
      databaseProvider: () async => db,
    );

    final items = await service.classifyItems(batch);
    final byInvoice = <String, OfficialInvoiceDetailImportPreflightItem>{
      for (final item in items) item.invoiceNumber: item,
    };

    expect(
      byInvoice['AA00000001']!.status,
      OfficialInvoiceDetailImportPreflightStatus.alreadyFormal,
    );
    expect(byInvoice['AA00000001']!.transactionId, 'transaction-exact');
    expect(
      byInvoice['AA00000002']!.status,
      OfficialInvoiceDetailImportPreflightStatus.identityConflict,
    );
    expect(
      byInvoice['AA00000003']!.status,
      OfficialInvoiceDetailImportPreflightStatus.selectable,
    );
  });

  test('confirmed overseas difference becomes an auditable supporting line', () {
    final source = _estimatedTaxEnrichment();

    expect(source.positiveEstimatedTaxAmount, 31);
    expect(source.canUseUserConfirmedEstimatedTax, isTrue);
    expect(isOfficialInvoiceDetailEligibleForFormalImportV2(source), isTrue);

    final confirmed = withUserConfirmedEstimatedTax(source);
    expect(confirmed.success, isTrue);
    expect(confirmed.officialTaxAmount, 31);
    expect(confirmed.officialTaxLabel, '推算稅額（使用者確認）');
    expect(confirmed.unallocatedDifference, 0);
    expect(confirmed.lineItems, hasLength(2));
    expect(confirmed.lineItems.last.name, '推算稅額（使用者確認）');
    expect(confirmed.lineItems.last.amount, 31);
  });
}

OfficialInvoiceDetailEnrichment _enrichment(
  String invoiceNumber,
  DateTime timestamp,
) {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: invoiceNumber,
    invoiceNumber: invoiceNumber,
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 26, 3),
    success: true,
    invoiceIdentityMatches: true,
    detailTotalInternallyConsistent: true,
    detailTotalMatchesCsv: true,
    sellerIdentifierConsistent: true,
    lineItems: const <OfficialInvoiceDetailLineItem>[
      OfficialInvoiceDetailLineItem(
        name: '測試商品',
        quantity: 1,
        unitPrice: 100,
        amount: 100,
      ),
    ],
    exactTimestamp: timestamp,
    currencyCode: 'TWD',
    officialStatus: '已確認',
    sellerIdentifier: '12345678',
    sellerName: '測試商家',
    expectedTotal: 100,
    detailTotal: 100,
    lineItemSubtotal: 100,
    unallocatedDifference: 0,
  );
}

OfficialInvoiceDetailEnrichment _estimatedTaxEnrichment() {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: 'GP00000660',
    invoiceNumber: 'GP00000660',
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 26, 3),
    success: false,
    invoiceIdentityMatches: true,
    detailTotalInternallyConsistent: false,
    detailTotalMatchesCsv: true,
    sellerIdentifierConsistent: true,
    lineItems: const <OfficialInvoiceDetailLineItem>[
      OfficialInvoiceDetailLineItem(
        name: 'Example App Store 應用程式',
        quantity: 1,
        unitPrice: 629,
        amount: 629,
      ),
    ],
    exactTimestamp: DateTime(2026, 6, 25, 20),
    currencyCode: 'TWD',
    officialStatus: '已確認',
    sellerIdentifier: '42523557',
    sellerName: 'Example Asia Pacific Pte Ltd',
    expectedTotal: 660,
    detailTotal: 660,
    lineItemSubtotal: 629,
    unallocatedDifference: 31,
    errorCode: 'DETAIL_UNALLOCATED_DIFFERENCE',
    dialogDetected: true,
    summaryTableDetected: true,
    itemTableDetected: true,
    detectedItemRowCount: 1,
  );
}

Future<void> _insertMetadata(
  Database db, {
  required String invoiceNumber,
  required DateTime invoiceDate,
  required String transactionId,
}) async {
  await db.insert('cloud_invoice_metadata_links', <String, Object?>{
    'id': 'metadata-$invoiceNumber',
    'operation_key': 'operation-$invoiceNumber',
    'transaction_id': transactionId,
    'candidate_reference': 'candidate-$invoiceNumber',
    'invoice_number': invoiceNumber,
    'seller_identifier': '12345678',
    'seller_name': '測試商家',
    'invoice_date': invoiceDate.toIso8601String(),
    'time_precision': 'exactDateTime',
    'time_source': 'officialDetailPage',
    'currency_code': 'TWD',
    'currency_source': 'officialDetailPage',
    'tax_amount': null,
    'merchant_id': null,
    'line_items_json': '[]',
    'payload_version': 1,
    'created_at': DateTime.utc(2026, 6, 26, 3).toIso8601String(),
  });
}
