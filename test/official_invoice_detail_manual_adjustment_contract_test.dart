import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_v2_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';

void main() {
  test('unallocated difference can enter explicit reviewable draft path', () {
    final item = OfficialInvoiceDetailEnrichment(
      requestedInvoiceNumber: 'DC30740436',
      invoiceNumber: 'DC30740436',
      selectorProfileVersion: 1,
      fetchedAt: DateTime.utc(2026, 9, 25),
      success: false,
      invoiceIdentityMatches: true,
      detailTotalInternallyConsistent: false,
      detailTotalMatchesCsv: true,
      sellerIdentifierConsistent: true,
      lineItems: const <OfficialInvoiceDetailLineItem>[
        OfficialInvoiceDetailLineItem(
          name: 'fixture',
          quantity: 1,
          unitPrice: 90,
          amount: 90,
        ),
      ],
      exactTimestamp: DateTime(2026, 8, 1, 12),
      currencyCode: 'TWD',
      sellerIdentifier: '12345678',
      sellerName: 'fixture',
      detailTotal: 100,
      lineItemSubtotal: 90,
      unallocatedDifference: 5,
      errorCode: 'DETAIL_UNALLOCATED_DIFFERENCE',
    );

    expect(item.canUseUserConfirmedEstimatedTax, isFalse);
    expect(isOfficialInvoiceDetailManualDifferenceReviewCandidate(item), isTrue);
    expect(isOfficialInvoiceDetailEligibleForReviewableDraft(item), isFalse);
    expect(isOfficialInvoiceDetailEligibleForFormalImportV2(item), isTrue);
    final confirmed = withUserConfirmedManualDifferenceReview(item);
    expect(
      isOfficialInvoiceDetailConfirmedManualDifferenceDraft(confirmed),
      isTrue,
    );
    expect(
      isOfficialInvoiceDetailEligibleForReviewableDraft(confirmed),
      isTrue,
    );
    final preflight = OfficialInvoiceDetailImportPreflightItem(
      enrichment: item,
      status: OfficialInvoiceDetailImportPreflightStatus.selectable,
    );
    expect(preflight.requiresManualDifferenceConfirmation, isTrue);
  });
}
