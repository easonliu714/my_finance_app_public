import 'private_cloud_invoice_csv_reconciliation_preview.dart';

enum PrivateCloudInvoiceCsvReviewAction {
  skipAlreadyLinked,
  enrichExisting,
  keepSeparate,
  deferAccount,
}

class PrivateCloudInvoiceCsvReviewDecision {
  const PrivateCloudInvoiceCsvReviewDecision({
    required this.invoiceId,
    required this.action,
    this.transactionId,
    this.expectedTransactionFingerprint,
  });

  final String invoiceId;
  final PrivateCloudInvoiceCsvReviewAction action;
  final String? transactionId;
  final String? expectedTransactionFingerprint;
}

class PrivateCloudInvoiceCsvReviewSummary {
  const PrivateCloudInvoiceCsvReviewSummary({
    required this.alreadyLinkedSkippedCount,
    required this.selectedExistingCount,
    required this.keepSeparateCount,
    required this.unresolvedMatchCount,
    required this.deferredAccountCount,
    required this.blockedCount,
  });

  final int alreadyLinkedSkippedCount;
  final int selectedExistingCount;
  final int keepSeparateCount;
  final int unresolvedMatchCount;
  final int deferredAccountCount;
  final int blockedCount;
}

class PrivateCloudInvoiceCsvReconciliationReview {
  PrivateCloudInvoiceCsvReconciliationReview._({
    required this.preview,
    required Map<String, PrivateCloudInvoiceCsvReviewDecision> decisions,
  }) : _decisions = Map.unmodifiable(decisions);

  factory PrivateCloudInvoiceCsvReconciliationReview.fromPreview(
    PrivateCloudInvoiceCsvReconciliationPreview preview,
  ) {
    final decisions = <String, PrivateCloudInvoiceCsvReviewDecision>{};
    for (final item in preview.items) {
      if (item.isAlreadyLinked) {
        decisions[item.invoice.id] = PrivateCloudInvoiceCsvReviewDecision(
          invoiceId: item.invoice.id,
          action: PrivateCloudInvoiceCsvReviewAction.skipAlreadyLinked,
          transactionId: item.linkedTransaction?.transactionId,
          expectedTransactionFingerprint:
              item.linkedTransaction?.transactionFingerprint,
        );
      } else if (item.status ==
          PrivateCloudInvoiceCsvReconciliationStatus.unmatched) {
        decisions[item.invoice.id] = PrivateCloudInvoiceCsvReviewDecision(
          invoiceId: item.invoice.id,
          action: PrivateCloudInvoiceCsvReviewAction.deferAccount,
        );
      }
    }
    return PrivateCloudInvoiceCsvReconciliationReview._(
      preview: preview,
      decisions: decisions,
    );
  }

  final PrivateCloudInvoiceCsvReconciliationPreview preview;
  final Map<String, PrivateCloudInvoiceCsvReviewDecision> _decisions;

  Map<String, PrivateCloudInvoiceCsvReviewDecision> get decisions => _decisions;

  PrivateCloudInvoiceCsvReviewDecision? decisionFor(String invoiceId) {
    return _decisions[invoiceId];
  }

  PrivateCloudInvoiceCsvReconciliationReview beginAlreadyLinkedReview(
    String invoiceId,
  ) {
    final item = _item(invoiceId);
    if (!item.isAlreadyLinked) {
      throw StateError('INVOICE_NOT_ALREADY_LINKED');
    }
    final next = Map<String, PrivateCloudInvoiceCsvReviewDecision>.from(
      _decisions,
    )..remove(invoiceId);
    return PrivateCloudInvoiceCsvReconciliationReview._(
      preview: preview,
      decisions: next,
    );
  }

  PrivateCloudInvoiceCsvReconciliationReview restoreAlreadyLinkedSkip(
    String invoiceId,
  ) {
    final item = _item(invoiceId);
    final linked = item.linkedTransaction;
    if (!item.isAlreadyLinked || linked == null) {
      throw StateError('INVOICE_NOT_ALREADY_LINKED');
    }
    return _replace(
      PrivateCloudInvoiceCsvReviewDecision(
        invoiceId: invoiceId,
        action: PrivateCloudInvoiceCsvReviewAction.skipAlreadyLinked,
        transactionId: linked.transactionId,
        expectedTransactionFingerprint: linked.transactionFingerprint,
      ),
    );
  }

