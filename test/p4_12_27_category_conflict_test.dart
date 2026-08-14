import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_category_suggestion_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('conflicting rule and confirmed history require manual selection',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cloud_invoice_metadata_links (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        seller_identifier TEXT NOT NULL,
        seller_name TEXT NOT NULL,
        line_items_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    for (var index = 0; index < 3; index++) {
      final transactionId = 'transaction-$index';
      await db.insert('transactions', <String, Object?>{
        'id': transactionId,
        'category': '午餐',
      });
      await db.insert('cloud_invoice_metadata_links', <String, Object?>{
        'id': 'metadata-$index',
        'transaction_id': transactionId,
        'seller_identifier': '12345678',
        'seller_name': '熟客商行',
        'line_items_json': encodeCloudInvoiceLineItems(
          const <CloudInvoiceLineItem>[
            CloudInvoiceLineItem(name: '每日特餐', amount: 120),
          ],
        ),
        'created_at': DateTime.utc(2026, 6, 20 + index).toIso8601String(),
      });
    }

    final service = OfficialInvoiceCategorySuggestionService(
      referenceTime: DateTime.utc(2026, 6, 27),
    );
    final result = await service.suggestMany(
      db,
      <OfficialInvoiceCategorySuggestionInput>[
        OfficialInvoiceCategorySuggestionInput(
          id: 'conflict',
          invoiceDate: DateTime(2026, 6, 26, 18, 30),
          sellerIdentifier: '12345678',
          sellerName: '熟客商行',
          lineItems: const <CloudInvoiceLineItem>[
            CloudInvoiceLineItem(name: '雞腿便當', amount: 130),
          ],
        ),
      ],
    );
    final suggestion = result['conflict']!;

    expect(suggestion.category, '晚餐');
    expect(suggestion.historyEvidenceCount, 3);
    expect(suggestion.confidence, lessThan(0.65));
    expect(suggestion.canPrefill, isFalse);
    expect(suggestion.reasons.join('；'), contains('保留人工判斷'));
  });
}
