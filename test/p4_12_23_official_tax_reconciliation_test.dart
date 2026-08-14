import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_v2_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_review_page.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_script.dart';

void main() {
  test('explicit official tax that exactly reconciles is standardized', () {
    final enrichment = OfficialInvoiceDetailEnrichment.fromJson(
      <String, Object?>{
        'requestedInvoiceNumber': 'GP00000200',
        'invoiceNumber': 'GP00000200',
        'selectorProfileVersion': officialInvoiceDetailSelectorProfileVersion,
        'fetchedAt': '2026-06-26T00:00:00Z',
        'success': true,
        'invoiceIdentityMatches': true,
        'detailTotalInternallyConsistent': true,
        'detailTotalMatchesCsv': true,
        'sellerIdentifierConsistent': true,
        'exactTimestamp': '2026-06-25T20:00:00',
        'currencyCode': 'TWD',
        'expectedTotal': 200,
        'detailTotal': 200,
        'officialTaxAmount': 10,
        'officialTaxLabel': '營業稅額',
        'lineItemSubtotal': 190,
        'unallocatedDifference': 0,
        'lineItems': <Object?>[
          <String, Object?>{
            'name': 'Example App Store 應用程式',
            'quantity': 1,
            'unitPrice': 190,
            'amount': 190,
          },
          <String, Object?>{
            'name': '官方稅額',
            'quantity': 1,
            'unitPrice': 10,
            'amount': 10,
          },
        ],
      },
    );

    expect(enrichment.hasExplicitOfficialTax, isTrue);
    expect(enrichment.officialTaxAmount, 10);
    expect(enrichment.officialTaxLabel, '營業稅額');
    expect(enrichment.lineItemSubtotal, 190);
    expect(enrichment.unallocatedDifference, 0);
    expect(enrichment.lineItems.last.name, '官方稅額');
    expect(isOfficialInvoiceDetailEligibleForFormalImport(enrichment), isTrue);

    final candidate = CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: 'GP00000200',
      invoiceDate: DateTime(2026, 6, 25),
      sellerIdentifier: '',
      sellerName: 'Example App Store',
      totalAmount: 200,
      carrierType: 'official-webview',
      carrierMaskedId: '****',
      fetchedAt: DateTime.utc(2026, 6, 26),
    );
    final upgraded = enrichment.applyValidatedValues(candidate);
    expect(upgraded.taxAmount, 10);
    expect(upgraded.lineItems, hasLength(2));
    expect(upgraded.lineItems.last.name, '官方稅額');
  });

  test('missing official tax exposes a user-confirmable estimate', () {
    final enrichment = _unallocatedDifference();

    expect(enrichment.success, isFalse);
    expect(enrichment.officialTaxAmount, isNull);
    expect(enrichment.lineItemSubtotal, 629);
    expect(enrichment.detailTotal, 660);
    expect(enrichment.unallocatedDifference, 31);
    expect(enrichment.positiveEstimatedTaxAmount, 31);
    expect(enrichment.canUseUserConfirmedEstimatedTax, isTrue);
    expect(isOfficialInvoiceDetailEligibleForFormalImport(enrichment), isFalse);
    expect(
      isOfficialInvoiceDetailEligibleForFormalImportV2(enrichment),
      isTrue,
    );

    final confirmed = withUserConfirmedEstimatedTax(enrichment);
    expect(confirmed.success, isTrue);
    expect(confirmed.detailTotalInternallyConsistent, isTrue);
    expect(confirmed.officialTaxAmount, 31);
    expect(confirmed.officialTaxLabel, '推算稅額（使用者確認）');
    expect(confirmed.lineItems.last.name, '推算稅額（使用者確認）');
    expect(confirmed.lineItems.last.amount, 31);
    expect(isOfficialInvoiceDetailEligibleForFormalImport(confirmed), isTrue);
  });

  testWidgets('review UI exposes subtotal tax source total and difference',
      (tester) async {
    final enrichment = _unallocatedDifference();
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialInvoiceDetailEnrichmentReviewPage(
          batchResult: OfficialInvoiceDetailBatchResult(
            requestedCount: 1,
            results: <OfficialInvoiceDetailEnrichment>[enrichment],
            cancelled: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('品項小計'), findsOneWidget);
    expect(find.text('官方稅額'), findsOneWidget);
    expect(find.text('稅額來源'), findsOneWidget);
    expect(find.text('未分配差額'), findsOneWidget);
    expect(find.text('TWD 629'), findsOneWidget);
    expect(find.text('TWD 660'), findsAtLeastNWidgets(1));
    expect(find.text('TWD 31'), findsAtLeastNWidgets(1));
    expect(find.text('官方頁面未提供'), findsOneWidget);
    expect(find.text('推算稅額（待確認）'), findsOneWidget);
    expect(
      find.byKey(
        OfficialInvoiceDetailEnrichmentReviewPage.formalImportButtonKey,
      ),
      findsOneWidget,
    );
  });

  test('selector contract uses only explicit official tax evidence', () {
    final script = buildOfficialInvoiceDetailEnrichmentScript(
      scope: OfficialInvoiceDetailSelectionScope.currentPage,
      handlerName: 'taxTestHandler',
    );

    expect(script, contains('findOfficialTax'));
    expect(script, contains("['營業稅額', '稅額', '稅']"));
    expect(script, contains("name: '官方稅額'"));
    expect(script, contains('officialTaxAmount'));
    expect(script, contains('officialTaxLabel'));
    expect(script, contains('lineItemSubtotal'));
    expect(script, contains('unallocatedDifference'));
    expect(script, contains('DETAIL_OFFICIAL_TAX_MISMATCH'));
    expect(script, contains('DETAIL_UNALLOCATED_DIFFERENCE'));
    expect(script, isNot(contains('0.05')));
    expect(script, isNot(contains('/ 1.05')));
  });
}

OfficialInvoiceDetailEnrichment _unallocatedDifference() {
  return OfficialInvoiceDetailEnrichment.fromJson(
    <String, Object?>{
      'requestedInvoiceNumber': 'GP00000660',
      'invoiceNumber': 'GP00000660',
      'selectorProfileVersion': officialInvoiceDetailSelectorProfileVersion,
      'fetchedAt': '2026-06-26T00:00:00Z',
      'success': false,
      'invoiceIdentityMatches': true,
      'detailTotalInternallyConsistent': false,
      'detailTotalMatchesCsv': true,
      'sellerIdentifierConsistent': true,
      'exactTimestamp': '2026-06-25T20:00:00',
      'currencyCode': 'TWD',
      'expectedTotal': 660,
      'detailTotal': 660,
      'officialTaxAmount': null,
      'officialTaxLabel': null,
      'lineItemSubtotal': 629,
      'unallocatedDifference': 31,
      'errorCode': 'DETAIL_UNALLOCATED_DIFFERENCE',
      'dialogDetected': true,
      'summaryTableDetected': true,
      'itemTableDetected': true,
      'detectedItemRowCount': 1,
      'lineItems': <Object?>[
        <String, Object?>{
          'name': 'Example App Store 應用程式',
          'quantity': 1,
          'unitPrice': 629,
          'amount': 629,
        },
      ],
    },
  );
}
