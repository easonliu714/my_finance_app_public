import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const builder = PrivateCloudInvoiceCsvReconciliationPreviewBuilder();

  test('unique same-date same-amount expense is matched without account input', () {
    final preview = builder.build(
      csvPreview: _csvPreview([
        _invoice(
          id: 'AB12345678',
          amount: 320,
          date: DateTime.utc(2026, 6, 17),
        ),
      ]),
      localTransactions: [
        _transaction(
          id: 'txn-1',
          amount: 320,
          occurredAt: DateTime.utc(2026, 6, 17, 20, 30),
          accountName: '信用卡',
        ),
      ],
    );

    expect(preview.requiresAccountSelectionNow, isFalse);
    expect(preview.uniqueMatchCount, 1);
    expect(preview.ambiguousMatchCount, 0);
    expect(preview.unmatchedCount, 0);
    final item = preview.items.single;
    expect(item.canEnrichExisting, isTrue);
    expect(item.requiresAccountLater, isFalse);
    expect(item.matches.single.transactionId, 'txn-1');
    expect(item.matches.single.accountName, '信用卡');
  });

  test('multiple same-date same-amount expenses are ambiguous', () {
    final preview = builder.build(
      csvPreview: _csvPreview([
        _invoice(
          id: 'AB12345678',
          amount: 75,
          date: DateTime.utc(2026, 6, 17),
        ),
      ]),
      localTransactions: [
        _transaction(id: 'txn-1', amount: 75),
        _transaction(id: 'txn-2', amount: 75),
      ],
    );

    expect(preview.uniqueMatchCount, 0);
    expect(preview.ambiguousMatchCount, 1);
    expect(preview.items.single.requiresUserMatchChoice, isTrue);
    expect(preview.items.single.matches, hasLength(2));
  });

  test('no same-date same-amount expense defers account handling', () {
    final preview = builder.build(
      csvPreview: _csvPreview([
        _invoice(
          id: 'AB12345678',
          amount: 629,
          date: DateTime.utc(2026, 6, 17),
        ),
      ]),
      localTransactions: [
        _transaction(id: 'txn-1', amount: 628),
        _transaction(
          id: 'txn-2',
          amount: 629,
          occurredAt: DateTime.utc(2026, 6, 18),
        ),
      ],
    );

    expect(preview.unmatchedCount, 1);
    expect(preview.items.single.requiresAccountLater, isTrue);
    expect(preview.items.single.matches, isEmpty);
  });

  test('non-expense and blocked invoices are not matched', () {
    final preview = builder.build(
      csvPreview: _csvPreview([
        _invoice(
          id: 'AB12345678',
          amount: 100,
          date: DateTime.utc(2026, 6, 17),
        ),
        _blockedInvoice('MASKED'),
      ]),
      localTransactions: [
        _transaction(id: 'transfer-1', amount: 100, type: TransactionType.transfer),
      ],
    );

    expect(preview.unmatchedCount, 1);
    expect(preview.blockedCount, 1);
    expect(preview.items.first.requiresAccountLater, isTrue);
    expect(preview.items.last.isBlocked, isTrue);
  });
}

OfficialCloudInvoiceCsvPreview _csvPreview(
  List<OfficialCloudInvoiceCsvInvoicePreview> invoices,
) {
  return OfficialCloudInvoiceCsvPreview(
    invoices: invoices,
    fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
    detailRowCount: invoices.fold<int>(
      0,
      (sum, invoice) => sum + invoice.detailRowCount,
    ),
    repairedRowCount: 0,
    ignoredFooterCount: 0,
    earliestInvoiceDate: DateTime.utc(2026, 6, 17),
    latestInvoiceDate: DateTime.utc(2026, 6, 17),
  );
}

OfficialCloudInvoiceCsvInvoicePreview _invoice({
  required String id,
  required double amount,
  required DateTime date,
}) {
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
      invoiceDate: date,
      sellerIdentifier: '12345678',
      sellerName: '測試商家',
      totalAmount: amount,
      carrierType: 'official-csv',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 19),
      lineItems: [
        CloudInvoiceLineItem(name: '測試品項', amount: amount),
      ],
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

TransactionRecord _transaction({
  required String id,
  required double amount,
  DateTime? occurredAt,
  String accountName = '現金',
  TransactionType type = TransactionType.expense,
}) {
  return TransactionRecord(
    id: id,
    type: type,
    amount: amount,
    category: type == TransactionType.expense ? '餐飲' : '轉帳',
    occurredAt: occurredAt ?? DateTime.utc(2026, 6, 17, 12),
    accountName: accountName,
    memberName: '本人',
    merchantName: '測試商家',
    tagName: '',
    note: '',
    currency: CurrencyCode.twd,
  );
}
