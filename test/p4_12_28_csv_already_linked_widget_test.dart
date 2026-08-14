import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/official_cloud_invoice_csv_adapter.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_enrichment_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_import_page.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_import_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_preview.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_csv_reconciliation_review.dart';

void main() {
  testWidgets(
    'already-linked invoice defaults to skip and supports explicit re-review',
    (tester) async {
      final csvPreview = _csvPreview();
      final reconciliationPreview =
          const PrivateCloudInvoiceCsvReconciliationPreviewBuilder().build(
            csvPreview: csvPreview,
            localTransactions: const [],
            existingLinksByInvoiceNumber:
                <String, PrivateCloudInvoiceCsvExistingLinkLookup>{
                  'BS90000016': PrivateCloudInvoiceCsvExistingLinkLookup(
                    normalizedInvoiceNumber: 'BS90000016',
                    linkCount: 1,
                    matches: <PrivateCloudInvoiceCsvTransactionMatch>[
                      PrivateCloudInvoiceCsvTransactionMatch(
                        transactionId: 'txn-linked',
                        transactionFingerprint: 'fp-linked',
                        accountName: '信用卡',
                        merchantName: '百樂商行',
                        occurredAt: DateTime(2026, 6, 17, 20, 30),
                        amount: 90,
                      ),
                    ],
                  ),
                },
          );

      await tester.pumpWidget(
        MaterialApp(
          home: PrivateCloudInvoiceCsvImportPage(
            service: _FakeImportService(
              csvPreview: csvPreview,
              reconciliationPreview: reconciliationPreview,
            ),
            enrichmentPort: const _FakeEnrichmentPort(),
          ),
        ),
      );

      await tester.tap(
        find.byKey(PrivateCloudInvoiceCsvImportPage.pickFileKey),
      );
      await tester.pumpAndSettle();

      expect(find.text('已存在且已連結：1'), findsOneWidget);
      expect(find.text('已連結並預設略過：1'), findsOneWidget);

      final cardFinder = find.byKey(
        PrivateCloudInvoiceCsvImportPage.alreadyLinkedCardKey('BS90000016'),
      );
      final expansionFinder = find.byKey(
        PrivateCloudInvoiceCsvImportPage.alreadyLinkedExpansionKey,
      );
      final completeFinder = find.byKey(
        PrivateCloudInvoiceCsvImportPage.completeReviewKey,
      );

      await tester.scrollUntilVisible(expansionFinder, 200);
      await tester.pump();
      expect(expansionFinder, findsOneWidget);
      expect(find.text('已存在且已連結（1）'), findsOneWidget);
      expect(find.text('已預設略過，需要時再展開逐筆覆核'), findsOneWidget);
      expect(cardFinder, findsNothing);

      await tester.tap(find.text('已存在且已連結（1）'));
      await tester.pumpAndSettle();

      expect(cardFinder, findsOneWidget);
      expect(
        find.text(privateCloudInvoiceCsvAlreadyLinkedLabel),
        findsOneWidget,
      );
      expect(find.text('既有交易：百樂商行'), findsOneWidget);
      expect(find.textContaining('信用卡｜2026-06-17 20:30｜90'), findsOneWidget);
      expect(find.text('保持分開／稍後處理'), findsNothing);

      await tester.scrollUntilVisible(completeFinder, 200);
      await tester.pump();
      var completeButton = tester.widget<FilledButton>(completeFinder);
      expect(completeButton.onPressed, isNotNull);

      await tester.tap(
        find.byKey(
          PrivateCloudInvoiceCsvImportPage.alreadyLinkedReviewKey('BS90000016'),
        ),
      );
      await tester.pump();

      expect(find.text('人工重新覆核中；只有明確選擇既有交易才會進入資料補充。'), findsOneWidget);
      expect(
        find.byKey(
          PrivateCloudInvoiceCsvImportPage.alreadyLinkedRestoreKey(
            'BS90000016',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('保持分開／稍後處理'), findsNothing);
      await tester.scrollUntilVisible(completeFinder, 200);
      await tester.pump();
      completeButton = tester.widget<FilledButton>(completeFinder);
      expect(completeButton.onPressed, isNull);

      final restoreFinder = find.byKey(
        PrivateCloudInvoiceCsvImportPage.alreadyLinkedRestoreKey('BS90000016'),
      );
      await tester.scrollUntilVisible(restoreFinder, 200);
      await tester.tap(restoreFinder);
      await tester.pump();

      await tester.scrollUntilVisible(completeFinder, 200);
      await tester.pump();
      completeButton = tester.widget<FilledButton>(completeFinder);
      expect(completeButton.onPressed, isNotNull);
      await tester.tap(completeFinder);
      await tester.pumpAndSettle();

      final completedFinder = find.byKey(
        PrivateCloudInvoiceCsvImportPage.completedResultKey,
      );
      expect(completedFinder, findsOneWidget);
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final completedRect = tester.getRect(completedFinder);
      expect(completedRect.top, lessThan(viewportHeight));
      expect(completedRect.bottom, greaterThan(0));
      expect(
        find.descendant(
          of: completedFinder,
          matching: find.textContaining('已連結並略過：1'),
        ),
        findsOneWidget,
      );
    },
  );
}

class _FakeImportService implements PrivateCloudInvoiceCsvImportPort {
  _FakeImportService({
    required this.csvPreview,
    required this.reconciliationPreview,
  });

  final OfficialCloudInvoiceCsvPreview csvPreview;
  final PrivateCloudInvoiceCsvReconciliationPreview reconciliationPreview;

  @override
  Future<PrivateCloudInvoiceCsvSource?> pickAndPreview() async {
    return PrivateCloudInvoiceCsvSource(
      fileName: '2026-06.csv',
      preview: csvPreview,
    );
  }

  @override
  Future<PrivateCloudInvoiceCsvReconciliationPreview>
  buildReconciliationPreview(OfficialCloudInvoiceCsvPreview preview) async {
    return reconciliationPreview;
  }

  @override
  Future<List<AccountRecord>> listActiveAccounts() async {
    return const <AccountRecord>[];
  }

  @override
  Future<PrivateCloudInvoiceCsvImportSummary> importDrafts({
    required OfficialCloudInvoiceCsvPreview preview,
    required Set<String> invoiceIds,
    required AccountRecord account,
  }) {
    throw UnimplementedError('not used by this widget test');
  }
}

class _FakeEnrichmentPort implements PrivateCloudInvoiceCsvEnrichmentPort {
  const _FakeEnrichmentPort();

  @override
  Future<PrivateCloudInvoiceCsvEnrichmentSummary> executeConfirmed({
    required PrivateCloudInvoiceCsvReconciliationReview review,
    required bool finalConfirmation,
  }) {
    throw UnimplementedError('not used by this widget test');
  }
}

OfficialCloudInvoiceCsvPreview _csvPreview() {
  return OfficialCloudInvoiceCsvPreview(
    invoices: <OfficialCloudInvoiceCsvInvoicePreview>[
      OfficialCloudInvoiceCsvInvoicePreview(
        id: 'BS90000016',
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
          invoiceNumber: 'BS90000016',
          invoiceDate: DateTime(2026, 6, 17),
          sellerIdentifier: '12345678',
          sellerName: '百樂商行',
          totalAmount: 90,
          carrierType: 'official-csv',
          carrierMaskedId: '',
          fetchedAt: DateTime(2026, 6, 27),
          lineItems: const <CloudInvoiceLineItem>[
            CloudInvoiceLineItem(name: '巧克力餅', amount: 90),
          ],
        ),
      ),
    ],
    fileIssues: const <OfficialCloudInvoiceCsvIssue>[],
    detailRowCount: 1,
    repairedRowCount: 0,
    ignoredFooterCount: 0,
    earliestInvoiceDate: DateTime(2026, 6, 17),
    latestInvoiceDate: DateTime(2026, 6, 17),
  );
}
