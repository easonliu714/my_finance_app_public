import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_import_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_unmatched_draft_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_unmatched_review.dart';

void main() {
  test('bulk account assignment supports per-invoice override', () {
    final preview = _preview();
    var review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(preview);

    expect(review.items, hasLength(3));
    expect(review.canSubmit, isFalse);

    review = review.selectAll().assignSelected('account-a');
    expect(review.selectedCount, 3);
    expect(review.missingAccountCount, 0);
    expect(review.canSubmit, isTrue);

    review = review.assignInvoice(
      invoiceId: 'CC12345678',
      accountId: 'account-b',
    );
    final grouped = review.selectedInvoiceIdsByAccount();
    expect(grouped['account-a'], {'AA12345678', 'BB12345678'});
    expect(grouped['account-b'], {'CC12345678'});
  });

  test('selected invoice without account blocks submission', () {
    final preview = _preview();
    var review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(preview);

    review = review.toggle('AA12345678');
    expect(review.selectedCount, 1);
    expect(review.missingAccountCount, 1);
    expect(review.canSubmit, isFalse);
    expect(review.selectedInvoiceIdsByAccount, throwsStateError);
  });

  test('explicit deferral keeps only selected invoices with accounts', () {
    final preview = _preview();
    var review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(
      preview,
    ).selectAll();

    review = review.assignInvoice(
      invoiceId: 'AA12345678',
      accountId: 'account-a',
    );
    review = review.assignInvoice(
      invoiceId: 'CC12345678',
      accountId: 'account-b',
    );

    expect(review.selectedCount, 3);
    expect(review.assignedSelectedCount, 2);
    expect(review.missingAccountCount, 1);
    expect(review.deferredCount, 0);
    expect(review.canDeferMissingAccounts, isTrue);
    expect(review.canSubmit, isFalse);

    review = review.deferSelectedWithoutAccount();

    expect(review.selectedInvoiceIds, {'AA12345678', 'CC12345678'});
    expect(review.selectedCount, 2);
    expect(review.assignedSelectedCount, 2);
    expect(review.missingAccountCount, 0);
    expect(review.deferredCount, 1);
    expect(review.canDeferMissingAccounts, isFalse);
    expect(review.canSubmit, isTrue);
    expect(review.selectedInvoiceIdsByAccount()['account-a'], {'AA12345678'});
    expect(review.selectedInvoiceIdsByAccount()['account-b'], {'CC12345678'});
  });

  test('deferring an entirely unassigned selection leaves no submission', () {
    final preview = _preview();
    final review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(
      preview,
    ).selectAll().deferSelectedWithoutAccount();

    expect(review.selectedCount, 0);
    expect(review.deferredCount, 3);
    expect(review.canSubmit, isFalse);
  });

  test('draft service groups selected invoices by account', () async {
    final preview = _preview();
    var review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(
      preview,
    ).selectAll().assignSelected('account-a');
    review = review.assignInvoice(
      invoiceId: 'CC12345678',
      accountId: 'account-b',
    );
    final fake = _FakeImportPort();
    final service = PrivateCloudInvoiceCsvUnmatchedDraftService(
      importPort: fake,
    );

    final summary = await service.execute(
      preview: preview.csvPreview,
      review: review,
      accounts: const [
        AccountRecord(
          id: 'account-a',
          name: '現金',
          type: AccountType.cash,
          initialBalance: 0,
          sortOrder: 0,
        ),
        AccountRecord(
          id: 'account-b',
          name: '信用卡',
          type: AccountType.creditCard,
          initialBalance: 0,
          sortOrder: 1,
        ),
      ],
      confirmed: true,
    );

    expect(fake.calls, hasLength(2));
    expect(
      fake.calls
          .firstWhere((call) => call.account.id == 'account-a')
          .invoiceIds,
      {'AA12345678', 'BB12345678'},
    );
    expect(
      fake.calls
          .firstWhere((call) => call.account.id == 'account-b')
          .invoiceIds,
      {'CC12345678'},
    );
    expect(summary.committedCount, 3);
    expect(summary.replayCount, 0);
    expect(summary.pendingDraftIds, {
      'draft-AA12345678',
      'draft-BB12345678',
      'draft-CC12345678',
    });
    expect(summary.transactionCountUnchanged, isTrue);
  });

  test('draft service requires final confirmation', () async {
    final preview = _preview();
    final review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(
      preview,
    ).toggle('AA12345678').assignSelected('account-a');
    final service = PrivateCloudInvoiceCsvUnmatchedDraftService(
      importPort: _FakeImportPort(),
    );

    await expectLater(
      service.execute(
        preview: preview.csvPreview,
        review: review,
        accounts: const [
          AccountRecord(
            id: 'account-a',
            name: '現金',
            type: AccountType.cash,
            initialBalance: 0,
            sortOrder: 0,
          ),
        ],
        confirmed: false,
      ),
      throwsStateError,
    );
  });
}

