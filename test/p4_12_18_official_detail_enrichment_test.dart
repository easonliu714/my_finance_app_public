import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_repository.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_script.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('validated official detail upgrades only normalized candidate fields', () {
    final original = _candidate();
    final enrichment = _validEnrichment();

    expect(enrichment.isCompatibleWithCandidate(original), isTrue);
    expect(enrichment.canUpgradeTime, isTrue);
    expect(enrichment.canUpgradeCurrency, isTrue);
    expect(enrichment.canUseOfficialLineItems, isTrue);

    final enriched = enrichment.applyValidatedValues(original);
    expect(enriched.invoiceDate, DateTime(2026, 6, 18, 14, 35, 22));
    expect(enriched.lineItems, hasLength(2));
    expect(enriched.lineItems.first.name, '官方品項 A');
    expect(enriched.totalAmount, original.totalAmount);
    expect(enriched.invoiceNumber, original.invoiceNumber);
    expect(enriched.sellerIdentifier, original.sellerIdentifier);
    expect(enriched.sellerName, original.sellerName);
    expect(enriched.carrierMaskedId, original.carrierMaskedId);
  });

  test('identity or total conflict cannot upgrade candidate', () {
    final original = _candidate();
    final conflict = OfficialInvoiceDetailEnrichment(
      requestedInvoiceNumber: 'AN90000007',
      invoiceNumber: 'AN90000008',
      selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
      fetchedAt: DateTime.utc(2026, 6, 23),
      success: false,
      invoiceIdentityMatches: false,
      detailTotalInternallyConsistent: true,
      detailTotalMatchesCsv: false,
      sellerIdentifierConsistent: true,
      lineItems: const <OfficialInvoiceDetailLineItem>[],
      exactTimestamp: DateTime(2026, 6, 18, 14, 35, 22),
      currencyCode: 'TWD',
      expectedTotal: 47,
      detailTotal: 48,
      errorCode: 'DETAIL_INVOICE_IDENTITY_MISMATCH',
      dialogDetected: true,
      summaryTableDetected: true,
      itemTableDetected: true,
    );

    expect(conflict.isCompatibleWithCandidate(original), isFalse);
    expect(conflict.applyValidatedValues(original), same(original));
    expect(
      officialInvoiceDetailFailureLabel(conflict.errorCode!),
      '明細發票號碼與目標不一致',
    );
  });

  test('safe diagnostics and failure counts are parsed without raw page data', () {
    final first = OfficialInvoiceDetailEnrichment.fromJson(
      <String, Object?>{
        'requestedInvoiceNumber': 'AN90000009',
        'invoiceNumber': 'AN90000009',
        'selectorProfileVersion': 2,
        'fetchedAt': '2026-06-24T01:48:00Z',
        'success': false,
        'invoiceIdentityMatches': true,
        'detailTotalInternallyConsistent': false,
        'detailTotalMatchesCsv': true,
        'sellerIdentifierConsistent': true,
        'lineItems': const <Object?>[],
        'errorCode': 'DETAIL_ITEM_TABLE_NOT_FOUND',
        'dialogDetected': true,
        'summaryTableDetected': true,
        'itemTableDetected': false,
        'detectedItemRowCount': 0,
      },
    );
    final second = OfficialInvoiceDetailEnrichment.fromJson(
      <String, Object?>{
        'requestedInvoiceNumber': 'BD8526899',
        'invoiceNumber': '',
        'selectorProfileVersion': 2,
        'fetchedAt': '2026-06-24T01:49:00Z',
        'success': false,
        'invoiceIdentityMatches': false,
        'detailTotalInternallyConsistent': false,
        'detailTotalMatchesCsv': false,
        'sellerIdentifierConsistent': true,
        'lineItems': const <Object?>[],
        'errorCode': 'DETAIL_NO_DIALOG',
        'dialogDetected': false,
        'summaryTableDetected': false,
        'itemTableDetected': false,
        'detectedItemRowCount': 0,
      },
    );
    final result = OfficialInvoiceDetailBatchResult(
      requestedCount: 2,
      results: <OfficialInvoiceDetailEnrichment>[first, second],
      cancelled: false,
    );

    expect(first.dialogDetected, isTrue);
    expect(first.summaryTableDetected, isTrue);
    expect(first.itemTableDetected, isFalse);
    expect(result.failureCounts['DETAIL_ITEM_TABLE_NOT_FOUND'], 1);
    expect(result.failureCounts['DETAIL_NO_DIALOG'], 1);
  });

  test('repository stores only successful normalized values', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createCanonicalProductionV15Tables(db);
    final repository = OfficialInvoiceDetailEnrichmentRepository(
      databaseProvider: () async => db,
      clock: () => DateTime.utc(2026, 6, 23, 8),
    );

    final stored = await repository.saveValidated(<OfficialInvoiceDetailEnrichment>[
      _validEnrichment(),
      OfficialInvoiceDetailEnrichment(
        requestedInvoiceNumber: 'ZZ00000001',
        invoiceNumber: 'ZZ00000001',
        selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
        fetchedAt: DateTime.utc(2026, 6, 23),
        success: false,
        invoiceIdentityMatches: true,
        detailTotalInternallyConsistent: false,
        detailTotalMatchesCsv: false,
        sellerIdentifierConsistent: true,
        lineItems: const <OfficialInvoiceDetailLineItem>[],
        errorCode: 'DETAIL_TOTAL_CSV_MISMATCH',
      ),
    ]);

    expect(stored, 1);
    final rows = await db.query('cloud_invoice_detail_enrichments');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['invoice_number'], 'AN90000007');
    expect(row['currency_code'], 'TWD');
    expect(
      row['selector_profile_version'],
      officialInvoiceDetailSelectorProfileVersion,
    );
    expect(row.keys, isNot(contains('cookie')));
    expect(row.keys, isNot(contains('html')));
    expect(row.keys, isNot(contains('dom')));
    expect(row.keys, isNot(contains('page_url')));
    expect(row.keys, isNot(contains('download_url')));

    final loaded = await repository.loadByInvoiceNumbers(<String>[
      'AN90000007',
      'ZZ00000001',
    ]);
    expect(loaded.keys, contains('AN90000007'));
    expect(loaded.keys, isNot(contains('ZZ00000001')));
    expect(
      loaded['AN90000007']!.exactTimestamp,
      DateTime(2026, 6, 18, 14, 35, 22),
    );
    expect(loaded['AN90000007']!.lineItems, hasLength(2));
  });

  test('official scripts support Bootstrap dialog lifecycle and typed failures', () {
    final inspect = buildOfficialInvoiceDetailTargetInspectionScript();
    final enrich = buildOfficialInvoiceDetailEnrichmentScript(
      scope: OfficialInvoiceDetailSelectionScope.selectedInvoices,
      handlerName: 'testHandler',
    );
    final cancel = buildOfficialInvoiceDetailCancellationScript();

    expect(inspect, contains('approvedOrigin'));
    expect(enrich, contains('.modal.in'));
    expect(enrich, contains('waitForDialogReady'));
    expect(enrich, contains('DETAIL_NO_DIALOG'));
    expect(enrich, contains('DETAIL_RENDER_TIMEOUT'));
    expect(enrich, contains('DETAIL_ITEM_TABLE_NOT_FOUND'));
    expect(enrich, contains('DETAIL_ITEM_ROW_PARSE_FAILED'));
    expect(enrich, contains('DETAIL_INVOICE_IDENTITY_MISMATCH'));
    expect(enrich, contains('DETAIL_TOTAL_CSV_MISMATCH'));
    expect(enrich, contains('cancelled'));
    expect(cancel, contains('cancelled = true'));

    final combined = '$inspect\n$enrich\n$cancel'.toLowerCase();
    expect(combined, isNot(contains('outerhtml')));
    expect(combined, isNot(contains('innerhtml')));
    expect(combined, isNot(contains('document.cookie')));
    expect(combined, isNot(contains('location.href')));
    expect(combined, isNot(contains('screenshot')));
    expect(combined, isNot(contains('localstorage')));
    expect(combined, isNot(contains('sessionstorage')));
  });

  test('prepared workspace exposes explicit-consent UI and strict origin guard', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_webview_page.dart',
    ).readAsStringSync();
    final sheet = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_sheet.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/features/invoice/lab/flutter_landing_webview_session_runtime.dart',
    ).readAsStringSync();
    final importService = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_import_service.dart',
    ).readAsStringSync();
    final promotion = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart',
    ).readAsStringSync();

    expect(page, contains('OfficialInvoiceDetailEnrichmentSheet'));
    expect(page, contains('補充官方發票明細'));
    expect(sheet, contains('failureCounts'));
    expect(sheet, contains('officialInvoiceDetailFailureLabel'));
    expect(runtime, contains('isApprovedOfficialPortalHttpsUri(uri)'));
    expect(runtime, contains('cancelOfficialInvoiceDetailEnrichment'));
    expect(importService, contains('CloudInvoiceTimeSource.officialDetailPage'));
    expect(
      importService,
      contains('CloudInvoiceCurrencySource.officialDetailPage'),
    );
    expect(promotion, contains("'time_precision': draft.timePrecision.name"));
    expect(promotion, contains("'currency_source': draft.currencySource.name"));
  });
}

