import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_review_page.dart';

void main() {
  testWidgets('CloudInvoiceReviewPage renders invoice and fetch time summary labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CloudInvoiceReviewPage(
          candidates: <CloudInvoiceCandidate>[
            CloudInvoiceCandidate(
              source: CloudInvoiceCandidateSource.mockCloudInvoice,
              status: CloudInvoiceCandidateStatus.pending,
              invoiceNumber: 'AB12345678',
              invoiceDate: DateTime(2026, 6, 9, 14, 35),
              sellerIdentifier: '12345678',
              sellerName: '測試便利商店',
              totalAmount: 120,
              carrierType: 'mobileBarcode',
              carrierMaskedId: '/AB***12',
              fetchedAt: DateTime.utc(2026, 6, 10, 8, 5),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('發票日期：2026-06-09'), findsOneWidget);
    expect(find.text('發票時間：14:35'), findsOneWidget);
    expect(find.text('取得日期：2026-06-10'), findsOneWidget);
    expect(find.text('取得時間：08:05'), findsOneWidget);
  });
}
