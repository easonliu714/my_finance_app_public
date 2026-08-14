import 'dart:io';

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

  test('invoice identity normalization is canonical before lookup', () {
    expect(normalizeCloudInvoiceNumber(' ab-1234 5678 '), 'AB12345678');
  });

  test('exactly one metadata link to one existing transaction is skipped', () {
    final linkedTransaction = _transaction(id: 'txn-linked', amount: 320);
    final preview = builder.build(
      csvPreview: _csvPreview(_invoice('ab-1234 5678', 320)),
      localTransactions: const <TransactionRecord>[],
      existingLinksByInvoiceNumber:
          <String, PrivateCloudInvoiceCsvExistingLinkLookup>{
            'AB12345678': PrivateCloudInvoiceCsvExistingLinkLookup(
              normalizedInvoiceNumber: 'AB12345678',
              linkCount: 1,
              matches: <PrivateCloudInvoiceCsvTransactionMatch>[
                _match(linkedTransaction),
              ],
            ),
          },
    );

    expect(preview.alreadyLinkedCount, 1);
    expect(preview.uniqueMatchCount, 0);
    expect(preview.unmatchedCount, 0);
    expect(preview.items.single.isAlreadyLinked, isTrue);
    expect(preview.items.single.isDefaultSkipped, isTrue);
    expect(preview.items.single.linkedTransaction?.transactionId, 'txn-linked');
    expect(privateCloudInvoiceCsvAlreadyLinkedLabel, '已存在且已連結交易（預設略過）');
  });

  test(
    'multiple or broken metadata links fail closed before date matching',
    () {
      final transaction = _transaction(id: 'txn-1', amount: 75);
      final preview = builder.build(
        csvPreview: _csvPreview(_invoice('AB12345678', 75)),
        localTransactions: <TransactionRecord>[transaction],
        existingLinksByInvoiceNumber:
            <String, PrivateCloudInvoiceCsvExistingLinkLookup>{
              'AB12345678': PrivateCloudInvoiceCsvExistingLinkLookup(
                normalizedInvoiceNumber: 'AB12345678',
                linkCount: 2,
                matches: <PrivateCloudInvoiceCsvTransactionMatch>[
                  _match(transaction),
                ],
              ),
            },
      );

      expect(preview.alreadyLinkedCount, 0);
      expect(preview.uniqueMatchCount, 0);
      expect(preview.blockedCount, 1);
      expect(
        preview.items.single.blockReason,
        PrivateCloudInvoiceCsvBlockReason.brokenOrAmbiguousCanonicalLink,
      );
    },
  );

  test(
    'already-linked review defaults to skip and supports explicit re-review',
    () {
      final transaction = _transaction(id: 'txn-linked', amount: 90);
      final preview = builder.build(
        csvPreview: _csvPreview(_invoice('BS90000016', 90)),
        localTransactions: const <TransactionRecord>[],
        existingLinksByInvoiceNumber:
            <String, PrivateCloudInvoiceCsvExistingLinkLookup>{
              'BS90000016': PrivateCloudInvoiceCsvExistingLinkLookup(
                normalizedInvoiceNumber: 'BS90000016',
                linkCount: 1,
                matches: <PrivateCloudInvoiceCsvTransactionMatch>[
                  _match(transaction),
                ],
              ),
            },
      );

      final initial = PrivateCloudInvoiceCsvReconciliationReview.fromPreview(
        preview,
      );
      expect(initial.summary.alreadyLinkedSkippedCount, 1);
      expect(initial.summary.unresolvedMatchCount, 0);
      expect(
        initial.decisionFor('BS90000016')?.action,
        PrivateCloudInvoiceCsvReviewAction.skipAlreadyLinked,
      );

      final reviewing = initial.beginAlreadyLinkedReview('BS90000016');
      expect(reviewing.summary.alreadyLinkedSkippedCount, 0);
      expect(reviewing.summary.unresolvedMatchCount, 1);
      expect(reviewing.allMatchRowsReviewed, isFalse);

      final restored = reviewing.restoreAlreadyLinkedSkip('BS90000016');
      expect(restored.summary.alreadyLinkedSkippedCount, 1);
      expect(restored.allMatchRowsReviewed, isTrue);
    },
  );

  test(
    'service source queries metadata links and blocks protected draft import',
    () {
      final source = File(
        'lib/features/invoice/lab/private_cloud_invoice_csv_import_service.dart',
      ).readAsStringSync();

      expect(source, contains('cloud_invoice_metadata_links'));
      expect(source, contains('_loadExistingLinks'));
      expect(source, contains('CSV_CANONICAL_LINK_REVIEW_REQUIRED'));
      expect(source, contains('existingLinksByInvoiceNumber'));
      expect(source, contains('cloud_invoice_drafts'));
      expect(source, contains('cloud_invoice_draft_promotions'));
      expect(source, contains('CSV_INVOICE_DRAFT_ALREADY_PENDING'));
    },
  );
}

OfficialCloudInvoiceCsvPreview _csvPreview(
  OfficialCloudInvoiceCsvInvoicePreview invoice,
) {
  return OfficialCloudInvoiceCsvPreview(
    invoices: <OfficialCloudInvoiceCsvInvoicePreview>[invoice],
    fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
    detailRowCount: 1,
    repairedRowCount: 0,
    ignoredFooterCount: 0,
    earliestInvoiceDate: DateTime.utc(2026, 6, 17),
    latestInvoiceDate: DateTime.utc(2026, 6, 17),
  );
}

OfficialCloudInvoiceCsvInvoicePreview _invoice(
  String invoiceNumber,
  double amount,
) {
  return OfficialCloudInvoiceCsvInvoicePreview(
    id: normalizeCloudInvoiceNumber(invoiceNumber),
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
      invoiceNumber: invoiceNumber,
      invoiceDate: DateTime.utc(2026, 6, 17),
      sellerIdentifier: '12345678',
      sellerName: '測試商家',
      totalAmount: amount,
      carrierType: 'official-csv',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 27),
      lineItems: <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '測試品項', amount: amount),
      ],
    ),
  );
}

TransactionRecord _transaction({required String id, required double amount}) {
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

PrivateCloudInvoiceCsvTransactionMatch _match(TransactionRecord transaction) {
  return PrivateCloudInvoiceCsvTransactionMatch(
    transactionId: transaction.id,
    transactionFingerprint: 'fp-${transaction.id}',
    accountName: transaction.accountName,
    merchantName: transaction.merchantName,
    occurredAt: transaction.occurredAt,
    amount: transaction.amount,
  );
}