  PrivateCloudInvoiceCsvReconciliationReview selectExisting({
    required String invoiceId,
    required String transactionId,
  }) {
    final item = _item(invoiceId);
    if (!_canSelectExisting(item)) {
      throw StateError('INVOICE_NOT_MATCHABLE');
    }
    PrivateCloudInvoiceCsvTransactionMatch? selectedMatch;
    for (final match in item.matches) {
      if (match.transactionId == transactionId) {
        selectedMatch = match;
        break;
      }
    }
    if (selectedMatch == null) {
      throw StateError('TRANSACTION_NOT_IN_MATCH_SET');
    }
    return _replace(
      PrivateCloudInvoiceCsvReviewDecision(
        invoiceId: invoiceId,
        action: PrivateCloudInvoiceCsvReviewAction.enrichExisting,
        transactionId: transactionId,
        expectedTransactionFingerprint:
            selectedMatch.transactionFingerprint,
      ),
    );
  }

  PrivateCloudInvoiceCsvReconciliationReview keepSeparate(String invoiceId) {
    final item = _item(invoiceId);
    if (!_canKeepSeparate(item)) {
      throw StateError('INVOICE_NOT_REVIEWABLE_AS_SEPARATE');
    }
    return _replace(
      PrivateCloudInvoiceCsvReviewDecision(
        invoiceId: invoiceId,
        action: PrivateCloudInvoiceCsvReviewAction.keepSeparate,
      ),
    );
  }

  PrivateCloudInvoiceCsvReconciliationReview clearMatchDecision(
    String invoiceId,
  ) {
    final item = _item(invoiceId);
    if (!_canSelectExisting(item)) {
      throw StateError('INVOICE_NOT_MATCHABLE');
    }
    final next = Map<String, PrivateCloudInvoiceCsvReviewDecision>.from(
      _decisions,
    )..remove(invoiceId);
    return PrivateCloudInvoiceCsvReconciliationReview._(
      preview: preview,
      decisions: next,
    );
  }

  PrivateCloudInvoiceCsvReviewSummary get summary {
    var alreadyLinkedSkipped = 0;
    var selectedExisting = 0;
    var keepSeparate = 0;
    var unresolved = 0;
    var deferredAccount = 0;
    var blocked = 0;

    for (final item in preview.items) {
      if (item.status == PrivateCloudInvoiceCsvReconciliationStatus.blocked) {
        blocked += 1;
        continue;
      }
      if (item.status == PrivateCloudInvoiceCsvReconciliationStatus.unmatched) {
        deferredAccount += 1;
        continue;
      }

      final decision = _decisions[item.invoice.id];
      if (decision == null) {
        unresolved += 1;
      } else if (decision.action ==
          PrivateCloudInvoiceCsvReviewAction.skipAlreadyLinked) {
        alreadyLinkedSkipped += 1;
      } else if (decision.action ==
          PrivateCloudInvoiceCsvReviewAction.enrichExisting) {
        selectedExisting += 1;
      } else if (decision.action ==
          PrivateCloudInvoiceCsvReviewAction.keepSeparate) {
        keepSeparate += 1;
      }
    }

    return PrivateCloudInvoiceCsvReviewSummary(
      alreadyLinkedSkippedCount: alreadyLinkedSkipped,
      selectedExistingCount: selectedExisting,
      keepSeparateCount: keepSeparate,
      unresolvedMatchCount: unresolved,
      deferredAccountCount: deferredAccount,
      blockedCount: blocked,
    );
  }

  bool get allMatchRowsReviewed => summary.unresolvedMatchCount == 0;

  bool _canSelectExisting(PrivateCloudInvoiceCsvReconciliationItem item) {
    return item.isAlreadyLinked ||
        item.status ==
            PrivateCloudInvoiceCsvReconciliationStatus.uniqueExistingMatch ||
        item.status ==
            PrivateCloudInvoiceCsvReconciliationStatus.ambiguousExistingMatch;
  }

  bool _canKeepSeparate(PrivateCloudInvoiceCsvReconciliationItem item) {
    return !item.isAlreadyLinked &&
        (item.status ==
                PrivateCloudInvoiceCsvReconciliationStatus
                    .uniqueExistingMatch ||
            item.status ==
                PrivateCloudInvoiceCsvReconciliationStatus
                    .ambiguousExistingMatch);
  }

  PrivateCloudInvoiceCsvReconciliationItem _item(String invoiceId) {
    for (final item in preview.items) {
      if (item.invoice.id == invoiceId) {
        return item;
      }
    }
    throw StateError('INVOICE_NOT_FOUND');
  }

  PrivateCloudInvoiceCsvReconciliationReview _replace(
    PrivateCloudInvoiceCsvReviewDecision decision,
  ) {
    final next = Map<String, PrivateCloudInvoiceCsvReviewDecision>.from(
      _decisions,
    )..[decision.invoiceId] = decision;
    return PrivateCloudInvoiceCsvReconciliationReview._(
      preview: preview,
      decisions: next,
    );
  }
}
