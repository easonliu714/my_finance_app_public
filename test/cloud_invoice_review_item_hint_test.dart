import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_review_page.dart';

void main() {
  testWidgets('CloudInvoiceReviewPage renders line item hint labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CloudInvoiceReviewPage(
          candidates: <CloudInvoiceCandidate>[
            CloudInvoiceCandidate(
              source: CloudInvoiceCandidateSource.mockCloudInvoice,
              status: CloudInvoiceCandidateStatus.pending,
              invoiceNumber: 'AB12345678',
              invoiceDate: DateTime(2026, 6, 9),
              sellerIdentifier: '12345678',
              sellerName: '測試便利商店',
              totalAmount: 120,
              carrierType: 'mobileBarcode',
              carrierMaskedId: '/AB***12',
              fetchedAt: DateTime.utc(2026, 6, 10, 8),
              lineItems: const <CloudInvoiceLineItem>[
                CloudInvoiceLineItem(name: '咖啡', amount: 55, categorySuggestion: '餐飲'),
                CloudInvoiceLineItem(name: '茶葉蛋', amount: 15, categorySuggestion: '早餐'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('項目提示：咖啡：餐飲、茶葉蛋：早餐'), findsOneWidget);
  });
}
