import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_category_suggestion_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final service = OfficialInvoiceCategorySuggestionService(
    referenceTime: DateTime.utc(2026, 6, 27),
  );

  setUpAll(sqfliteFfiInit);

  test('confirmed linked history improves a category suggestion', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await _createHistoryTables(db);

    for (var index = 0; index < 3; index++) {
      await _insertHistory(
        db,
        index: index,
        category: '午餐',
        createdAt: DateTime.utc(2026, 6, 20 + index),
      );
    }

    final suggestions = await service.suggestMany(
      db,
      <OfficialInvoiceCategorySuggestionInput>[
        OfficialInvoiceCategorySuggestionInput(
          id: 'history-driven',
          invoiceDate: DateTime(2026, 6, 26, 16),
          sellerIdentifier: '12345678',
          sellerName: '熟客商行',
          lineItems: const <CloudInvoiceLineItem>[
            CloudInvoiceLineItem(name: '本日商品', amount: 130),
          ],
        ),
      ],
    );
    final suggestion = suggestions['history-driven']!;

    expect(suggestion.category, '午餐');
    expect(suggestion.historyEvidenceCount, 3);
    expect(suggestion.canPrefill, isTrue);
    expect(suggestion.reasons.join('；'), contains('參考 3 筆'));
  });

  test('recent history outweighs older conflicting records', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await _createHistoryTables(db);

    for (var index = 0; index < 3; index++) {
      await _insertHistory(
        db,
        index: index,
        category: '早餐',
        createdAt: DateTime.utc(2023, 1, 10 + index),
      );
    }
    for (var index = 3; index < 5; index++) {
      await _insertHistory(
        db,
        index: index,
        category: '晚餐',
        createdAt: DateTime.utc(2026, 6, 20 + index),
      );
    }

    final suggestions = await service.suggestMany(
      db,
      <OfficialInvoiceCategorySuggestionInput>[
        OfficialInvoiceCategorySuggestionInput(
          id: 'recency-driven',
          invoiceDate: DateTime(2026, 6, 26, 16),
          sellerIdentifier: '12345678',
          sellerName: '熟客商行',
          lineItems: const <CloudInvoiceLineItem>[
            CloudInvoiceLineItem(name: '本日商品', amount: 130),
          ],
        ),
      ],
    );
    final suggestion = suggestions['recency-driven']!;

    expect(suggestion.category, '晚餐');
    expect(suggestion.historyEvidenceCount, 2);
    expect(suggestion.canPrefill, isTrue);
    expect(suggestion.reasons.join('；'), contains('近期歷史紀錄權重較高'));
  });
}

Future<void> _insertHistory(
  Database db, {
  required int index,
  required String category,
  required DateTime createdAt,
}) async {
  final transactionId = 'transaction-$index';
  await db.insert('transactions', <String, Object?>{
    'id': transactionId,
    'category': category,
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
    'created_at': createdAt.toIso8601String(),
  });
}

Future<void> _createHistoryTables(Database db) async {
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
}
