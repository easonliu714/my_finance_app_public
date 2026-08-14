import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';

void main() {
  test('eligible official detail allows unknown currency but requires line items',
      () {
    expect(
      isOfficialInvoiceDetailEligibleForFormalImport(_enrichment()),
      isTrue,
    );
    expect(
      isOfficialInvoiceDetailEligibleForFormalImport(
        _enrichment(lineItems: const <OfficialInvoiceDetailLineItem>[]),
      ),
      isFalse,
    );
  });

  test('draft request preserves exact official fields and optional account', () {
    final account = _account();
    final service = OfficialInvoiceDetailDraftImportService(
      clock: () => DateTime.utc(2026, 6, 24, 20, 30),
    );
    final request = service.buildDraftRequest(account, _enrichment());
    final unresolvedRequest = service.buildDraftRequest(null, _enrichment());

    expect(request.facts.timePrecision, CloudInvoiceTimePrecision.exactDateTime);
    expect(request.facts.timeSource, CloudInvoiceTimeSource.officialDetailPage);
    expect(request.facts.currencyCode, isNull);
    expect(request.facts.currencySource, CloudInvoiceCurrencySource.unknown);
    expect(request.facts.candidate.invoiceNumber, 'AN90000010');
    expect(request.facts.candidate.totalAmount, 59);
    expect(request.facts.candidate.lineItems, hasLength(2));
    expect(request.decision.selectedAccountId, account.id);
    expect(unresolvedRequest.decision.selectedAccountId, isNull);
    expect(unresolvedRequest.expectedAccountFingerprint, isNull);
    expect(request.operationKey, contains('createNewDraft'));
  });

  test('formal import and conflict review source contracts remain governed', () {
    final importService = File(
      'lib/features/invoice/lab/official_invoice_detail_draft_import_service.dart',
    ).readAsStringSync();
    final importPage = File(
      'lib/features/invoice/lab/official_invoice_detail_draft_import_page.dart',
    ).readAsStringSync();
    final promotionPage = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();
    final conflictPage = File(
      'lib/features/invoice/lab/private_cloud_invoice_conflict_review_page.dart',
    ).readAsStringSync();
    final config = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_config.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*([^\s]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    expect(
      config,
      contains("validationVersion = '${versionMatch!.group(1)}'"),
    );
    expect(
      importService,
      contains('CanonicalCloudInvoicePersistenceService'),
    );
    expect(importService, contains('OFFICIAL_INVOICE_ALREADY_FORMAL'));
    expect(importService, contains('transactionCountUnchanged'));
    expect(importPage, contains('兩階段建立正式支出'));
    expect(importPage, contains('預設交易帳戶（選填）'));
    expect(importPage, contains('待定帳戶（下一階段再指定）'));
    expect(importPage, contains("initialValue: selectedAccountId ?? ''"));
    expect(importPage, isNot(contains('selectedAccount == null')));
    expect(importPage, contains('帳戶可維持「待定帳戶」進入下一階段'));
    expect(promotionPage, contains('initialDraftIds'));
    expect(
      promotionPage,
      contains('我確認先比對既有交易，並將資料完整者建立為正式支出'),
    );
    expect(promotionPage, contains('跨帳戶檢查同日期、同金額交易'));
    expect(promotionPage, contains('付款帳戶（建立新交易時必填）'));
    expect(promotionPage, contains('立即選擇候選交易'));
    expect(promotionPage, contains('立即逐筆確認衝突'));
    expect(conflictPage, contains('系統不會自動覆蓋'));
    expect(conflictPage, contains('兩筆皆保留並另建新交易'));
    expect(importService.toLowerCase(), isNot(contains('document.cookie')));
    expect(importService.toLowerCase(), isNot(contains('outerhtml')));
  });
}

OfficialInvoiceDetailEnrichment _enrichment({
  List<OfficialInvoiceDetailLineItem>? lineItems,
}) {
  return OfficialInvoiceDetailEnrichment(
    requestedInvoiceNumber: 'AN90000010',
    invoiceNumber: 'AN90000010',
    selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
    fetchedAt: DateTime.utc(2026, 6, 24, 20, 11, 4),
    success: true,
    invoiceIdentityMatches: true,
    detailTotalInternallyConsistent: true,
    detailTotalMatchesCsv: true,
    sellerIdentifierConsistent: true,
    lineItems: lineItems ??
        const <OfficialInvoiceDetailLineItem>[
          OfficialInvoiceDetailLineItem(
            name: '(V)卜蜂義式輕食沙拉胸(4°C/110g)',
            quantity: 1,
            unitPrice: 69,
            amount: 69,
          ),
          OfficialInvoiceDetailLineItem(
            name: '應稅總折價',
            quantity: 1,
            unitPrice: -10,
            amount: -10,
          ),
        ],
    exactTimestamp: DateTime.utc(2026, 6, 24, 18, 50, 59),
    currencyCode: null,
    officialStatus: '已確認',
    sellerIdentifier: '31655572',
    sellerName: '測試零售股份有限公司甲門市',
    expectedTotal: 59,
    detailTotal: 59,
    lineItemSubtotal: 59,
    unallocatedDifference: 0,
    dialogDetected: true,
  );
}

AccountRecord _account() {
  return const AccountRecord(
    id: 'acc-1',
    name: '一卡通 Money',
    type: AccountType.eWallet,
    initialBalance: 1000,
    sortOrder: 0,
    currency: CurrencyCode.twd,
    isArchived: false,
  );
}
