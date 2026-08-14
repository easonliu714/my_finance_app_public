import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_review_page.dart';

void main() {
  testWidgets('review page shows normalized invoice fields and line items', (
    tester,
  ) async {
    final result = OfficialInvoiceDetailBatchResult(
      requestedCount: 1,
      results: <OfficialInvoiceDetailEnrichment>[
        OfficialInvoiceDetailEnrichment(
          requestedInvoiceNumber: 'AN90000009',
          invoiceNumber: 'AN90000009',
          selectorProfileVersion: 2,
          fetchedAt: DateTime(2026, 6, 24, 13, 12),
          success: true,
          invoiceIdentityMatches: true,
          detailTotalInternallyConsistent: true,
          detailTotalMatchesCsv: true,
          sellerIdentifierConsistent: true,
          lineItems: const <OfficialInvoiceDetailLineItem>[
            OfficialInvoiceDetailLineItem(
              name: '測試商品 A',
              quantity: 2,
              unitPrice: 20,
              amount: 40,
            ),
            OfficialInvoiceDetailLineItem(
              name: '測試商品 B',
              quantity: 1,
              unitPrice: 7,
              amount: 7,
            ),
          ],
          exactTimestamp: DateTime(2026, 6, 18, 8, 5, 3),
          currencyCode: 'TWD',
          officialStatus: '開立已確認',
          sellerIdentifier: '31655572',
          sellerName: '測試商店',
          expectedTotal: 47,
          detailTotal: 47,
          dialogDetected: true,
          summaryTableDetected: true,
          itemTableDetected: true,
          detectedItemRowCount: 2,
        ),
      ],
      cancelled: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OfficialInvoiceDetailEnrichmentReviewPage(batchResult: result),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('官方明細內容審查'), findsOneWidget);
    expect(find.text('成功：1'), findsOneWidget);
    expect(find.text('AN90000009'), findsWidgets);
    expect(find.text('2026-06-18 08:05:03'), findsOneWidget);
    expect(find.text('測試商店'), findsOneWidget);
    expect(find.text('TWD 47'), findsWidgets);
    expect(find.textContaining('測試商品 A'), findsOneWidget);
    expect(find.textContaining('測試商品 B'), findsOneWidget);
    expect(find.text('發票號碼一致：通過'), findsOneWidget);
    expect(find.text('官方總額與查詢／CSV 一致：通過'), findsOneWidget);
  });

  testWidgets('review page shows typed failure and safe diagnostics', (
    tester,
  ) async {
    final result = OfficialInvoiceDetailBatchResult(
      requestedCount: 1,
      results: <OfficialInvoiceDetailEnrichment>[
        OfficialInvoiceDetailEnrichment(
          requestedInvoiceNumber: 'BD90000011',
          invoiceNumber: '',
          selectorProfileVersion: 2,
          fetchedAt: DateTime(2026, 6, 24, 13, 12),
          success: false,
          invoiceIdentityMatches: false,
          detailTotalInternallyConsistent: false,
          detailTotalMatchesCsv: false,
          sellerIdentifierConsistent: true,
          lineItems: const <OfficialInvoiceDetailLineItem>[],
          errorCode: 'DETAIL_ITEM_TABLE_NOT_FOUND',
          dialogDetected: true,
          summaryTableDetected: true,
          itemTableDetected: false,
          detectedItemRowCount: 0,
        ),
      ],
      cancelled: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OfficialInvoiceDetailEnrichmentReviewPage(batchResult: result),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('找不到官方消費明細表格'), findsOneWidget);
    expect(find.text('偵測到明細視窗'), findsOneWidget);
    expect(find.text('是'), findsWidgets);
    expect(find.text('偵測到品項表格'), findsOneWidget);
    expect(find.text('否'), findsWidgets);
  });

  test('LAB display version matches pubspec and review route is wired', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final config = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',
    ).readAsStringSync();
    final sheet = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_sheet.dart',
    ).readAsStringSync();
    final review = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_review_page.dart',
    ).readAsStringSync();

    final version = RegExp(
      r'^version:\s*(\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;

    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(config, contains("validationVersion = '$version'"));
    expect(sheet, contains('reviewButtonKey'));
    expect(sheet, contains('OfficialInvoiceDetailEnrichmentReviewPage'));
    expect(sheet, contains('await _openReview(completedResult)'));
    expect(review, contains('官方明細內容審查'));
    expect(review.toLowerCase(), isNot(contains('outerhtml')));
    expect(review.toLowerCase(), isNot(contains('document.cookie')));
    expect(review.toLowerCase(), isNot(contains('screenshot')));
  });
}
