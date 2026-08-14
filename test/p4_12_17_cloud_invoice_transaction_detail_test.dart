import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v14.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_supplement_note.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_transaction_detail.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('read model exposes date-only and currency provenance without mutation',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createCanonicalProductionV14Tables(db);
    await db.insert('cloud_invoice_metadata_links', <String, Object?>{
      'id': 'metadata-1',
      'operation_key': 'cloud-invoice-draft-promotion:draft-1',
      'transaction_id': 'transaction-1',
      'candidate_reference': 'candidate-1',
      'invoice_number': 'AE90000005',
      'seller_identifier': '88122703',
      'seller_name': 'Example Streaming Pte. Ltd.',
      'invoice_date': DateTime.utc(2026, 6, 22).toIso8601String(),
      'time_precision': 'dateOnly',
      'time_source': 'unknown',
      'currency_code': 'TWD',
      'currency_source': 'userConfirmed',
      'tax_amount': null,
      'merchant_id': null,
      'line_items_json': encodeCloudInvoiceLineItems(const [
        CloudInvoiceLineItem(
          name: 'Subscription',
          quantity: 1,
          unitPrice: 460,
          amount: 460,
        ),
      ]),
      'payload_version': 1,
      'created_at': DateTime.utc(2026, 6, 23).toIso8601String(),
    });
    await db.insert('cloud_invoice_draft_promotions', <String, Object?>{
      'draft_id': 'draft-1',
      'promotion_key': 'cloud-invoice-draft-promotion:draft-1',
      'draft_operation_key': 'cloud-invoice:candidate-1:createNewDraft',
      'draft_fingerprint': 'fingerprint-1',
      'transaction_id': 'transaction-1',
      'category': '訂閱',
      'member_name': '自己',
      'tag_name': '日常',
      'note': '',
      'created_at': DateTime.utc(2026, 6, 23).toIso8601String(),
    });

    final port = ProductionCloudInvoiceTransactionDetailPort(
      databaseProvider: () async => db,
    );
    final detail = await port.findByTransactionId('transaction-1');

    expect(detail, isNotNull);
    expect(detail!.invoiceNumber, 'AE90000005');
    expect(detail.timePrecision, CloudInvoiceTimePrecision.dateOnly);
    expect(detail.dateTimeLabel, contains('時間未提供（僅日期）'));
    expect(detail.timeSourceLabel, '官方 CSV 僅提供日期');
    expect(detail.currencyCode, 'TWD');
    expect(detail.currencySource, CloudInvoiceCurrencySource.userConfirmed);
    expect(detail.currencySourceLabel, '使用者確認／歸戶帳戶');
    expect(detail.lineItemTotal, 460);
    expect(detail.amountMatches(460), isTrue);
    expect(detail.draftId, 'draft-1');
    expect(detail.promotionKey, 'cloud-invoice-draft-promotion:draft-1');

    await db.close();
  });

  testWidgets('read-only invoice section opens full item and supplement action',
      (tester) async {
    final transaction = _transaction();
    final detail = _detail();
    var supplementRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudInvoiceTransactionDetailSection(
            transaction: transaction,
            port: _FakeDetailPort(detail),
            onSupplementRequested: () => supplementRequested = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(CloudInvoiceTransactionDetailSection.sectionKey),
      findsOneWidget,
    );
    expect(find.text('發票明細'), findsOneWidget);
    expect(find.textContaining('時間未提供（僅日期）'), findsOneWidget);

    await tester.tap(
      find.byKey(CloudInvoiceTransactionDetailSection.openKey),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(CloudInvoiceTransactionDetailSheet.sheetKey),
      findsOneWidget,
    );
    expect(find.text('發票明細（唯讀）'), findsOneWidget);
    expect(find.text('補充未列入明細'), findsOneWidget);

    final sheetScrollable = find
        .descendant(
          of: find.byKey(CloudInvoiceTransactionDetailSheet.sheetKey),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      find.text('官方 CSV 僅提供日期'),
      220,
      scrollable: sheetScrollable,
    );
    expect(find.text('官方 CSV 僅提供日期'), findsOneWidget);
    expect(find.text('使用者確認／歸戶帳戶'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Subscription'),
      220,
      scrollable: sheetScrollable,
    );
    expect(find.text('Subscription'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('金額驗證一致'),
      220,
      scrollable: sheetScrollable,
    );
    expect(find.text('金額驗證一致'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(CloudInvoiceTransactionDetailSheet.supplementKey),
      -260,
      scrollable: sheetScrollable,
    );
    await tester.tap(
      find.byKey(CloudInvoiceTransactionDetailSheet.supplementKey),
    );
    await tester.pumpAndSettle();
    expect(supplementRequested, isTrue);
    expect(
      find.byKey(CloudInvoiceTransactionDetailSheet.sheetKey),
      findsNothing,
    );
  });

  test('supplement note stays separate from immutable official items', () {
    const original = '發票：AB12345678｜匯率來源：臺灣銀行';
    final first = CloudInvoiceSupplementNote.replace(
      original,
      '第 101 項：補充商品 A，NT\$50',
    );
    expect(first, contains(original));
    expect(
      CloudInvoiceSupplementNote.extract(first),
      '第 101 項：補充商品 A，NT\$50',
    );

    final updated = CloudInvoiceSupplementNote.replace(
      first,
      '第 101 項：補充商品 A，NT\$50\n第 102 項：補充商品 B，NT\$20',
    );
    expect(
      RegExp(RegExp.escape(CloudInvoiceSupplementNote.startMarker))
          .allMatches(updated)
          .length,
      1,
    );
    expect(updated, contains('第 102 項'));

    final cleared = CloudInvoiceSupplementNote.replace(updated, '');
    expect(cleared, original);
  });

  test('prepared transaction and ledger sources expose invoice detail path', () {
    final entry = File(
      'lib/features/transaction/transaction_entry_page.dart',
    ).readAsStringSync();
    final ledger = File(
      'lib/features/dashboard/ledger_detail_page.dart',
    ).readAsStringSync();

    expect(entry, contains('CloudInvoiceTransactionDetailSection'));
    expect(entry, contains('onSupplementRequested: _editInvoiceSupplement'));
    expect(entry, contains('補充未列入發票明細'));
    expect(ledger, contains('TransactionEntryPage.routeName'));
    expect(ledger, contains('extra: record'));
  });
}

TransactionRecord _transaction() {
  return TransactionRecord(
    id: 'transaction-1',
    type: TransactionType.expense,
    amount: 460,
    category: '訂閱',
    occurredAt: DateTime.utc(2026, 6, 22),
    accountName: 'Line・4568',
    memberName: '自己',
    merchantName: 'Example Streaming Pte. Ltd.',
    tagName: '日常',
    note: '發票：AE90000005',
  );
}

CloudInvoiceTransactionDetail _detail() {
  return CloudInvoiceTransactionDetail(
    id: 'metadata-1',
    operationKey: 'cloud-invoice-draft-promotion:draft-1',
    transactionId: 'transaction-1',
    candidateReference: 'candidate-1',
    invoiceNumber: 'AE90000005',
    sellerIdentifier: '88122703',
    sellerName: 'Example Streaming Pte. Ltd.',
    invoiceDate: DateTime.utc(2026, 6, 22),
    timePrecision: CloudInvoiceTimePrecision.dateOnly,
    timeSource: CloudInvoiceTimeSource.unknown,
    currencyCode: 'TWD',
    currencySource: CloudInvoiceCurrencySource.userConfirmed,
    lineItems: const [
      CloudInvoiceLineItem(
        name: 'Subscription',
        quantity: 1,
        unitPrice: 460,
        amount: 460,
      ),
    ],
    createdAt: DateTime.utc(2026, 6, 23),
    draftId: 'draft-1',
    promotionKey: 'cloud-invoice-draft-promotion:draft-1',
    draftOperationKey: 'cloud-invoice:candidate-1:createNewDraft',
    promotionCreatedAt: DateTime.utc(2026, 6, 23),
  );
}

class _FakeDetailPort implements CloudInvoiceTransactionDetailPort {
  const _FakeDetailPort(this.detail);

  final CloudInvoiceTransactionDetail? detail;

  @override
  Future<CloudInvoiceTransactionDetail?> findByTransactionId(
    String transactionId,
  ) async {
    return detail;
  }
}
