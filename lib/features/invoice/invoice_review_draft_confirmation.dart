import 'invoice_import_staging.dart';
import 'manual_invoice_draft.dart';

class InvoiceReviewDraftConfirmationResult {
  const InvoiceReviewDraftConfirmationResult({
    required this.originalItem,
    required this.convertedItem,
    required this.draft,
  });

  final InvoiceImportStagingItem originalItem;
  final InvoiceImportStagingItem convertedItem;
  final ManualInvoiceDraft draft;

  bool get createsFormalTransaction => false;
  bool get createsDraftOnly => draft.status == ManualInvoiceDraftStatus.readyToReview && !createsFormalTransaction;
}

class InvoiceReviewDraftConfirmationService {
  InvoiceReviewDraftConfirmationService({DateTime Function()? clock}) : _stagingService = InvoiceImportStagingService(clock: clock);

  final InvoiceImportStagingService _stagingService;

  InvoiceReviewDraftConfirmationResult confirmAcceptedItem({
    required InvoiceImportStagingItem item,
    required String draftId,
  }) {
    final draft = _stagingService.convertAcceptedItem(item: item, draftId: draftId);
    final convertedItem = _stagingService.markConverted(item);
    return InvoiceReviewDraftConfirmationResult(
      originalItem: item,
      convertedItem: convertedItem,
      draft: draft,
    );
  }
}
