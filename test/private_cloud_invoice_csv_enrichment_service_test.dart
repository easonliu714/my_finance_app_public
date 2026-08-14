import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_enrichment_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_review.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  test('confirmed selected match builds metadata-only enrichment request', () async {
    CloudInvoicePersistenceRequest? captured;
    final service = PrivateCloudInvoiceCsvEnrichmentService(
      persistenceExecutor: (request) async {
        captured = request;
        return CloudInvoicePersistenceResult(
          status: CloudInvoicePersistenceStatus.committed,
          operationKey: request.operationKey,
          message: 'METADATA_ENRICHED',
          transactionId: request.decision.selectedTransactionId,
        );
      },
      clock: () => DateTime.utc(2026, 6, 19, 8),
    );
    final transaction = _transaction('txn-1', 320);
    final review = _review(
      invoices: [_invoice('AB12345678', 320)],
      transactions: [transaction],
    ).selectExisting(
      invoiceId: 'AB12345678',
      transactionId: 'txn-1',
    );

    final summary = await service.executeConfirmed(
      review: review,
      finalConfirmation: true,
    );

    expect(summary.committedCount, 1);
    expect(captured, isNotNull);
    expect(
      captured!.decision.action,
      CloudInvoiceReconciliationOutcome.enrichExisting,
    );
    expect(captured!.decision.selectedTransactionId, 'txn-1');
    expect(captured!.decision.selectedAccountId, isNull);
    expect(captured!.decision.merchantProposalConfirmed, isFalse);
    expect(
      captured!.expectedTransactionFingerprint,
      transactionFingerprint(transaction),
    );
    expect(captured!.facts.candidate.invoiceNumber, 'AB12345678');
    expect(captured!.facts.candidate.lineItems.single.name, '測試品項');
  });

  test('final confirmation is required before persistence', () async {
    var calls = 0;
    final service = PrivateCloudInvoiceCsvEnrichmentService(
      persistenceExecutor: (request) async {
        calls += 1;
        return CloudInvoicePersistenceResult(
          status: CloudInvoicePersistenceStatus.committed,
          operationKey: request.operationKey,
          message: 'METADATA_ENRICHED',
        );
      },
    );
    final review = _review(
      invoices: [_invoice('AB12345678', 320)],
      transactions: [_transaction('txn-1', 320)],
    ).selectExisting(
      invoiceId: 'AB12345678',
      transactionId: 'txn-1',
    );

    await expectLater(
      service.executeConfirmed(review: review, finalConfirmation: false),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test('keep-separate and unmatched rows are not executed', () async {
    var calls = 0;
    final service = PrivateCloudInvoiceCsvEnrichmentService(
      persistenceExecutor: (request) async {
        calls += 1;
        return CloudInvoicePersistenceResult(
          status: CloudInvoicePersistenceStatus.committed,
          operationKey: request.operationKey,
          message: 'METADATA_ENRICHED',
        );
      },
    );
    final review = _review(
      invoices: [
        _invoice('AB12345678', 320),
        _invoice('CD12345678', 999),
      ],
      transactions: [_transaction('txn-1', 320)],
    ).keepSeparate('AB12345678');

    final summary = await service.executeConfirmed(
      review: review,
      finalConfirmation: true,
    );

    expect(calls, 0);
    expect(summary.rows, isEmpty);
  });

  test('summary reports committed replay conflict and rejected outcomes', () async {
    final statuses = <CloudInvoicePersistenceStatus>[
      CloudInvoicePersistenceStatus.committed,
      CloudInvoicePersistenceStatus.alreadyApplied,
      CloudInvoicePersistenceStatus.conflict,
      CloudInvoicePersistenceStatus.preflightRejected,
    ];
    var index = 0;
    final service = PrivateCloudInvoiceCsvEnrichmentService(
      persistenceExecutor: (request) async {
        final status = statuses[index++];
        return CloudInvoicePersistenceResult(
          status: status,
          operationKey: request.operationKey,
          message: status.name,
          transactionId: request.decision.selectedTransactionId,
        );
      },
    );
    var review = _review(
      invoices: [
        _invoice('AA12345678', 100),
        _invoice('BB12345678', 200),
        _invoice('CC12345678', 300),
        _invoice('DD12345678', 400),
      ],
      transactions: [
        _transaction('txn-1', 100),
        _transaction('txn-2', 200),
        _transaction('txn-3', 300),
        _transaction('txn-4', 400),
      ],
    );
    review = review
        .selectExisting(invoiceId: 'AA12345678', transactionId: 'txn-1')
        .selectExisting(invoiceId: 'BB12345678', transactionId: 'txn-2')
        .selectExisting(invoiceId: 'CC12345678', transactionId: 'txn-3')
        .selectExisting(invoiceId: 'DD12345678', transactionId: 'txn-4');

    final summary = await service.executeConfirmed(
      review: review,
      finalConfirmation: true,
    );

    expect(summary.committedCount, 1);
    expect(summary.replayCount, 1);
    expect(summary.conflictCount, 1);
    expect(summary.rejectedCount, 1);
  });
}

PrivateCloudInvoiceCsvReconciliationReview _review({
  required List<OfficialCloudInvoiceCsvInvoicePreview> invoices,
  required List<TransactionRecord> transactions,
}) {
  final preview = const PrivateCloudInvoiceCsvReconciliationPreviewBuilder().build(
    csvPreview: OfficialCloudInvoiceCsvPreview(
      invoices: invoices,
      fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
      detailRowCount: invoices.length,
      repairedRowCount: 0,
      ignoredFooterCount: 0,
      earliestInvoiceDate: DateTime.utc(2026, 6, 17),
      latestInvoiceDate: DateTime.utc(2026, 6, 17),
    ),
    localTransactions: transactions,
  );
  return PrivateCloudInvoiceCsvReconciliationReview.fromPreview(preview);
}

OfficialCloudInvoiceCsvInvoicePreview _invoice(String id, double amount) {
  return OfficialCloudInvoiceCsvInvoicePreview(
    id: id,
    carrierName: '手機條碼',
    invoiceStatus: '正常',
    discountFlag: '',
    sellerAddress: '',
    buyerIdentifier: '',
    detailRowCount: 1,
    issues: const <OfficialCloudInvoiceCsvIssue>[],
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: id,
      invoiceDate: DateTime.utc(2026, 6, 17),
      sellerIdentifier: '12345678',
      sellerName: '測試商家',
      totalAmount: amount,
      carrierType: 'official-csv',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 19),
      lineItems: [CloudInvoiceLineItem(name: '測試品項', amount: amount)],
    ),
  );
}

TransactionRecord _transaction(String id, double amount) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    category: '餐飲',
    occurredAt: DateTime.utc(2026, 6, 17, 12),
    accountName: '信用卡',
    memberName: '本人',
    merchantName: '既有商家',
    tagName: '',
    note: '',
    currency: CurrencyCode.twd,
  );
}
