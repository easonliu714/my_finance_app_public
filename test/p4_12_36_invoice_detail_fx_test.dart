import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_draft_import_v2_service.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_trace_script.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('inner invoice detail script prepares 100 rows and fails closed', () {
    final script = buildOfficialInvoiceDetailEnrichmentTraceScript(
      scope: OfficialInvoiceDetailSelectionScope.currentPage,
      handlerName: 'test-handler',
    );
    expect(script, contains('expectedItemCountOf'));
    expect(script, contains('requestPageSize100'));
    expect(script, contains('prepareOfficialDetailItems'));
    expect(script, contains('DETAIL_ITEM_PAGE_SIZE_100_NOT_AVAILABLE'));
    expect(script, contains('DETAIL_ITEM_COUNT_MISMATCH'));
    expect(script, contains('DETAIL_ITEM_LIST_TRUNCATED_TO_100'));
    expect(
      script,
      isNot(
        contains(
          "errorCode: 'DETAIL_ITEM_COUNT_EXCEEDS_SUPPORTED_LIMIT'",
        ),
      ),
    );
    expect(
      script,
      contains("normalize(candidate.textContent || candidate.value) === '100'"),
    );
  });

  test('oversized details keep first 100 items and remain formally eligible', () {
    final enrichment = OfficialInvoiceDetailEnrichment(
      requestedInvoiceNumber: 'AB12345678',
      invoiceNumber: 'AB12345678',
      selectorProfileVersion: officialInvoiceDetailSelectorProfileVersion,
      fetchedAt: DateTime.utc(2026, 7, 1),
      success: true,
      invoiceIdentityMatches: true,
      detailTotalInternallyConsistent: false,
      detailTotalMatchesCsv: true,
      sellerIdentifierConsistent: true,
      lineItems: List<OfficialInvoiceDetailLineItem>.generate(
        100,
        (index) => OfficialInvoiceDetailLineItem(
          name: '項目 ${index + 1}',
          amount: 1,
        ),
      ),
      exactTimestamp: DateTime.utc(2026, 7, 1, 12),
      currencyCode: 'TWD',
      sellerName: '測試商店',
      expectedTotal: 132,
      detailTotal: 132,
      lineItemSubtotal: 100,
      unallocatedDifference: 32,
      warningCode: 'DETAIL_ITEM_LIST_TRUNCATED_TO_100',
      declaredItemCount: 132,
      omittedItemCount: 32,
      lineItemsTruncated: true,
    );

    expect(enrichment.canUseOfficialLineItems, isTrue);
    expect(enrichment.positiveEstimatedTaxAmount, isNull);
    expect(isOfficialInvoiceDetailEligibleForFormalImportV2(enrichment), isTrue);

    final request = OfficialInvoiceDetailDraftImportService().buildDraftRequest(
      null,
      enrichment,
    );
    expect(
      request.facts.candidate.warnings,
      contains(CloudInvoiceCandidateWarning.partialPayload),
    );
    expect(request.facts.candidate.lineItems, hasLength(100));
  });

  test('Bank of Taiwan midpoint creates USD to JPY cross rate', () async {
    final service = TaiwanBankHistoricalFxRateService(
      fetcher: (uri) async {
        final code = uri.pathSegments.last;
        return HistoricalFxHttpPayload(
          statusCode: 200,
          body: _fixture(
            date: '2026/06/29',
            code: code,
            buy: code == 'USD' ? 31.50 : 0.205,
            sell: code == 'USD' ? 31.60 : 0.215,
          ),
        );
      },
    );
    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29, 19, 29),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.jpy,
    );
    expect(quote.sourceMidpointToTwd, closeTo(31.55, 0.000001));
    expect(quote.accountMidpointToTwd, closeTo(0.21, 0.000001));
    expect(quote.sourceToAccountRate, closeTo(31.55 / 0.21, 0.000001));
    expect(quote.effectiveDate, DateTime.utc(2026, 6, 29));
  });

  test('same non-TWD account still loads a TWD midpoint for audit', () async {
    final service = TaiwanBankHistoricalFxRateService(
      fetcher: (_) async => HistoricalFxHttpPayload(
        statusCode: 200,
        body: _fixture(
          date: '2026/06/29',
          code: 'USD',
          buy: 31.50,
          sell: 31.60,
        ),
      ),
    );
    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.usd,
    );
    expect(quote.sourceToAccountRate, 1);
    expect(quote.sourceMidpointToTwd, closeTo(31.55, 0.000001));
    expect(quote.accountMidpointToTwd, closeTo(31.55, 0.000001));
  });

  test('missing transaction-date quote falls back within seven days', () async {
    final requestedDates = <String>[];
    final service = TaiwanBankHistoricalFxRateService(
      fetcher: (uri) async {
        final date = uri.pathSegments[2];
        requestedDates.add(date);
        if (date != '2026-06-26') {
          return const HistoricalFxHttpPayload(statusCode: 404, body: '');
        }
        return HistoricalFxHttpPayload(
          statusCode: 200,
          body: _fixture(
            date: '2026/06/26',
            code: 'USD',
            buy: 31.50,
            sell: 31.60,
          ),
        );
      },
    );
    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 28),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );
    expect(quote.effectiveDate, DateTime.utc(2026, 6, 26));
    expect(quote.usedPreviousBusinessDate, isTrue);
    expect(requestedDates, contains('2026-06-26'));
  });

  test('maintenance response never falls back to static defaults', () async {
    final service = TaiwanBankHistoricalFxRateService(
      fetcher: (_) async => const HistoricalFxHttpPayload(
        statusCode: 200,
        body: '<html>臺灣銀行系統維護公告</html>',
      ),
    );
    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 6, 29),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(
        isA<HistoricalFxRateException>().having(
          (error) => error.code,
          'code',
          'FX_SOURCE_MAINTENANCE',
        ),
      ),
    );
  });

  test('formal transaction is converted into selected account currency', () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    await createCanonicalProductionV16Tables(db);
    await insertTestAccount(
      db,
      const AccountRecord(
        id: 'jpy-bank',
        name: 'JPY Bank',
        type: AccountType.bank,
        initialBalance: 100000,
        sortOrder: 1,
        currency: CurrencyCode.jpy,
      ),
    );
    const items = <CloudInvoiceLineItem>[
      CloudInvoiceLineItem(name: 'GitHub Actions Usage', amount: 2.33),
    ];
    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'usd-to-jpy',
      'operation_key': 'operation-usd-to-jpy',
      'candidate_reference': 'candidate-usd-to-jpy',
      'account_id': '',
      'account_name': '',
      'account_resolution_status': 'unresolved',
      'amount': 2.33,
      'invoice_date': DateTime(2026, 6, 29, 19, 29, 2).toIso8601String(),
      'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
      'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
      'currency_code': 'USD',
      'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
      'merchant_id': null,
      'invoice_number': 'BG90000012',
      'seller_identifier': '42541892',
      'seller_name': 'Example Labs, Inc.',
      'tax_amount': null,
      'line_items_json': encodeCloudInvoiceLineItems(items),
      'payload_version': canonicalCloudInvoicePayloadVersion,
      'created_at': DateTime(2026, 6, 30).toIso8601String(),
    });
    final result = await PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
    ).promote(
      decision: PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'usd-to-jpy',
        category: '電子數碼',
        memberName: '自己',
        tagName: '日常',
        accountId: 'jpy-bank',
        exchangeRateToBase: 31.55,
        accountRateToBase: 0.21,
        exchangeRateSourceToAccount: 31.55 / 0.21,
        fxSourceName: TaiwanBankHistoricalFxRateService.sourceName,
        fxRequestedDate: DateTime(2026, 6, 29),
        fxEffectiveDate: DateTime(2026, 6, 29),
      ),
      finalConfirmation: true,
    );
    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.committed);
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[result.transactionId],
    );
    final record = TransactionRecord.fromMap(rows.single);
    expect(record.currency, CurrencyCode.jpy);
    expect(record.amount, 350);
    expect(record.exchangeRateToBase, closeTo(0.21, 0.000001));
    expect(record.note, contains('原始金額：USD 2.33'));
  });
}

String _fixture({
  required String date,
  required String code,
  required double buy,
  required double sell,
}) {
  return '''
<table><tbody><tr>
<td data-table="掛牌日期">$date 16:00:00</td>
<td data-table="幣別">測試幣別 ($code)</td>
<td data-table="現金匯率-本行買入">0</td>
<td data-table="現金匯率-本行賣出">0</td>
<td data-table="即期匯率-本行買入">$buy</td>
<td data-table="即期匯率-本行賣出">$sell</td>
</tr></tbody></table>
''';
}
