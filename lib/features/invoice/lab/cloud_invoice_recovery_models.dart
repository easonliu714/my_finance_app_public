import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_reconciliation_models.dart';

enum CloudInvoiceRecoveryDisposition {
  notFound,
  completed,
  inProgress,
  retryable,
  requestConflict,
  manualReview,
}

class CloudInvoiceRecoveryInspection {
  const CloudInvoiceRecoveryInspection({
    required this.operationKey,
    required this.disposition,
    required this.message,
    this.status,
    this.action,
  });

  final String operationKey;
  final CloudInvoiceRecoveryDisposition disposition;
  final String message;
  final CloudInvoicePersistenceStatus? status;
  final CloudInvoiceReconciliationOutcome? action;

  bool get canRetryAutomatically =>
      disposition == CloudInvoiceRecoveryDisposition.retryable;

  bool get requiresManualReview =>
      disposition == CloudInvoiceRecoveryDisposition.manualReview ||
      disposition == CloudInvoiceRecoveryDisposition.requestConflict;
}
