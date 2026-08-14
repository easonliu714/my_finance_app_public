import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
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

  test(
    'keep-existing closes a draft when the target transaction already has another promotion',
    () async {
      final db = await _seedDatabase();
      addTearDown(db.close);
      final before = (await db.query('transactions')).single;
      var ledgerRefreshCount = 0;
      final service = PrivateCloudInvoiceConflictReviewService(
        databaseProvider: () async => db,
        clock: () => DateTime.utc(2026, 6, 25, 14),
        onLedgerChanged: () => ledgerRefreshCount += 1,
      );

      final result = await service.resolveMany(
        decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
          PrivateCloudInvoiceConflictResolutionDecision(
            draftId: 'draft-new',
            transactionId: 'transaction-1',
            action: PrivateCloudInvoiceConflictResolutionAction.keepExisting,
          ),
        ],
        finalConfirmation: true,
      );

      expect(result.committedCount, 1);
      expect(result.rejectedCount, 0);
      expect((await db.query('transactions')).single, before);
      expect(await _count(db, 'cloud_invoice_draft_promotions'), 1);
      expect(await _count(db, 'cloud_invoice_metadata_links'), 0);
      expect(await _count(db, 'cloud_invoice_operations'), 1);
      expect(await _count(db, 'cloud_invoice_audits'), 1);
      expect(ledgerRefreshCount, 1);

      final pending = await PrivateCloudInvoiceDraftPromotionService(
        databaseProvider: () async => db,
      ).listPendingDrafts();
      expect(pending.where((draft) => draft.id == 'draft-new'), isEmpty);
      expect(
        await service.loadReviewItems(
          const <String, String>{'draft-new': 'transaction-1'},
        ),
        isEmpty,
      );

      final replay = await service.resolveMany(
        decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
          PrivateCloudInvoiceConflictResolutionDecision(
            draftId: 'draft-new',
            transactionId: 'transaction-1',
            action: PrivateCloudInvoiceConflictResolutionAction.keepExisting,
          ),
        ],
        finalConfirmation: true,
      );

      expect(replay.replayCount, 1);
      expect(await _count(db, 'cloud_invoice_draft_promotions'), 1);
      expect(await _count(db, 'cloud_invoice_operations'), 1);
      expect(await _count(db, 'cloud_invoice_audits'), 1);
      expect(ledgerRefreshCount, 1);
    },
  );
}

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

  await db.insert(
    'transactions',
    TransactionRecord(
      id: 'transaction-1',
      type: TransactionType.expense,
      amount: 47,
      category: '早餐',
      occurredAt: DateTime(2026, 6, 24, 8, 8),
      accountName: '一卡通 Money',
      memberName: '自己',
      merchantName: 'OK便利商店',
      tagName: '日常',
      note: '既有備註',
    ).toMap(),
  );
  await db.insert(
    'cloud_invoice_drafts',
    _draftRow(
      id: 'draft-existing',
      operationKey: 'draft-operation-existing',
      invoiceNumber: 'OLD1234567',
      amount: 41,
    ),
  );
  await db.insert(
    'cloud_invoice_drafts',
    _draftRow(
      id: 'draft-new',
      operationKey: 'draft-operation-new',
      invoiceNumber: 'AN90000009',
      amount: 47,
    ),
  );
  await db.insert(
    'cloud_invoice_draft_promotions',
    <String, Object?>{
      'draft_id': 'draft-existing',
      'promotion_key': 'existing-promotion',
      'draft_operation_key': 'draft-operation-existing',
      'draft_fingerprint': 'existing-fingerprint',
      'transaction_id': 'transaction-1',
      'category': '早餐',
      'member_name': '自己',
      'tag_name': '日常',
      'note': '',
      'created_at': DateTime(2026, 6, 24, 9).toIso8601String(),
    },
  );
  return db;
}

Map<String, Object?> _draftRow({
  required String id,
  required String operationKey,
  required String invoiceNumber,
  required double amount,
}) {
  const items = <CloudInvoiceLineItem>[
    CloudInvoiceLineItem(name: '測試商品', amount: 47),
  ];
  return <String, Object?>{
    'id': id,
    'operation_key': operationKey,
    'candidate_reference': 'candidate-$id',
    'account_id': 'account-1',
    'account_name': '一卡通 Money',
    'amount': amount,
    'invoice_date': DateTime(2026, 6, 24, 8, 5, 3).toIso8601String(),
    'time_precision': CloudInvoiceTimePrecision.exactDateTime.name,
    'time_source': CloudInvoiceTimeSource.officialDetailPage.name,
    'currency_code': 'TWD',
    'currency_source': CloudInvoiceCurrencySource.officialDetailPage.name,
    'merchant_id': null,
    'invoice_number': invoiceNumber,
    'seller_identifier': '31655572',
    'seller_name': '測試零售股份有限公司甲門市',
    'tax_amount': null,
    'line_items_json': encodeCloudInvoiceLineItems(items),
    'payload_version': canonicalCloudInvoicePayloadVersion,
    'created_at': DateTime(2026, 6, 24, 10).toIso8601String(),
  };
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS value FROM $table');
  return (rows.single['value']! as num).toInt();
}
