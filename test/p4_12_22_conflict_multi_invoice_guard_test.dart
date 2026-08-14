import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v15.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/private_cloud_invoice_conflict_review_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('metadata action rejects a second invoice on the same transaction',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final before = (await db.query('transactions')).single;
    final service = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      clock: () => DateTime.utc(2026, 6, 25, 10),
    );

    final result = await service.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-new-invoice',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.attachMetadata,
        ),
      ],
      finalConfirmation: true,
    );

    expect(result.committedCount, 0);
    expect(result.rejectedCount, 1);
    expect(
      result.results.single.message,
      'TRANSACTION_ALREADY_LINKED_TO_OTHER_INVOICE',
    );
    expect((await db.query('transactions')).single, before);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 1);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 0);
    expect(await _count(db, 'cloud_invoice_operations'), 0);
    expect(await _count(db, 'cloud_invoice_audits'), 0);
  });

  test('keep-existing may close the draft without adding a second invoice',
      () async {
    final db = await _seedDatabase();
    addTearDown(db.close);
    final before = (await db.query('transactions')).single;
    final service = PrivateCloudInvoiceConflictReviewService(
      databaseProvider: () async => db,
      clock: () => DateTime.utc(2026, 6, 25, 10),
    );

    final result = await service.resolveMany(
      decisions: const <PrivateCloudInvoiceConflictResolutionDecision>[
        PrivateCloudInvoiceConflictResolutionDecision(
          draftId: 'draft-new-invoice',
          transactionId: 'transaction-1',
          action: PrivateCloudInvoiceConflictResolutionAction.keepExisting,
        ),
      ],
      finalConfirmation: true,
    );

    expect(result.committedCount, 1);
    expect((await db.query('transactions')).single, before);
    expect(await _count(db, 'cloud_invoice_metadata_links'), 1);
    expect(await _count(db, 'cloud_invoice_draft_promotions'), 0);
    expect(await _count(db, 'cloud_invoice_operations'), 1);
    expect(await _count(db, 'cloud_invoice_audits'), 1);
    expect(
      await service.loadReviewItems(
        const <String, String>{
          'draft-new-invoice': 'transaction-1',
        },
      ),
      isEmpty,
    );
  });
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
      amount: 59,
      category: '午餐',
      occurredAt: DateTime(2026, 6, 24, 18),
      accountName: '測試現金',
      memberName: '自己',
      merchantName: '既有商家',
      tagName: '日常',
      note: '既有備註',
    ).toMap(),
  );
  await db.insert('cloud_invoice_drafts', _draftRow());
  await db.insert(
    'cloud_invoice_metadata_links',
    <String, Object?>{
      'id': 'metadata-existing',
      'operation_key': 'metadata-existing-operation',
      'transaction_id': 'transaction-1',
      'candidate_reference': 'candidate-existing',
      'invoice_number': 'ZZ00000001',
      'seller_identifier': '11111111',
      'seller_name': '既有發票商家',
      'invoice_date': DateTime(2026, 6, 23, 12).toIso8601String(),
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
      'created_at': DateTime(2026, 6, 23, 13).toIso8601String(),
    },
  );
  return db;
}

Map<String, Object?> _draftRow() {
  const items = <CloudInvoiceLineItem>[
    CloudInvoiceLineItem(name: '新發票商品', amount: 59),
  ];
  return <String, Object?>{
    'id': 'draft-new-invoice',
    'operation_key': 'draft-new-invoice-operation',
    'candidate_reference': 'candidate-new-invoice',
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
