import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_review_page.dart';
import 'package:my_finance_app/routing/app_router.dart';

void main() {
  test('cloud invoice review route metadata is registered', () {
    expect(CloudInvoiceReviewPage.routeName, 'cloud-invoice-review');
    expect(CloudInvoiceReviewPage.routePath, '/invoice/cloud/review');
    expect(appRouter.namedLocation(CloudInvoiceReviewPage.routeName), CloudInvoiceReviewPage.routePath);
  });
}
