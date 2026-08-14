import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_inbox_page.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_unmatched_review.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';

void main() {
  test('safe bulk fill preserves an existing per-invoice account', () {
    var review = PrivateCloudInvoiceCsvUnmatchedReview.fromPreview(_preview())
        .selectAll()
        .assignInvoice(invoiceId: 'AA12345678', accountId: 'account-a');

    review = review.assignSelectedMissing('account-b');

    expect(review.accountIdFor('AA12345678'), 'account-a');
    expect(review.accountIdFor('BB12345678'), 'account-b');
    expect(review.missingAccountCount, 0);
    expect(review.canSubmit, isTrue);

    review = review.assignSelected('account-c');
    expect(review.accountIdFor('AA12345678'), 'account-c');
    expect(review.accountIdFor('BB12345678'), 'account-c');
  });

  test('prepared CSV page contains the lower safe bulk-action panel', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_csv_import_page.dart',
    ).readAsStringSync();

    expect(source, contains('清單底部快速套用帳戶'));
    expect(source, contains('unmatchedApplyMissingBottomKey'));
    expect(source, contains('assignSelectedMissing'));
    expect(source, contains('不會覆蓋逐筆選擇'));
    expect(source, contains('覆蓋全部'));
  });

  testWidgets('cloud invoice inbox displays persisted pending drafts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CloudInvoiceInboxPage(
          port: _FakeInboxPort([_draft()]),
          onOpenDraftPromotion: () => opened = true,
          onManualEntry: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('雲端發票工作箱'), findsOneWidget);
    expect(find.text('1 筆等待覆核'), findsOneWidget);
    expect(find.text('覆核 1 筆發票'), findsOneWidget);
    expect(find.text('測試商家'), findsOneWidget);
    expect(find.text('資料與安全邊界'), findsNothing);

    final help = find.byKey(CloudInvoiceInboxPage.reviewHelpKey);
    await tester.scrollUntilVisible(
      help,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('雲端發票覆核說明'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    final promotionButton = find.byKey(CloudInvoiceInboxPage.promotionKey);
    await tester.scrollUntilVisible(
      promotionButton,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(promotionButton);
    await tester.pump();
    expect(opened, isTrue);
  });
}

PrivateCloudInvoiceCsvReconciliationPreview _preview() {
  return const PrivateCloudInvoiceCsvReconciliationPreviewBuilder().build(
    csvPreview: OfficialCloudInvoiceCsvPreview(
      invoices: [_invoice('AA12345678'), _invoice('BB12345678')],
      fileIssues: const [],
      detailRowCount: 2,
      repairedRowCount: 0,
      ignoredFooterCount: 0,
      earliestInvoiceDate: DateTime.utc(2026, 6, 23),
      latestInvoiceDate: DateTime.utc(2026, 6, 23),
    ),
    localTransactions: const [],
  );
}

OfficialCloudInvoiceCsvInvoicePreview _invoice(String id) {
  return OfficialCloudInvoiceCsvInvoicePreview(
    id: id,
    carrierName: '手機條碼',
    invoiceStatus: '開立已確認',
    discountFlag: '',
    sellerAddress: '',
    buyerIdentifier: '',
    detailRowCount: 1,
    issues: const [],
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: id,
      invoiceDate: DateTime.utc(2026, 6, 23),
      sellerIdentifier: '12345678',
      sellerName: '測試商家',
      totalAmount: 47,
      carrierType: 'official-csv',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 23),
      lineItems: const [CloudInvoiceLineItem(name: '測試品項', amount: 47)],
    ),
  );
}

PrivateCloudInvoiceDraftCandidate _draft() {
  return PrivateCloudInvoiceDraftCandidate(
    id: 'draft-1',
    operationKey: 'operation-1',
    candidateReference: 'candidate-1',
    accountId: 'account-1',
    accountName: '現金',
    amount: 47,
    invoiceDate: DateTime.utc(2026, 6, 23),
    currencyCode: 'TWD',
    invoiceNumber: 'AA12345678',
    sellerIdentifier: '12345678',
    sellerName: '測試商家',
    lineItems: const [CloudInvoiceLineItem(name: '測試品項', amount: 47)],
    createdAt: DateTime.utc(2026, 6, 23),
  );
}

class _FakeInboxPort implements CloudInvoiceInboxPort {
  _FakeInboxPort(this.drafts);

  final List<PrivateCloudInvoiceDraftCandidate> drafts;

  @override
  Future<List<PrivateCloudInvoiceDraftCandidate>> listPendingDrafts() async {
    return drafts;
  }
}
