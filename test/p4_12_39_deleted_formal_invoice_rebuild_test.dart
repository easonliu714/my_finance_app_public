import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_v2_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('deleted formal transaction reopens the original draft safely', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    await createCanonicalProductionV16Tables(db);

    final invoiceTime = DateTime(2026, 6, 29, 19, 29, 2);
    final createdAt = DateTime(2026, 6, 30).toIso8601String();

    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'draft-bg93433474',
      'operation_key': 'draft-operation-bg93433474',
      'candidate_reference': 'candidate-bg93433474',
      'account_id': '',
      'account_name': '',
      'account_resolution_status': 'unresolved',
      'amount': 2.33,
      'invoice_date': invoiceTime.toIso8601String(),
      'time_precision': 'exactDateTime',
      'time_source': 'officialDetailPage',
      'currency_code': 'USD',
      'currency_source': 'officialDetailPage',
      'merchant_id': null,
      'invoice_number': 'BG90000012',
      'seller_identifier': '42541892',
      'seller_name': 'Example Labs, Inc.',
      'tax_amount': null,
      'line_items_json': '[]',
      'payload_version': 1,
      'created_at': createdAt,
    });
    await db.insert('cloud_invoice_draft_promotions', <String, Object?>{
      'draft_id': 'draft-bg93433474',
      'promotion_key': 'promotion-bg93433474',
      'draft_operation_key': 'draft-operation-bg93433474',
      'draft_fingerprint': 'fingerprint-bg93433474',
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
      'candidate_reference': 'candidate-bg93433474',
      'invoice_number': 'BG90000012',
      'seller_identifier': '42541892',
      'seller_name': 'Example Labs, Inc.',
      'invoice_date': invoiceTime.toIso8601String(),
      'time_precision': 'exactDateTime',
      'time_source': 'officialDetailPage',
      'currency_code': 'USD',
      'currency_source': 'officialDetailPage',
      'tax_amount': null,
      'merchant_id': null,
      'line_items_json': '[]',
      'payload_version': 1,
      'created_at': createdAt,
    });

    final batch = OfficialInvoiceDetailBatchResult(
      requestedCount: 1,
      results: <OfficialInvoiceDetailEnrichment>[
        OfficialInvoiceDetailEnrichment(
          requestedInvoiceNumber: 'BG90000012',
          invoiceNumber: 'BG90000012',
          selectorProfileVersion: 6,
          fetchedAt: DateTime(2026, 7, 1, 21, 24, 23),
          success: true,
          invoiceIdentityMatches: true,
          detailTotalInternallyConsistent: true,
          detailTotalMatchesCsv: true,
          sellerIdentifierConsistent: true,
          lineItems: const <OfficialInvoiceDetailLineItem>[
            OfficialInvoiceDetailLineItem(
              name: 'GitHub Actions Usage',
              quantity: 1,
              unitPrice: 2.33,
              amount: 2.33,
            ),
          ],
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
    expect(preflight.alreadyFormalItems, isEmpty);
    expect(preflight.selectableItems, hasLength(1));

    final summary = await service.stageDrafts(
      batchResult: batch,
      invoiceNumbers: const <String>{'BG90000012'},
      confirmedEstimatedTaxInvoiceNumbers: const <String>{},
      account: null,
      finalConfirmation: true,
    );

    expect(summary.transactionCountUnchanged, isTrue);
    expect(summary.pendingDraftIds, contains('draft-bg93433474'));
    expect(await db.query('transactions'), isEmpty);
    expect(await db.query('cloud_invoice_metadata_links'), isEmpty);
    expect(await db.query('cloud_invoice_draft_promotions'), isEmpty);
    expect(await db.query('cloud_invoice_drafts'), hasLength(1));
  });
}
