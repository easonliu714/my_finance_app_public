import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_review_page.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_review_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('metadata-only preserves transaction and replays idempotently', () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final service = _service(db);
    final before = (await db.query('transactions')).single;

    final review = await service.loadReviewItems(
      const <String, String>{'draft-1': 'transaction-1'},
    );
    expect(review, hasLength(1));
    expect(review.single.existingHasInvoiceMetadata, isFalse);
    expect(review.single.merchantDiffers, isTrue);

    const decision = PrivateCloudInvoiceConflictResolutionDecision(
      draftId: 'draft-1',
      transactionId: 'transaction-1',
      action: PrivateCloudInvoiceConflictResolutionAction.attachMetadata,
    );
    final first = await service.resolveMany(
      decisions: const [decision],
      finalConfirmation: true,
    );
    final replay = await service.resolveMany(
      decisions: const [decision],
      finalConfirmation: true,
    );

    expect(first.committedCount, 1);
    expect(replay.replayCount, 1);
    expect((await db.query('transactions')).single, before);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 1);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 1);
  });

  test('official update preserves governed fields and stores before image',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final service = _service(db);

    final result = await service.resolveMany(
      decisions: const [
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-1',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.updateOfficialFields,
        ),
      ],
      finalConfirmation: true,
    );
    final updated = TransactionRecord.fromMap(
      (await db.query('transactions')).single,
    );

    expect(result.committedCount, 1);
    expect(updated.amount, 59);
    expect(updated.occurredAt, DateTime(2026, 6, 24, 18, 50, 59));
    expect(updated.merchantName, '官方商家');
    expect(updated.accountName, '測試現金');
    expect(updated.category, '午餐');
    expect(updated.memberName, '自己');
    expect(updated.tagName, '日常');
    expect(updated.note, contains('既有備註'));
    expect(updated.note, contains('發票：AN90000010'));
    expect(await _count(db, 'cloud_invoice_before_images'), 1);
  });

  test('keep-existing closes draft without mutating transaction or metadata',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final service = _service(db);
    final before = (await db.query('transactions')).single;

    final result = await service.resolveMany(
      decisions: const [
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-1',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.keepExisting,
        ),
      ],
      finalConfirmation: true,
    );

    expect(result.committedCount, 1);
    expect((await db.query('transactions')).single, before);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 0);
    expect(
      await service.loadReviewItems(
        const <String, String>{'draft-1': 'transaction-1'},
      ),
      isEmpty,
    );
  });

  testWidgets('comparison page requires action and second confirmation',
      (tester) async {
    final fake = _FakeConflictService();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateCloudInvoiceConflictReviewPage(
          conflictTransactionByDraftId: const {'draft-1': 'transaction-1'},
          service: fake,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final resolve = find.byKey(PrivateCloudInvoiceConflictReviewPage.resolveKey);
    await tester.scrollUntilVisible(resolve, 300);
    expect(tester.widget<FilledButton>(resolve).onPressed, isNull);

    await tester.tap(
      find.byKey(PrivateCloudInvoiceConflictReviewPage.actionKey('draft-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(
      PrivateCloudInvoiceConflictResolutionAction.attachMetadata.label,
    ).last);
    await tester.pumpAndSettle();

    final confirmation =
        find.byKey(PrivateCloudInvoiceConflictReviewPage.confirmationKey);
    await tester.scrollUntilVisible(confirmation, 300);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(resolve, 300);
    expect(tester.widget<FilledButton>(resolve).onPressed, isNotNull);

    await tester.tap(resolve);
    await tester.pumpAndSettle();
    expect(fake.resolveCallCount, 1);
    expect(
      find.byKey(PrivateCloudInvoiceConflictReviewPage.resultKey),
      findsOneWidget,
    );
  });
}

PrivateCloudInvoiceConflictReviewService _service(Database db) =>
    PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      clock: () => DateTime.utc(2026, 6, 25, 8),
    );

