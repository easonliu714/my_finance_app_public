import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_review_page.dart';

void main() {
  testWidgets('CloudInvoiceReviewPage renders source detail label', (tester) async {
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
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('來源：模擬雲端發票'), findsOneWidget);
    expect(find.text('載具：/AB***12'), findsOneWidget);
  });
}
