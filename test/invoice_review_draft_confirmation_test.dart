import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_import_staging.dart';
import 'package:my_finance_app/features/invoice/invoice_review_draft_confirmation.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';

void main() {
  test('confirmAcceptedItem converts accepted staging item into draft only', () {
    final service = InvoiceReviewDraftConfirmationService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final accepted = _stagingItem(id: 'item-1', status: InvoiceImportStagingStatus.accepted);

    final result = service.confirmAcceptedItem(item: accepted, draftId: 'draft-1');

    expect(result.originalItem.status, InvoiceImportStagingStatus.accepted);
    expect(result.convertedItem.status, InvoiceImportStagingStatus.converted);
    expect(result.convertedItem.updatedAt, DateTime.utc(2026, 6, 10, 8, 0));
    expect(result.draft.id, 'draft-1');
    expect(result.draft.status, ManualInvoiceDraftStatus.readyToReview);
    expect(result.draft.invoiceNumber, 'AB12345678');
    expect(result.draft.invoiceDate, DateTime(2026, 6, 9, 14, 35));
    expect(result.draft.sellerName, '測試便利商店');
    expect(result.draft.totalAmount, 120);
    expect(result.draft.createdAt, DateTime.utc(2026, 6, 10, 8, 0));
    expect(result.createsFormalTransaction, isFalse);
    expect(result.createsDraftOnly, isTrue);
  });

  test('confirmAcceptedItem rejects non-accepted staging item', () {
    final service = InvoiceReviewDraftConfirmationService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));

    expect(
      () => service.confirmAcceptedItem(item: _stagingItem(id: 'item-1'), draftId: 'draft-1'),
      throwsA(isA<InvoiceImportStagingTransitionError>()),
    );
  });

  test('confirmAcceptedItem does not allow duplicate candidate to bypass review', () {
    final service = InvoiceReviewDraftConfirmationService(clock: () => DateTime.utc(2026, 6, 10, 8, 0));
    final duplicate = _stagingItem(id: 'item-1', status: InvoiceImportStagingStatus.duplicate);

    expect(duplicate.requiresUserReview, isTrue);
    expect(
      () => service.confirmAcceptedItem(item: duplicate, draftId: 'draft-1'),
      throwsA(isA<InvoiceImportStagingTransitionError>()),
    );
  });
}

InvoiceImportStagingItem _stagingItem({required String id, InvoiceImportStagingStatus status = InvoiceImportStagingStatus.pending}) {
  return InvoiceImportStagingItem(
    id: id,
    source: InvoiceImportStagingSource.qrParser,
    invoiceNumber: 'AB12345678',
    invoiceDate: DateTime(2026, 6, 9, 14, 35),
    sellerName: '測試便利商店',
    totalAmount: 120,
    taxAmount: 6,
    note: 'QR 匯入候選',
    rawPayload: 'raw-qr-payload',
    status: status,
  );
}
