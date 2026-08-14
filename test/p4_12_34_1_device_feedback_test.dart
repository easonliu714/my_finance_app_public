import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/canonical_cloud_invoice_persistence_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('reviewed USD rate persists source amount and TWD base amount', () async {
    final db = await _openPromotionDatabase();
    addTearDown(db.close);
    await _insertUsdDraft(db, id: 'usd-draft-valid');

    final service = PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
      clock: () => DateTime.utc(2026, 6, 30, 1),
    );
    final result = await service.promote(
      decision: PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'usd-draft-valid',
        category: '電子數碼',
        memberName: '自己',
        tagName: '日常',
        accountId: 'twd-bank',
        exchangeRateToBase: 31.55,
        accountRateToBase: 1,
        exchangeRateSourceToAccount: 31.55,
        fxSourceName: '臺灣銀行歷史匯率（即期買入／賣出中價）',
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
    expect(rows, hasLength(1));
    final transaction = TransactionRecord.fromMap(rows.single);
    expect(transaction.currency, CurrencyCode.twd);
    expect(transaction.amount, 74);
    expect(transaction.exchangeRateToBase, closeTo(1, 0.000001));
    expect(transaction.baseAmount, 74);
    expect(transaction.accountName, 'LineBank・7597');
    expect(transaction.note, contains('原始金額：USD 2.33'));
    expect(transaction.note, contains('匯率日期：2026-06-29'));
  });

  test('foreign draft without a positive reviewed rate fails closed', () async {
    final db = await _openPromotionDatabase();
    addTearDown(db.close);
    await _insertUsdDraft(db, id: 'usd-draft-no-rate');

    final service = PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
    );
    final result = await service.promote(
      decision: const PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'usd-draft-no-rate',
        category: '電子數碼',
        memberName: '自己',
        tagName: '日常',
        accountId: 'twd-bank',
      ),
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.rejected);
    expect(result.message, 'FOREIGN_EXCHANGE_RATE_REQUIRED');
    expect(await db.query('transactions'), isEmpty);
    expect(await db.query('cloud_invoice_draft_promotions'), isEmpty);
  });

  test('draft review source retains grouped account and completed-flow controls',
      () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();

    expect(source, contains('showGroupedAccountChoiceSheet'));
    expect(source, contains('account.type.label'));
    expect(source, contains('account.currency.displayLabel'));
    expect(source, contains('依發票交易日自動載入臺銀中價'));
    expect(source, contains('TaiwanBankHistoricalFxRateService'));
    expect(source, isNot(contains('currency.defaultRateToTwd')));
    expect(source, contains('完成並回到首頁'));
    expect(source, contains('context.goNamed(DashboardPage.routeName)'));
    expect(
      source,
      isNot(contains('｜NT\$ \${draft.amount.toStringAsFixed(0)}')),
    );
  });

  test('detail enrichment source fails closed unless 100-row mode is ready', () {
    final controller = File(
      'lib/features/invoice/lab/disposable_webview_session.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/features/invoice/lab/flutter_landing_webview_session_runtime.dart',
    ).readAsStringSync();

    expect(controller, contains('_prepareOfficialDetailPageIfSupported'));
    expect(controller, contains('DETAIL_PAGE_SIZE_100_NOT_READY'));
    expect(runtime, contains('prepareCurrentPageForOfficialDetail'));
    expect(runtime, contains('prepareExportSelection: false'));
  });
}

Future<Database> _openPromotionDatabase() async {
  final db = await openCanonicalPersistenceTestDatabase();
  await createCanonicalProductionV16Tables(db);
  await insertTestAccount(
    db,
    const AccountRecord(
      id: 'twd-bank',
      name: 'LineBank',
      type: AccountType.bank,
      initialBalance: 10000,
      sortOrder: 10,
      suffix: '7597',
      currency: CurrencyCode.twd,
    ),
  );
  return db;
}

Future<void> _insertUsdDraft(Database db, {required String id}) async {
  const items = <CloudInvoiceLineItem>[
    CloudInvoiceLineItem(name: 'GitHub Actions Usage', amount: 2.33),
  ];
  await db.insert('cloud_invoice_drafts', <String, Object?>{
    'id': id,
    'operation_key': 'operation-$id',
    'candidate_reference': 'candidate-$id',
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
}