Future<Database> _seedDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY, type TEXT NOT NULL, amount REAL NOT NULL,
      category TEXT NOT NULL, occurred_at TEXT NOT NULL,
      account_name TEXT NOT NULL, member_name TEXT NOT NULL,
      merchant_name TEXT NOT NULL, tag_name TEXT NOT NULL, note TEXT NOT NULL,
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      exchange_rate_to_base REAL NOT NULL DEFAULT 1,
      base_amount REAL NOT NULL DEFAULT 0, from_account_name TEXT,
      to_account_name TEXT, repayment_group_id TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await createCanonicalProductionV15Tables(db);
  await db.insert('transactions', _existingTransaction().toMap());
  await db.insert('cloud_invoice_drafts', _draftRow());
  return db;
}

TransactionRecord _existingTransaction() => TransactionRecord(
      id: 'transaction-1',
      type: TransactionType.expense,
      amount: 59,
      category: '午餐',
      occurredAt: DateTime(2026, 6, 24, 18),
      accountName: '測試現金',
      memberName: '自己',
      merchantName: '既有商家',
      tagName: '日常',
      note: '既有備註',
    );

Map<String, Object?> _draftRow() {
  const items = [CloudInvoiceLineItem(name: '測試商品', amount: 59)];
  return <String, Object?>{
    'id': 'draft-1',
    'operation_key': 'draft-operation-1',
    'candidate_reference': 'candidate-1',
    'account_id': 'account-1',
    'account_name': '測試現金',
    'amount': 59,
    'invoice_date': DateTime(2026, 6, 24, 18, 50, 59).toIso8601String(),
    'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
    'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
    'currency_code': 'TWD',
    'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
    'merchant_id': null,
    'invoice_number': 'AN90000010',
    'seller_identifier': '31655572',
    'seller_name': '官方商家',
    'tax_amount': null,
    'line_items_json': encodeCloudInvoiceLineItems(items),
    'payload_version': canonicalCloudInvoicePayloadVersion,
    'created_at': DateTime(2026, 6, 24, 20).toIso8601String(),
  };
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS value FROM $table');
  return (rows.single['value']! as num).toInt();
}

class _FakeConflictService implements PrivateCloudInvoiceConflictReviewPort {
  int resolveCallCount = 0;
  bool resolved = false;

  @override
  Future<List<PrivateCloudInvoiceConflictReviewItem>> loadReviewItems(
    Map<String, String> conflictTransactionByDraftId,
  ) async {
    if (resolved) return const [];
    final row = _draftRow();
    final lineItemsJson = row['line_items_json']! as String;
    return [
      PrivateCloudInvoiceConflictReviewItem(
        draft: PrivateCloudInvoiceConflictDraft(
          id: 'draft-1',
          operationKey: 'draft-operation-1',
          candidateReference: 'candidate-1',
          accountId: 'account-1',
          accountName: '測試現金',
          amount: 59,
          invoiceDate: DateTime(2026, 6, 24, 18, 50, 59),
          currencyCode: 'TWD',
          timePrecision: CloudInvoiceTimePrecision.exactDateTime,
          timeSource: CloudInvoiceTimeSource.officialDetailPage,
          currencySource: CloudInvoiceCurrencySource.officialDetailPage,
          invoiceNumber: 'AN90000010',
          sellerIdentifier: '31655572',
          sellerName: '官方商家',
          taxAmount: null,
          lineItems: decodeCloudInvoiceLineItems(lineItemsJson),
          lineItemsJson: lineItemsJson,
          payloadVersion: canonicalCloudInvoicePayloadVersion,
          createdAt: DateTime(2026, 6, 24, 20),
        ),
        existingTransaction: _existingTransaction(),
        existingHasInvoiceMetadata: false,
      ),
    ];
  }

  @override
  Future<PrivateCloudInvoiceConflictResolutionSummary> resolveMany({
    required List<PrivateCloudInvoiceConflictResolutionDecision> decisions,
    required bool finalConfirmation,
  }) async {
    resolveCallCount += 1;
    expect(finalConfirmation, isTrue);
    expect(
      decisions.single.action,
      PrivateCloudInvoiceConflictResolutionAction.attachMetadata,
    );
    resolved = true;
    return const PrivateCloudInvoiceConflictResolutionSummary(
      results: [
        PrivateCloudInvoiceConflictResolutionResult(
          draftId: 'draft-1',
          transactionId: 'transaction-1',
          status: PrivateCloudInvoiceConflictResolutionStatus.committed,
          message: 'CONFLICT_RESOLUTION_COMMITTED',
        ),
      ],
    );
  }
}
