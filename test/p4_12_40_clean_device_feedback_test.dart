import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_v2_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_script.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'hidden checked rows are recognized and selected targets sort first',
    () {
      final inspection = buildOfficialInvoiceDetailTargetInspectionScript();
      final enrichment = buildOfficialInvoiceDetailEnrichmentScript(
        scope: OfficialInvoiceDetailSelectionScope.selectedInvoices,
        handlerName: 'p4-12-40-handler',
      );
      for (final source in <String>[inspection, enrichment]) {
        expect(source, contains("element.matches(':checked')"));
        expect(source, contains("data-state') === 'checked'"));
        expect(
          source,
          isNot(contains(').filter(rendered);\n      targets.push')),
        );
      }
      expect(inspection, contains('targets.sort((left, right) =>'));
      expect(officialInvoiceDetailSelectorProfileVersion, 7);
    },
  );

  test('reopened draft replaces 11 stale rows with 62 official rows', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    await createCanonicalProductionV16Tables(db);

    final invoiceTime = DateTime(2026, 6, 29, 19, 29, 2);
    final createdAt = DateTime(2026, 6, 30).toIso8601String();
    const candidateReference = 'BG90000012|2026-06-29|2|42541892';
    final oldItems = List<CloudInvoiceLineItem>.generate(
      11,
      (index) => CloudInvoiceLineItem(
        name: '舊明細 ${index + 1}',
        amount: index == 0 ? 2.33 : 0,
      ),
    );
    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'draft-bg93433474',
      'operation_key': 'draft-operation-bg93433474',
      'candidate_reference': candidateReference,
      'account_id': '',
      'account_name': '',
      'account_resolution_status': 'unresolved',
      'amount': 2.33,
      'invoice_date': invoiceTime.toIso8601String(),
      'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
      'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
      'currency_code': 'USD',
      'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
      'merchant_id': null,
      'invoice_number': 'BG90000012',
      'seller_identifier': '42541892',
      'seller_name': 'Example Labs, Inc.',
      'tax_amount': null,
      'line_items_json': encodeCloudInvoiceLineItems(oldItems),
      'payload_version': canonicalCloudInvoicePayloadVersion,
      'created_at': createdAt,
    });
    await db.insert('cloud_invoice_draft_promotions', <String, Object?>{
      'draft_id': 'draft-bg93433474',
      'promotion_key': 'promotion-bg93433474',
      'draft_operation_key': 'draft-operation-bg93433474',
      'draft_fingerprint': 'old-fingerprint',
      'transaction_id': 'deleted-transaction-bg93433474',
      'category': '電子數碼',
      'member_name': '自己',
      'tag_name': '日常',
      'note': '',
      'created_at': createdAt,
    });
    await db.insert('cloud_invoice_metadata_links', <String, Object?>{
      'id': 'metadata-bg93433474',
      'operation_key': 'metadata-operation-bg93433474',
      'transaction_id': 'deleted-transaction-bg93433474',
      'candidate_reference': candidateReference,
      'invoice_number': 'BG90000012',
      'seller_identifier': '42541892',
      'seller_name': 'Example Labs, Inc.',
      'invoice_date': invoiceTime.toIso8601String(),
      'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
      'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
      'currency_code': 'USD',
      'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
      'tax_amount': null,
      'merchant_id': null,
      'line_items_json': encodeCloudInvoiceLineItems(oldItems),
      'payload_version': canonicalCloudInvoicePayloadVersion,
      'created_at': createdAt,
    });

    final latestItems = List<OfficialInvoiceDetailLineItem>.generate(
      62,
      (index) => OfficialInvoiceDetailLineItem(
        name: '最新明細 ${index + 1}',
        quantity: index == 0 ? 1 : 0,
        unitPrice: index == 0 ? 2.33 : 0,
        amount: index == 0 ? 2.33 : 0,
      ),
    );
    final batch = OfficialInvoiceDetailBatchResult(
      requestedCount: 1,
      results: <OfficialInvoiceDetailEnrichment>[
        OfficialInvoiceDetailEnrichment(
          requestedInvoiceNumber: 'BG90000012',
          invoiceNumber: 'BG90000012',
          selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
          fetchedAt: DateTime(2026, 7, 2),
          success: true,
          invoiceIdentityMatches: true,
          detailTotalInternallyConsistent: true,
          detailTotalMatchesCsv: true,
          sellerIdentifierConsistent: true,
          lineItems: latestItems,
          exactTimestamp: invoiceTime,
          currencyCode: 'USD',
          officialStatus: '已確認',
          sellerIdentifier: '42541892',
          sellerName: 'Example Labs, Inc.',
          expectedTotal: 2.33,
          detailTotal: 2.33,
          lineItemSubtotal: 2.33,
          unallocatedDifference: 0,
        ),
      ],
      cancelled: false,
    );
    final service = OfficialInvoiceDetailDraftImportV2Service(
      databaseProvider: () async => db,
    );
    final preflight = await service.loadPreflight(batch);
    expect(preflight.rebuildableDeletedItems, hasLength(1));

    final summary = await service.stageDrafts(
      batchResult: batch,
      invoiceNumbers: const <String>{'BG90000012'},
      confirmedEstimatedTaxInvoiceNumbers: const <String>{},
      account: null,
      finalConfirmation: true,
    );
    expect(summary.transactionCountUnchanged, isTrue);
    final rows = await db.query(
      'cloud_invoice_drafts',
      where: 'id = ?',
      whereArgs: const <Object?>['draft-bg93433474'],
    );
    final refreshed = decodeCloudInvoiceLineItems(
      rows.single['line_items_json'] as String,
    );
    expect(refreshed, hasLength(62));
    expect(refreshed.first.name, '最新明細 1');
    expect(await db.query('transactions'), isEmpty);
    expect(await db.query('cloud_invoice_metadata_links'), isEmpty);
    expect(await db.query('cloud_invoice_draft_promotions'), isEmpty);
  });
}