CloudInvoiceCandidate _candidate() {
  return CloudInvoiceCandidate(
    source: CloudInvoiceCandidateSource.privateCloudResearch,
    status: CloudInvoiceCandidateStatus.pending,
    invoiceNumber: 'AN90000007',
    invoiceDate: DateTime(2026, 6, 18),
    sellerIdentifier: '31655572',
    sellerName: '測試零售股份有限公司甲門市',
    totalAmount: 47,
    carrierType: '手機條碼',
    carrierMaskedId: '/AB***12',
    fetchedAt: DateTime.utc(2026, 6, 23),
    lineItems: const <CloudInvoiceLineItem>[
      CloudInvoiceLineItem(name: 'CSV 品項', quantity: 1, unitPrice: 47, amount: 47),
    ],
  );
}

OfficialInvoiceDetailEnrichment _validEnrichment() {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: 'AN90000007',
    invoiceNumber: 'AN90000007',
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 23, 7, 30),
    success: true,
    invoiceIdentityMatches: true,
    detailTotalInternallyConsistent: true,
    detailTotalMatchesCsv: true,
    sellerIdentifierConsistent: true,
    lineItems: const <OfficialInvoiceDetailLineItem>[
      OfficialInvoiceDetailLineItem(
        name: '官方品項 A',
        quantity: 1,
        unitPrice: 25,
        amount: 25,
      ),
      OfficialInvoiceDetailLineItem(
        name: '官方品項 B',
        quantity: 1,
        unitPrice: 22,
        amount: 22,
      ),
    ],
    exactTimestamp: DateTime(2026, 6, 18, 14, 35, 22),
    currencyCode: 'TWD',
    officialStatus: '開立已確認',
    sellerIdentifier: '31655572',
    sellerName: '測試零售股份有限公司甲門市',
    expectedTotal: 47,
    detailTotal: 47,
    dialogDetected: true,
    summaryTableDetected: true,
    itemTableDetected: true,
    detectedItemRowCount: 2,
  );
}
