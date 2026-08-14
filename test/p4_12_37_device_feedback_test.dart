import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_trace_script.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_retry.dart';
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

  test(
      'Bank of Taiwan request forces zh-TW and accepts English quote labels on an identified historical table',
      () async {
    Uri? requestedUri;
    final service = TaiwanBankHistoricalFxRateService(
      fetcher: (uri) async {
        requestedUri = uri;
        return const HistoricalFxHttpPayload(
          statusCode: 200,
          body: '''
<table title="Historical quote time spot rates"><tbody><tr>
<td data-table="Quoted Date">06/29/2026 16:00:00</td>
<td data-table="Currency">US Dollar (USD)</td>
<td data-table="Cash Buying">31.20</td>
<td data-table="Cash Selling">31.90</td>
<td data-table="Spot Buying">31.50</td>
<td data-table="Spot Selling">31.60</td>
</tr></tbody></table>
''',
        );
      },
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(requestedUri, isNotNull);
    expect(requestedUri!.queryParameters['Lang'], 'zh-TW');
    expect(quote.sourceMidpointToTwd, closeTo(31.55, 0.000001));
  });

  test('actual TWD debit amount is persisted exactly and rate stays auditable',
      () async {
    final db = await openCanonicalPersistenceTestDatabase();
    addTearDown(db.close);
    await createCanonicalProductionV16Tables(db);
    await insertTestAccount(
      db,
      const AccountRecord(
        id: 'line-debit-9936',
        name: 'LineBank',
        suffix: '9936',
        type: AccountType.debitCard,
        initialBalance: 1000,
        sortOrder: 1,
        currency: CurrencyCode.twd,
      ),
    );
    const items = <CloudInvoiceLineItem>[
      CloudInvoiceLineItem(name: 'GitHub Actions Usage', amount: 2.33),
    ];
    await db.insert('cloud_invoice_drafts', <String, Object?>{
      'id': 'actual-debit-usd',
      'operation_key': 'operation-actual-debit-usd',
      'candidate_reference': 'candidate-actual-debit-usd',
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
      'created_at': DateTime(2026, 7, 1).toIso8601String(),
    });

    const derivedRate = 74 / 2.33;
    final result = await PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
    ).promote(
      decision: PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'actual-debit-usd',
        category: '電子數碼',
        memberName: '自己',
        tagName: '日常',
        accountId: 'line-debit-9936',
        exchangeRateToBase: derivedRate,
        accountRateToBase: 1,
        exchangeRateSourceToAccount: derivedRate,
        reviewedAccountAmount: 74,
        fxSourceName: '使用者輸入實際扣帳金額（反推）',
        fxRequestedDate: DateTime(2026, 6, 29),
      ),
      finalConfirmation: true,
    );

    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[result.transactionId],
    );
    final record = TransactionRecord.fromMap(rows.single);
    expect(record.currency, CurrencyCode.twd);
    expect(record.amount, 74);
    expect(record.note, contains('原始金額：USD 2.33'));
    expect(record.note, contains('實際扣帳金額：TWD 74'));
    expect(record.note, contains('使用者輸入實際扣帳金額（反推）'));
  });

  test('100-item preparation retries and reports structured diagnostics', () {
    final script = buildOfficialInvoiceDetailEnrichmentTraceScript(
      scope: OfficialInvoiceDetailSelectionScope.singleInvoice,
      handlerName: 'test-handler',
      singleInvoiceNumber: 'BG90000012',
    );
    expect(script, contains('window.jQuery'));
    expect(script, contains('requiredVisibleItemCount'));
    expect(script, contains('pageSize100SelectionObserved'));
    expect(script, contains('loadingMaskObserved'));
    expect(script, contains('}, 30000);'));
    expect(
      officialInvoiceDetailResidualCategoryForCode(
        'DETAIL_ITEM_TABLE_RELOAD_TIMEOUT',
      ),
      OfficialInvoiceDetailResidualCategory.technicalRetryable,
    );
    expect(
      officialInvoiceDetailFailureLabel('DETAIL_ITEM_TABLE_RELOAD_TIMEOUT'),
      contains('30 秒'),
    );
  });

  test('promotion page exposes actual debit fallback and retry action', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();
    expect(source, contains('實際扣帳金額'));
    expect(source, contains('重新取得臺銀匯率'));
    expect(source, contains('reviewedAccountAmount'));
  });
}
