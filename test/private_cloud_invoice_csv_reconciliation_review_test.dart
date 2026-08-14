import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_review.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const builder = PrivateCloudInvoiceCsvReconciliationPreviewBuilder();

  test('unique match requires explicit selection or keep-separate decision', () {
    final preview = builder.build(
      csvPreview: _csvPreview([_invoice('AB12345678', 320)]),
      localTransactions: [_transaction('txn-1', 320)],
    );

    var review = PrivateCloudInvoiceCsvReconciliationReview.fromPreview(preview);
    expect(review.summary.unresolvedMatchCount, 1);
    expect(review.allMatchRowsReviewed, isFalse);

    review = review.selectExisting(
      invoiceId: 'AB12345678',
      transactionId: 'txn-1',
    );
    expect(review.summary.selectedExistingCount, 1);
    expect(review.summary.unresolvedMatchCount, 0);
    expect(review.allMatchRowsReviewed, isTrue);

    review = review.keepSeparate('AB12345678');
    expect(review.summary.selectedExistingCount, 0);
    expect(review.summary.keepSeparateCount, 1);
  });

  test('ambiguous match only accepts a transaction in the match set', () {
    final preview = builder.build(
      csvPreview: _csvPreview([_invoice('AB12345678', 75)]),
      localTransactions: [
        _transaction('txn-1', 75),
        _transaction('txn-2', 75),
      ],
    );
    final review = PrivateCloudInvoiceCsvReconciliationReview.fromPreview(preview);

    expect(
      () => review.selectExisting(
        invoiceId: 'AB12345678',
        transactionId: 'txn-outside',
      ),
      throwsStateError,
    );

    final selected = review.selectExisting(
      invoiceId: 'AB12345678',
      transactionId: 'txn-2',
    );
    expect(selected.decisionFor('AB12345678')?.transactionId, 'txn-2');
  });

  test('unmatched is deferred and blocked row cannot receive decisions', () {
    final preview = builder.build(
      csvPreview: _csvPreview([
        _invoice('AB12345678', 99),
        _blockedInvoice('MASKED'),
      ]),
      localTransactions: const <TransactionRecord>[],
    );
    final review = PrivateCloudInvoiceCsvReconciliationReview.fromPreview(preview);

    expect(review.summary.deferredAccountCount, 1);
    expect(review.summary.blockedCount, 1);
    expect(
      review.decisionFor('AB12345678')?.action,
      PrivateCloudInvoiceCsvReviewAction.deferAccount,
    );
    expect(() => review.keepSeparate('MASKED'), throwsStateError);
  });

  test('clearing a match decision restores unresolved state', () {
    final preview = builder.build(
      csvPreview: _csvPreview([_invoice('AB12345678', 320)]),
      localTransactions: [_transaction('txn-1', 320)],
    );
    final review = PrivateCloudInvoiceCsvReconciliationReview.fromPreview(preview)
        .selectExisting(
      invoiceId: 'AB12345678',
      transactionId: 'txn-1',
    );

    final cleared = review.clearMatchDecision('AB12345678');
    expect(cleared.decisionFor('AB12345678'), isNull);
    expect(cleared.summary.unresolvedMatchCount, 1);
  });
}

OfficialCloudInvoiceCsvPreview _csvPreview(
  List<OfficialCloudInvoiceCsvInvoicePreview> invoices,
) {
  return OfficialCloudInvoiceCsvPreview(
    invoices: invoices,
    fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
    detailRowCount: invoices.length,
    repairedRowCount: 0,
    ignoredFooterCount: 0,
    earliestInvoiceDate: DateTime.utc(2026, 6, 17),
    latestInvoiceDate: DateTime.utc(2026, 6, 17),
  );
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

OfficialCloudInvoiceCsvInvoicePreview _blockedInvoice(String id) {
  return OfficialCloudInvoiceCsvInvoicePreview(
    id: id,
    carrierName: '手機條碼',
    invoiceStatus: '異常',
    discountFlag: '',
    sellerAddress: '',
    buyerIdentifier: '',
    detailRowCount: 1,
    issues: const <OfficialCloudInvoiceCsvIssue>[
      OfficialCloudInvoiceCsvIssue(
        code: OfficialCloudInvoiceCsvIssueCode.maskedInvoiceNumber,
        message: 'masked',
        isBlocking: true,
      ),
    ],
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
    merchantName: '測試商家',
    tagName: '',
    note: '',
    currency: CurrencyCode.twd,
  );
}
