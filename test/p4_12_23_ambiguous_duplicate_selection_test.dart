import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_candidate_selection_page.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_review_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('multiple duplicate candidates fail closed and preserve every id', () async {
    final db = await _seedDatabase(twoCandidates: true);
    addTearDown(db.close);
    final service = PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
    );

    final result = await service.promote(
      decision: const PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'draft-1',
        category: '午餐',
        memberName: '自己',
        tagName: '日常',
      ),
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.conflict);
    expect(result.message, 'MULTIPLE_POTENTIAL_DUPLICATES_REVIEW_REQUIRED');
    expect(result.transactionId, isNull);
    expect(result.candidateTransactionIds, <String>['transaction-1', 'transaction-2']);
    expect(result.requiresCandidateSelection, isTrue);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 0);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 0);
    expect(await _count(db, 'transactions'), 2);
  });

  test('single duplicate remains compatible with conflict review', () async {
    final db = await _seedDatabase(twoCandidates: false);
    addTearDown(db.close);
    final service = PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
    );

    final result = await service.promote(
      decision: const PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'draft-1',
        category: '午餐',
        memberName: '自己',
        tagName: '日常',
      ),
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.conflict);
    expect(result.message, 'POTENTIAL_DUPLICATE_REVIEW_REQUIRED');
    expect(result.transactionId, 'transaction-1');
    expect(result.candidateTransactionIds, <String>['transaction-1']);
    expect(result.requiresCandidateSelection, isFalse);
  });

  testWidgets('candidate page requires an explicit transaction selection',
      (tester) async {
    final fake = _FakeReviewService();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateCloudInvoiceConflictCandidateSelectionPage(
          candidateTransactionIdsByDraftId: const <String, List<String>>{
            'draft-1': <String>['transaction-1', 'transaction-2'],
          },
          service: fake,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final continueButton = find.byKey(
      PrivateCloudInvoiceConflictCandidateSelectionPage.continueKey,
    );
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.tap(
      find.byKey(
        PrivateCloudInvoiceConflictCandidateSelectionPage.candidateKey(
          'draft-1',
          'transaction-2',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    expect(fake.loadCalls, 2);
  });
}

Future<Database> _seedDatabase({required bool twoCandidates}) async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
      initial_balance REAL NOT NULL, sort_order INTEGER NOT NULL,
      suffix TEXT NOT NULL DEFAULT '', currency_code TEXT NOT NULL DEFAULT 'TWD',
      credit_limit REAL NOT NULL DEFAULT 0, statement_day INTEGER NOT NULL DEFAULT 1,
      payment_due_day INTEGER NOT NULL DEFAULT 1,
      payment_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_principal REAL NOT NULL DEFAULT 0,
      annual_interest_rate REAL NOT NULL DEFAULT 0,
      loan_term_months INTEGER NOT NULL DEFAULT 0,
      loan_repayment_method TEXT NOT NULL DEFAULT 'equalPrincipalAndInterest',
      loan_payment_due_day INTEGER NOT NULL DEFAULT 1,
      loan_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      loan_reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_start_date TEXT, loan_disbursement_account_name TEXT NOT NULL DEFAULT '',
      loan_handling_fee REAL NOT NULL DEFAULT 0,
      loan_disbursement_created INTEGER NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '', is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
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

  await db.insert(
    'accounts',
    const AccountRecord(
      id: 'account-1',
      name: '測試現金',
      type: AccountType.cash,
      initialBalance: 1000,
      sortOrder: 0,
    ).toMap(),
  );
  await db.insert('transactions', _transaction('transaction-1', 9));
  if (twoCandidates) {
    await db.insert('transactions', _transaction('transaction-2', 10));
  }
  await db.insert('cloud_invoice_drafts', _draftRow());
  return db;
}

Map<String, Object?> _transaction(String id, int minute) => TransactionRecord(
      id: id,
      type: TransactionType.expense,
      amount: 59,
      category: '午餐',
      occurredAt: DateTime(2026, 6, 24, 18, minute),
      accountName: '測試現金',
      memberName: '自己',
      merchantName: '候選商家 $id',
      tagName: '日常',
      note: '',
    ).toMap();

Map<String, Object?> _draftRow() {
  const items = <CloudInvoiceLineItem>[
    CloudInvoiceLineItem(name: '測試商品', amount: 59),
  ];
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

class _FakeReviewService implements PrivateCloudInvoiceConflictReviewPort {
  int loadCalls = 0;

  @override
  Future<List<PrivateCloudInvoiceConflictReviewItem>> loadReviewItems(
    Map<String, String> conflictTransactionByDraftId,
  ) async {
    loadCalls += 1;
    final transactionId = conflictTransactionByDraftId.values.single;
    return <PrivateCloudInvoiceConflictReviewItem>[
      PrivateCloudInvoiceConflictReviewItem(
        draft: _fakeDraft(),
        existingTransaction: TransactionRecord(
          id: transactionId,
          type: TransactionType.expense,
          amount: 59,
          category: '午餐',
          occurredAt: transactionId == 'transaction-1'
              ? DateTime(2026, 6, 24, 18, 9)
              : DateTime(2026, 6, 24, 18, 10),
          accountName: '測試現金',
          memberName: '自己',
          merchantName: '候選商家 $transactionId',
          tagName: '日常',
          note: '',
        ),
        existingHasInvoiceMetadata: false,
      ),
    ];
  }

  @override
  Future<PrivateCloudInvoiceConflictResolutionSummary> resolveMany({
    required List<PrivateCloudInvoiceConflictResolutionDecision> decisions,
    required bool finalConfirmation,
  }) async {
    throw UnimplementedError();
  }
}

PrivateCloudInvoiceConflictDraft _fakeDraft() {
  const items = <CloudInvoiceLineItem>[
    CloudInvoiceLineItem(name: '測試商品', amount: 59),
  ];
  final lineItemsJson = encodeCloudInvoiceLineItems(items);
  return PrivateCloudInvoiceConflictDraft(
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
    lineItems: items,
    lineItemsJson: lineItemsJson,
    payloadVersion: canonicalCloudInvoicePayloadVersion,
    createdAt: DateTime(2026, 6, 24, 20),
  );
}
