import 'cloud_invoice_candidate.dart';
import 'invoice_import_staging.dart';

class CloudInvoiceStagingAdapterError implements Exception {
  const CloudInvoiceStagingAdapterError(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudInvoiceStagingAdapter {
  const CloudInvoiceStagingAdapter();

  InvoiceImportStagingItem toStagingItem({
    required CloudInvoiceCandidate candidate,
    required String id,
  }) {
    if (!_canConvert(candidate)) {
      throw const CloudInvoiceStagingAdapterError('Only pending or duplicate cloud invoice candidates can become staging items.');
    }
    return InvoiceImportStagingItem(
      id: id,
      source: InvoiceImportStagingSource.externalSource,
      invoiceNumber: candidate.invoiceNumber,
      invoiceDate: candidate.invoiceDate,
      sellerName: candidate.displaySellerName,
      totalAmount: candidate.totalAmount,
      taxAmount: candidate.taxAmount,
      note: _noteFor(candidate),
      rawPayload: candidate.rawPayload,
      status: _statusFor(candidate),
    );
  }

  bool canCreateFormalTransactionAutomatically(CloudInvoiceCandidate candidate) => false;

  bool _canConvert(CloudInvoiceCandidate candidate) {
    return candidate.status == CloudInvoiceCandidateStatus.pending || candidate.status == CloudInvoiceCandidateStatus.duplicate;
  }

  InvoiceImportStagingStatus _statusFor(CloudInvoiceCandidate candidate) {
    switch (candidate.status) {
      case CloudInvoiceCandidateStatus.pending:
        return InvoiceImportStagingStatus.pending;
      case CloudInvoiceCandidateStatus.duplicate:
        return InvoiceImportStagingStatus.duplicate;
      case CloudInvoiceCandidateStatus.rejected:
      case CloudInvoiceCandidateStatus.retryableError:
      case CloudInvoiceCandidateStatus.confirmedDraft:
      case CloudInvoiceCandidateStatus.discarded:
      case CloudInvoiceCandidateStatus.blocked:
        throw const CloudInvoiceStagingAdapterError('Unsupported cloud invoice candidate status.');
    }
  }

  String _noteFor(CloudInvoiceCandidate candidate) {
    final parts = <String>['雲端發票 mock 匯入候選'];
    if (candidate.hasWarnings) {
      parts.add('需人工補齊');
    }
    if (candidate.status == CloudInvoiceCandidateStatus.duplicate) {
      parts.add('疑似重複');
    }
    return parts.join('｜');
  }
}
