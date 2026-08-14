import '../../account/account_record.dart';
import 'cloud_invoice_persistence_models.dart';
import 'official_cloud_invoice_csv_adapter.dart';
import 'private_cloud_invoice_csv_import_service.dart';
import 'private_cloud_invoice_csv_unmatched_review.dart';

class PrivateCloudInvoiceCsvUnmatchedDraftSummary {
  const PrivateCloudInvoiceCsvUnmatchedDraftSummary({
    required this.results,
    required this.transactionCountUnchanged,
    this.invoiceNumberByOperationKey = const <String, String>{},
  });

  final List<CloudInvoicePersistenceResult> results;
  final bool transactionCountUnchanged;
  final Map<String, String> invoiceNumberByOperationKey;

  int get committedCount => results
      .where((item) => item.status == CloudInvoicePersistenceStatus.committed)
      .length;

  int get replayCount => results
      .where(
        (item) => item.status == CloudInvoicePersistenceStatus.alreadyApplied,
      )
      .length;

  int get rejectedCount => results.length - committedCount - replayCount;

  Set<String> get pendingDraftIds => results
      .where(
        (item) =>
            item.draftId != null &&
            (item.status == CloudInvoicePersistenceStatus.committed ||
                item.status == CloudInvoicePersistenceStatus.alreadyApplied),
      )
      .map((item) => item.draftId!)
      .toSet();

  List<CloudInvoicePersistenceResult> get failedResults => results
      .where(
        (item) =>
            item.status != CloudInvoicePersistenceStatus.committed &&
            item.status != CloudInvoicePersistenceStatus.alreadyApplied,
      )
      .toList(growable: false);

  String invoiceNumberFor(CloudInvoicePersistenceResult result) =>
      invoiceNumberByOperationKey[result.operationKey] ?? result.operationKey;
}

class PrivateCloudInvoiceCsvUnmatchedDraftService {
  const PrivateCloudInvoiceCsvUnmatchedDraftService({required this.importPort});

  final PrivateCloudInvoiceCsvImportPort importPort;

  Future<PrivateCloudInvoiceCsvUnmatchedDraftSummary> execute({
    required OfficialCloudInvoiceCsvPreview preview,
    required PrivateCloudInvoiceCsvUnmatchedReview review,
    required List<AccountRecord> accounts,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw StateError('CONFIRMATION_REQUIRED');
    }
    if (!review.canSubmit) {
      throw StateError('ACCOUNT_ASSIGNMENT_INCOMPLETE');
    }

    final accountsById = <String, AccountRecord>{
      for (final account in accounts) account.id: account,
    };
    final results = <CloudInvoicePersistenceResult>[];
    final invoiceNumberByOperationKey = <String, String>{};
    var transactionCountUnchanged = true;

    for (final entry in review.selectedInvoiceIdsByAccount().entries) {
      final account = accountsById[entry.key];
      if (account == null || account.isArchived) {
        throw StateError('ACCOUNT_NOT_AVAILABLE');
      }
      final summary = await importPort.importDrafts(
        preview: preview,
        invoiceIds: entry.value,
        account: account,
      );
      results.addAll(summary.results);
      invoiceNumberByOperationKey.addAll(summary.invoiceNumberByOperationKey);
      transactionCountUnchanged =
          transactionCountUnchanged && summary.transactionCountUnchanged;
    }

    return PrivateCloudInvoiceCsvUnmatchedDraftSummary(
      results: List<CloudInvoicePersistenceResult>.unmodifiable(results),
      transactionCountUnchanged: transactionCountUnchanged,
      invoiceNumberByOperationKey: Map<String, String>.unmodifiable(
        invoiceNumberByOperationKey,
      ),
    );
  }
}
