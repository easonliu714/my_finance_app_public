import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v16.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_review_service.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('selected account is persisted before cross-account conflict review',
      () async {
    final db = await _seedDatabase(
      draftAccountId: '',
      draftAccountName: '',
      accountResolutionStatus: 'unresolved',
    );
    addTearDown(db.close);

    final promotion = PrivateCloudInvoiceDraftPromotionService(
      databaseProvider: () async => db,
      onLedgerChanged: () {},
    );
    final result = await promotion.promote(
      decision: const PrivateCloudInvoiceDraftPromotionDecision(
        draftId: 'draft-1',
        category: '午餐',
        memberName: '自己',
        tagName: '日常',
        accountId: 'account-new',
      ),
      finalConfirmation: true,
    );

    expect(result.status, PrivateCloudInvoiceDraftPromotionStatus.conflict);
    final draft = (await db.query(
      'cloud_invoice_drafts',
      where: 'id = ?',
      whereArgs: const <Object?>['draft-1'],
    )).single;
    expect(draft['account_id'], 'account-new');
    expect(draft['account_name'], '新交易帳戶');
    expect(draft['account_resolution_status'], 'selected');

    final conflict = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      onLedgerChanged: () {},
    );
    final summary = await conflict.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-1',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.attachMetadata,
        ),
      ],
      finalConfirmation: true,
    );

    expect(summary.committedCount, 1);
    final existing = TransactionRecord.fromMap(
      (await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: const <Object?>['transaction-1'],
      ))
          .single,
    );
    expect(existing.accountName, '既有交易帳戶');
    expect(await _count(db, 'transactions'), 1);
  });

  test('keep-separate fails closed while draft account is unresolved',
      () async {
    final db = await _seedDatabase(
      draftAccountId: '',
      draftAccountName: '',
      accountResolutionStatus: 'unresolved',
    );
    addTearDown(db.close);

    final conflict = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      onLedgerChanged: () {},
    );
    final summary = await conflict.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-1',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.keepSeparate,
        ),
      ],
      finalConfirmation: true,
    );

    expect(summary.rejectedCount, 1);
    expect(summary.results.single.message, 'ACCOUNT_REQUIRED_FOR_NEW_TRANSACTION');
    expect(await _count(db, 'transactions'), 1);
  });

  test('keep-separate uses the explicitly selected active account', () async {
    final db = await _seedDatabase(
      draftAccountId: 'account-new',
      draftAccountName: '新交易帳戶',
      accountResolutionStatus: 'selected',
    );
    addTearDown(db.close);

    final conflict = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      onLedgerChanged: () {},
    );
    final summary = await conflict.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-1',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.keepSeparate,
        ),
      ],
      finalConfirmation: true,
    );

    expect(summary.committedCount, 1);
    expect(await _count(db, 'transactions'), 2);
    final created = TransactionRecord.fromMap(
      (await db.query(
        'transactions',
        where: 'id <> ?',
        whereArgs: const <Object?>['transaction-1'],
      ))
          .single,
    );
    expect(created.accountName, '新交易帳戶');
    expect(created.category, '午餐');
  });
}

Future<Database> _seedDatabase({
  required String draftAccountId,
  required String draftAccountName,
  required String accountResolutionStatus,
}) async {
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
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL,
      sort_order INTEGER NOT NULL,
      suffix TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await createCanonicalProductionV16Tables(db);

  await db.insert('accounts', const <String, Object?>{
    'id': 'account-new',
    'name': '新交易帳戶',
    'type': 'bank',
    'initial_balance': 0,
    'sort_order': 1,
    'suffix': '',
    'currency_code': 'TWD',
    'is_archived': 0,
  });
  await db.insert(
    'transactions',
    TransactionRecord(
      id: 'transaction-1',
      type: TransactionType.expense,
      amount: 120,
      category: '午餐',
      occurredAt: DateTime(2026, 6, 27, 12),
      accountName: '既有交易帳戶',
      memberName: '自己',
      merchantName: '既有商家',
      tagName: '日常',
      note: '',
    ).toMap(),
  );

  const items = <CloudInvoiceLineItem>[
    CloudInvoiceLineItem(name: '雞腿便當', amount: 120),
  ];
  await db.insert('cloud_invoice_drafts', <String, Object?>{
    'id': 'draft-1',
    'operation_key': 'draft-operation-1',
    'candidate_reference': 'candidate-1',
    'account_id': draftAccountId,
    'account_name': draftAccountName,
    'account_resolution_status': accountResolutionStatus,
    'amount': 120,
    'invoice_date': DateTime(2026, 6, 27, 12, 30).toIso8601String(),
    'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
    'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
    'currency_code': 'TWD',
    'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
    'merchant_id': null,
    'invoice_number': 'AB12345678',
    'seller_identifier': '12345678',
    'seller_name': '官方商家',
    'tax_amount': null,
    'line_items_json': encodeCloudInvoiceLineItems(items),
    'payload_version': canonicalCloudInvoicePayloadVersion,
    'created_at': DateTime.utc(2026, 6, 27).toIso8601String(),
  });
  return db;
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS value FROM $table');
  return (rows.single['value']! as num).toInt();
}
