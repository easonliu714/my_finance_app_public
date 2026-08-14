import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_mock_provider.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_review_page.dart';

void main() {
  testWidgets('CloudInvoiceReviewPage renders review-first summary and candidate sections', (tester) async {
    await _pumpPage(
      tester,
      candidates: <CloudInvoiceCandidate>[
        _candidate(confidence: 0.87),
        _candidate(status: CloudInvoiceCandidateStatus.duplicate, invoiceNumber: 'CD87654321'),
      ],
    );

    expect(find.text('雲端發票覆核'), findsOneWidget);
    expect(find.byKey(CloudInvoiceReviewPage.safetyBannerKey), findsOneWidget);
    expect(find.text('待確認 1 筆｜疑似重複 1 筆｜需處理 0 筆'), findsOneWidget);
    expect(find.textContaining('不會自動建立正式交易'), findsOneWidget);
    expect(find.byKey(CloudInvoiceReviewPage.pendingSectionKey), findsOneWidget);
    expect(find.byKey(CloudInvoiceReviewPage.duplicateSectionKey), findsOneWidget);
    expect(find.text('AB12345678'), findsOneWidget);
    expect(find.text('CD87654321'), findsOneWidget);
    expect(find.text('狀態：待確認'), findsOneWidget);
    expect(find.text('狀態：疑似重複'), findsOneWidget);
    expect(find.text('發票日期：2026-06-09'), findsNWidgets(2));
    expect(find.text('取得日期：2026-06-10'), findsNWidgets(2));
    expect(find.text('信心值：87%'), findsOneWidget);
    expect(find.text('確認為本機草稿'), findsOneWidget);
    expect(find.text('檢視重複處置'), findsOneWidget);
  });

  testWidgets('CloudInvoiceReviewPage exposes explicit review and draft callbacks only', (tester) async {
    final events = <String>[];
    await _pumpPage(
      tester,
      candidates: <CloudInvoiceCandidate>[_candidate()],
      onReviewCandidate: (candidate) => events.add('review:${candidate.invoiceNumber}'),
      onConfirmDraft: (candidate) => events.add('draft:${candidate.invoiceNumber}'),
      onDiscardCandidate: (candidate) => events.add('discard:${candidate.invoiceNumber}'),
    );

    await tester.tap(find.text('檢視'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認為本機草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('捨棄'));
    await tester.pumpAndSettle();

    expect(events, <String>['review:AB12345678', 'draft:AB12345678', 'discard:AB12345678']);
  });

  testWidgets('CloudInvoiceReviewPage renders warning fallback seller label', (tester) async {
    await _pumpPage(
      tester,
      candidates: <CloudInvoiceCandidate>[
        _candidate(
          sellerName: '',
          warnings: const <CloudInvoiceCandidateWarning>[CloudInvoiceCandidateWarning.missingSellerName],
        ),
      ],
    );

    expect(find.textContaining('未命名雲端發票商家'), findsOneWidget);
    expect(find.text('需人工確認：缺少商家名稱'), findsOneWidget);
  });

  testWidgets('CloudInvoiceReviewPage renders readable warning summary labels', (tester) async {
    await _pumpPage(
      tester,
      candidates: <CloudInvoiceCandidate>[
        _candidate(
          warnings: const <CloudInvoiceCandidateWarning>[
            CloudInvoiceCandidateWarning.missingLineItems,
            CloudInvoiceCandidateWarning.partialPayload,
            CloudInvoiceCandidateWarning.lowConfidence,
          ],
        ),
      ],
    );

    expect(find.text('需人工確認：缺少品項明細、資料不完整、辨識信心偏低'), findsOneWidget);
  });

  testWidgets('CloudInvoiceReviewPage renders line item summary', (tester) async {
    await _pumpPage(
      tester,
      candidates: <CloudInvoiceCandidate>[
        _candidate(
          lineItems: const <CloudInvoiceLineItem>[
            CloudInvoiceLineItem(name: '咖啡', amount: 55),
            CloudInvoiceLineItem(name: '茶葉蛋', amount: 15),
            CloudInvoiceLineItem(name: '購物袋', amount: 1),
          ],
        ),
      ],
    );

    expect(find.text('品項：3 項'), findsOneWidget);
    expect(find.textContaining('咖啡 NT\$ 55'), findsOneWidget);
    expect(find.textContaining('茶葉蛋 NT\$ 15'), findsOneWidget);
    expect(find.text('另有 1 項品項'), findsOneWidget);
  });

  testWidgets('CloudInvoiceReviewPage renders empty manual fallback CTA', (tester) async {
    var manualEntryCount = 0;
    await _pumpPage(
      tester,
      candidates: const <CloudInvoiceCandidate>[],
      onManualEntry: () => manualEntryCount++,
    );

    expect(find.text('沒有可覆核項目'), findsOneWidget);
    expect(find.byKey(CloudInvoiceReviewPage.emptyManualEntryKey), findsOneWidget);

    await tester.tap(find.byKey(CloudInvoiceReviewPage.emptyManualEntryKey));
    await tester.pumpAndSettle();

    expect(manualEntryCount, 1);
  });

  testWidgets('CloudInvoiceReviewPage renders rejected and retryable states with safe actions', (tester) async {
    var manualEntryCount = 0;
    var retryCount = 0;
    const provider = CloudInvoiceMockProvider();
    await _pumpPage(
      tester,
      candidates: <CloudInvoiceCandidate>[
        _candidate(
          status: CloudInvoiceCandidateStatus.rejected,
          invoiceNumber: '',
          errorCategory: CloudInvoiceCandidateErrorCategory.parseError,
        ),
      ],
      providerResults: <CloudInvoiceMockProviderResult>[
        provider.fetch(CloudInvoiceMockScenario.networkUnavailable),
      ],
      onManualEntry: () => manualEntryCount++,
      onRetryLater: () => retryCount++,
    );

    expect(find.byKey(CloudInvoiceReviewPage.errorSectionKey), findsOneWidget);
    expect(find.text('未辨識候選：解析失敗'), findsOneWidget);
    expect(find.text('網路異常：Network is unavailable.'), findsOneWidget);
    await tester.tap(find.text('改用手動輸入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍後再試'));
    await tester.pumpAndSettle();

    expect(manualEntryCount, 1);
    expect(retryCount, 1);
  });

  testWidgets('CloudInvoiceReviewPage disables candidate actions when callbacks are absent', (tester) async {
    await _pumpPage(tester, candidates: <CloudInvoiceCandidate>[_candidate()]);

    final reviewButton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '檢視'));
    final draftButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '確認為本機草稿'));
    final discardButton = tester.widget<TextButton>(find.widgetWithText(TextButton, '捨棄'));

    expect(reviewButton.onPressed, isNull);
    expect(draftButton.onPressed, isNull);
    expect(discardButton.onPressed, isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<CloudInvoiceCandidate> candidates,
  List<CloudInvoiceMockProviderResult> providerResults = const <CloudInvoiceMockProviderResult>[],
  ValueChanged<CloudInvoiceCandidate>? onReviewCandidate,
  ValueChanged<CloudInvoiceCandidate>? onConfirmDraft,
  ValueChanged<CloudInvoiceCandidate>? onDiscardCandidate,
  VoidCallback? onManualEntry,
  VoidCallback? onRetryLater,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  await tester.pumpWidget(
    MaterialApp(
      home: CloudInvoiceReviewPage(
        candidates: candidates,
        providerResults: providerResults,
        onReviewCandidate: onReviewCandidate,
        onConfirmDraft: onConfirmDraft,
        onDiscardCandidate: onDiscardCandidate,
        onManualEntry: onManualEntry,
        onRetryLater: onRetryLater,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CloudInvoiceCandidate _candidate({
  CloudInvoiceCandidateStatus status = CloudInvoiceCandidateStatus.pending,
  String invoiceNumber = 'AB12345678',
  String sellerName = '測試便利商店',
  double? confidence,
  List<CloudInvoiceLineItem> lineItems = const <CloudInvoiceLineItem>[],
  List<CloudInvoiceCandidateWarning> warnings = const <CloudInvoiceCandidateWarning>[],
  CloudInvoiceCandidateErrorCategory errorCategory = CloudInvoiceCandidateErrorCategory.none,
}) {
  return CloudInvoiceCandidate(
    source: CloudInvoiceCandidateSource.mockCloudInvoice,
    status: status,
    invoiceNumber: invoiceNumber,
    invoiceDate: DateTime(2026, 6, 9),
    sellerIdentifier: '12345678',
    sellerName: sellerName,
    totalAmount: 120,
    taxAmount: 6,
    carrierType: 'mobileBarcode',
    carrierMaskedId: '/AB***12',
    fetchedAt: DateTime.utc(2026, 6, 10, 8),
    lineItems: lineItems,
    rawPayload: 'mock-cloud-invoice-payload',
    confidence: confidence,
    warnings: warnings,
    errorCategory: errorCategory,
  );
}