PrivateCloudInvoiceCsvReconciliationPreview _preview() {
  final invoices = <OfficialCloudInvoiceCsvInvoicePreview>[
    _invoice('AA12345678', 100, '早餐店'),
    _invoice('BB12345678', 200, '超商'),
    _invoice('CC12345678', 300, '書店'),
    _blockedInvoice('MASKED'),
  ];
  return const PrivateCloudInvoiceCsvReconciliationPreviewBuilder().build(
    csvPreview: OfficialCloudInvoiceCsvPreview(
      invoices: invoices,
      fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
      detailRowCount: 4,
      repairedRowCount: 0,
      ignoredFooterCount: 0,
      earliestInvoiceDate: DateTime.utc(2026, 6, 17),
      latestInvoiceDate: DateTime.utc(2026, 6, 17),
    ),
    localTransactions: const [],
  );
}

OfficialCloudInvoiceCsvInvoicePreview _invoice(
  String id,
  double amount,
  String seller,
) {
  return OfficialCloudInvoiceCsvInvoicePreview(
    id: id,
    carrierName: '手機條碼',
    invoiceStatus: '正常',
    discountFlag: '',
    sellerAddress: '',
    buyerIdentifier: '',
    detailRowCount: 2,
    issues: const <OfficialCloudInvoiceCsvIssue>[],
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: id,
      invoiceDate: DateTime.utc(2026, 6, 17),
      sellerIdentifier: '12345678',
      sellerName: seller,
      totalAmount: amount,
      carrierType: 'official-csv',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 20),
      lineItems: [
        CloudInvoiceLineItem(name: '品項一', amount: amount / 2),
        CloudInvoiceLineItem(name: '品項二', amount: amount / 2),
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
    issues: const [
      OfficialCloudInvoiceCsvIssue(
        code: OfficialCloudInvoiceCsvIssueCode.maskedInvoiceNumber,
        message: 'masked',
        isBlocking: true,
      ),
    ],
  );
}

class _ImportCall {
  const _ImportCall({required this.invoiceIds, required this.account});

  final Set<String> invoiceIds;
  final AccountRecord account;
}

class _FakeImportPort implements PrivateCloudInvoiceCsvImportPort {
  final List<_ImportCall> calls = [];

  @override
  Future<PrivateCloudInvoiceCsvImportSummary> importDrafts({
    required OfficialCloudInvoiceCsvPreview preview,
    required Set<String> invoiceIds,
    required AccountRecord account,
  }) async {
    calls.add(_ImportCall(invoiceIds: invoiceIds, account: account));
    return PrivateCloudInvoiceCsvImportSummary(
      results: invoiceIds
          .map(
            (invoiceId) => CloudInvoicePersistenceResult(
              status: CloudInvoicePersistenceStatus.committed,
              operationKey: 'operation-$invoiceId-${account.id}',
              message: 'DRAFT_CREATED',
              accountId: account.id,
              draftId: 'draft-$invoiceId',
            ),
          )
          .toList(growable: false),
      transactionCountUnchanged: true,
    );
  }

  @override
  Future<PrivateCloudInvoiceCsvSource?> pickAndPreview() async {
    throw UnimplementedError();
  }

  @override
  Future<PrivateCloudInvoiceCsvReconciliationPreview>
  buildReconciliationPreview(OfficialCloudInvoiceCsvPreview preview) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AccountRecord>> listActiveAccounts() async {
    throw UnimplementedError();
  }
}
