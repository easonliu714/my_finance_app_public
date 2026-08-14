import 'canonical_cloud_invoice_persistence_service.dart';
import 'cloud_invoice_persistence_models.dart';
import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_reconciliation_review_decision.dart';
import 'private_cloud_invoice_csv_reconciliation_review.dart';

typedef PrivateCloudInvoiceCsvPersistenceExecutor =
    Future<CloudInvoicePersistenceResult> Function(
      CloudInvoicePersistenceRequest request,
    );

class PrivateCloudInvoiceCsvEnrichmentRowResult {
  const PrivateCloudInvoiceCsvEnrichmentRowResult({
    required this.invoiceId,
    required this.transactionId,
    required this.result,
  });

  final String invoiceId;
  final String transactionId;
  final CloudInvoicePersistenceResult result;
}

class PrivateCloudInvoiceCsvEnrichmentSummary {
  const PrivateCloudInvoiceCsvEnrichmentSummary({
    required this.rows,
  });

  final List<PrivateCloudInvoiceCsvEnrichmentRowResult> rows;

  int get committedCount => rows
      .where(
        (row) => row.result.status == CloudInvoicePersistenceStatus.committed,
      )
      .length;

  int get replayCount => rows
      .where(
        (row) =>
            row.result.status == CloudInvoicePersistenceStatus.alreadyApplied,
      )
      .length;

  int get conflictCount => rows
      .where(
        (row) => row.result.status == CloudInvoicePersistenceStatus.conflict,
      )
      .length;

  int get rejectedCount => rows
      .where(
        (row) =>
            row.result.status ==
                CloudInvoicePersistenceStatus.preflightRejected ||
            row.result.status == CloudInvoicePersistenceStatus.failed ||
            row.result.status == CloudInvoicePersistenceStatus.rollbackFailed,
      )
      .length;
}

abstract interface class PrivateCloudInvoiceCsvEnrichmentPort {
  Future<PrivateCloudInvoiceCsvEnrichmentSummary> executeConfirmed({
    required PrivateCloudInvoiceCsvReconciliationReview review,
    required bool finalConfirmation,
  });
}

class PrivateCloudInvoiceCsvEnrichmentService
    implements PrivateCloudInvoiceCsvEnrichmentPort {
  PrivateCloudInvoiceCsvEnrichmentService({
    PrivateCloudInvoiceCsvPersistenceExecutor? persistenceExecutor,
    DateTime Function()? clock,
  })  : _persistenceExecutor = persistenceExecutor ??
            CanonicalCloudInvoicePersistenceService().execute,
        _clock = clock ?? DateTime.now;

  final PrivateCloudInvoiceCsvPersistenceExecutor _persistenceExecutor;
  final DateTime Function() _clock;

  @override
  Future<PrivateCloudInvoiceCsvEnrichmentSummary> executeConfirmed({
    required PrivateCloudInvoiceCsvReconciliationReview review,
    required bool finalConfirmation,
  }) async {
    if (!finalConfirmation) {
      throw StateError('ENRICHMENT_CONFIRMATION_REQUIRED');
    }
    if (!review.allMatchRowsReviewed) {
      throw StateError('REVIEW_NOT_COMPLETE');
    }

    final rows = <PrivateCloudInvoiceCsvEnrichmentRowResult>[];
    for (final item in review.preview.items) {
      final decision = review.decisionFor(item.invoice.id);
      if (decision?.action !=
          PrivateCloudInvoiceCsvReviewAction.enrichExisting) {
        continue;
      }

      final candidate = item.invoice.candidate;
      final transactionId = decision!.transactionId;
      final expectedFingerprint = decision.expectedTransactionFingerprint;
      if (candidate == null ||
          transactionId == null ||
          transactionId.trim().isEmpty ||
          expectedFingerprint == null ||
          expectedFingerprint.trim().isEmpty) {
        throw StateError('INCOMPLETE_ENRICHMENT_DECISION');
      }

      final now = _clock().toUtc();
      final request = CloudInvoicePersistenceRequest(
        facts: CloudInvoiceCandidateFacts(
          candidate: candidate,
          timePrecision: CloudInvoiceTimePrecision.dateOnly,
          timeSource: CloudInvoiceTimeSource.unknown,
          currencyCode: null,
          currencySource: CloudInvoiceCurrencySource.unknown,
        ),
        decision: CloudInvoiceReconciliationReviewDecision(
          action: CloudInvoiceReconciliationOutcome.enrichExisting,
          selectedTransactionId: transactionId,
          selectedAccountId: null,
          merchantProposalReviewed: true,
          merchantProposalConfirmed: false,
          replacementSecondConfirmationCompleted: false,
          candidateReference: candidate.duplicateKey,
          decidedAt: now,
        ),
        expectedTransactionFingerprint: expectedFingerprint,
        requestedAt: now,
      );
      final result = await _persistenceExecutor(request);
      rows.add(
        PrivateCloudInvoiceCsvEnrichmentRowResult(
          invoiceId: item.invoice.id,
          transactionId: transactionId,
          result: result,
        ),
      );
    }

    return PrivateCloudInvoiceCsvEnrichmentSummary(
      rows: List<PrivateCloudInvoiceCsvEnrichmentRowResult>.unmodifiable(rows),
    );
  }
}
