import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_review_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_lab_lifecycle_policy.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('transient lifecycle states preserve the in-memory invoice batch', () {
    for (final state in <AppLifecycleState>[
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      expect(
        PrivateCloudInvoiceLabLifecyclePolicy.dispositionFor(state),
        PrivateCloudInvoiceLabLifecycleDisposition.preserve,
        reason: state.name,
      );
    }
    expect(
      PrivateCloudInvoiceLabLifecyclePolicy.dispositionFor(
        AppLifecycleState.detached,
      ),
      PrivateCloudInvoiceLabLifecycleDisposition.cancel,
    );
  });

  test('transaction linked to a different invoice is excluded as a candidate',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    await _insertMetadata(
      db,
      transactionId: 'transaction-1',
      invoiceNumber: 'ZZ00000001',
      operationKey: 'existing-metadata-different-invoice',
    );

    final result = await _promotionService(db).promote(
      decision: _promotionDecision,
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.committed);
    expect(result.message, 'DRAFT_PROMOTED');
    expect(result.transactionId, isNot('transaction-1'));
    expect(await _count(db, 'transactions'), 2);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 2);
  });

  test('same invoice number remains fail-closed', () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    await _insertMetadata(
      db,
      transactionId: 'transaction-1',
      invoiceNumber: 'AN90000010',
      operationKey: 'existing-metadata-same-invoice',
    );

    final result = await _promotionService(db).promote(
      decision: _promotionDecision,
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.rejected);
    expect(result.message, 'INVOICE_ALREADY_LINKED_TO_TRANSACTION');
    expect(result.transactionId, 'transaction-1');
    expect(await _count(db, 'transactions'), 1);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 0);
  });

  test('unlinked same-day account and amount remains an explicit conflict',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);

    final result = await _promotionService(db).promote(
      decision: _promotionDecision,
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.conflict);
    expect(result.message, 'POTENTIAL_DUPLICATE_REVIEW_REQUIRED');
    expect(result.transactionId, 'transaction-1');
    expect(result.candidateTransactionIds, <String>['transaction-1']);
    expect(await _count(db, 'transactions'), 1);
  });

  test('keep-separate requires final confirmation', () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final service = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
    );

    expect(
      () => service.resolveMany(
        decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
          _keepSeparateDecision,
        ],
        finalConfirmation: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'CONFLICT_RESOLUTION_CONFIRMATION_REQUIRED',
        ),
      ),
    );
  });

  test('keep-separate creates a governed new transaction and replays safely',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final existingBefore = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>['transaction-1'],
    ))
        .single;
    var ledgerRefreshCount = 0;
    final service = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      clock: () => DateTime.utc(2026, 6, 26, 8),
      onLedgerChanged: () => ledgerRefreshCount += 1,
    );

    final result = await service.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        _keepSeparateDecision,
      ],
      finalConfirmation: true,
    );

    expect(result.committedCount, 1);
    expect(result.rejectedCount, 0);
    final newTransactionId = result.results.single.transactionId;
    expect(newTransactionId, isNot('transaction-1'));
    expect(await _count(db, 'transactions'), 2);
    expect(
      (await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>['transaction-1'],
      ))
          .single,
      existingBefore,
    );
    final created = TransactionRecord.fromMap(
      (await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>[newTransactionId],
      ))
          .single,
    );
    expect(created.amount, 59);
    expect(created.occurredAt, DateTime(2026, 6, 24, 18, 50, 59));
    expect(created.accountName, '測試現金');
    expect(created.category, '午餐');
    expect(created.memberName, '自己');
    expect(created.tagName, '日常');
    expect(created.merchantName, '官方商家');
    expect(await _count(db, 'cloud_invoice_metadata_links'), 1);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 1);
    expect(await _count(db, 'cloud_invoice_operations'), 1);
    expect(await _count(db, 'cloud_invoice_audits'), 1);
    expect(ledgerRefreshCount, 1);

    final replay = await service.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        _keepSeparateDecision,
      ],
      finalConfirmation: true,
    );

    expect(replay.replayCount, 1);
    expect(replay.results.single.transactionId, newTransactionId);
    expect(await _count(db, 'transactions'), 2);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 1);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 1);
    expect(await _count(db, 'cloud_invoice_operations'), 1);
    expect(await _count(db, 'cloud_invoice_audits'), 1);
    expect(ledgerRefreshCount, 1);
  });

  test('keep-separate is unavailable when the same invoice is already formal',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    await _insertMetadata(
      db,
      transactionId: 'transaction-1',
      invoiceNumber: 'AN90000010',
      operationKey: 'same-invoice-before-keep-separate',
    );
    final service = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
    );

    final result = await service.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        _keepSeparateDecision,
      ],
      finalConfirmation: true,
    );

    expect(result.rejectedCount, 1);
    expect(
      result.results.single.message,
      'INVOICE_ALREADY_LINKED_TO_OTHER_TRANSACTION',
    );
    expect(await _count(db, 'transactions'), 1);
  });

  test('keep-separate is an explicit user-facing governed decision', () {
    expect(
      PrivateCloudInvoiceConflictResolutionAction.keepSeparate.label,
      '兩筆皆保留並另建新交易',
    );
    expect(
      PrivateCloudInvoiceConflictResolutionAction.keepSeparate.description,
      contains('既有交易完全不變'),
    );
  });
}

const _promotionDecision = PrivateCloudInvoiceDraftPromotionDecision(
  draftId: 'draft-1',
  category: '午餐',
  memberName: '自己',
  tagName: '日常',
);

const _keepSeparateDecision = PrivateCloudInvoiceConflictResolutionDecision(
  draftId: 'draft-1',
  transactionId: 'transaction-1',
  action: PrivateCloudInvoiceConflictResolutionAction.keepSeparate,
);

PrivateCloudInvoiceDraftPromotionService _promotionService(Database db) {
  return PrivateCloudInvoiceDraftPromotionService(
    databaseProvider: () async => db,
    clock: () => DateTime.utc(2026, 6, 26, 8),
  );
}

Future<Database> _seedDatabase() async {
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
  await db.insert(
    'transactions',
    TransactionRecord(
      id: 'transaction-1',
      type: TransactionType.expense,
      amount: 59,
      category: '午餐',
      occurredAt: DateTime(2026, 6, 24, 18, 10),
      accountName: '測試現金',
      memberName: '自己',
      merchantName: '既有商家',
      tagName: '日常',
      note: '既有備註',
    ).toMap(),
  );
  await db.insert('cloud_invoice_drafts', _draftRow());
  return db;
}

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

Future<void> _insertMetadata(
  Database db, {
  required String transactionId,
  required String invoiceNumber,
  required String operationKey,
}) async {
  await db.insert('cloud_invoice_metadata_links', <String, Object?>{
    'id': 'metadata-$operationKey',
    'operation_key': operationKey,
    'transaction_id': transactionId,
    'candidate_reference': 'existing-candidate-$invoiceNumber',
    'invoice_number': invoiceNumber,
    'seller_identifier': '12345678',
    'seller_name': '既有發票商家',
    'invoice_date': DateTime(2026, 6, 24, 18).toIso8601String(),
    'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
    'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
    'currency_code': 'TWD',
    'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
    'tax_amount': null,
    'merchant_id': null,
    'line_items_json': encodeCloudInvoiceLineItems(
      const <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '既有商品', amount: 59),
      ],
    ),
    'payload_version': canonicalCloudInvoicePayloadVersion,
    'created_at': DateTime(2026, 6, 24, 19).toIso8601String(),
  });
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS value FROM $table');
  return (rows.single['value']! as num).toInt();
}
