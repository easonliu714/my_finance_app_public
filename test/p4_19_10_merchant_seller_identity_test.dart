import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_master_binding_service.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/merchant/merchant_seller_identifier_migration.dart';
import 'package:my_finance_app/features/merchant/merchant_seller_identity_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('merchant seller identifier migration adds column and unique partial index', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE merchants (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        alias TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await ensureMerchantSellerIdentifierSchema(db);
    await ensureMerchantSellerIdentifierSchema(db);

    final columns = await db.rawQuery('PRAGMA table_info(merchants)');
    expect(
      columns.any((row) => row['name'] == 'seller_identifier'),
      isTrue,
    );
    final indexes = await db.rawQuery('PRAGMA index_list(merchants)');
    expect(
      indexes.any(
        (row) =>
            row['name'] == 'idx_merchants_seller_identifier_unique' &&
            row['unique'] == 1,
      ),
      isTrue,
    );
  });

  test('explicit binding creates merchant and seller tax identity together', () async {
    final store = _FakeMerchantSellerIdentityStore();
    final service = InvoiceMerchantMasterBindingService(store: store);

    final result = await service.bind(
      merchantName: '測試商店',
      sellerTaxId: '12345675',
    );

    expect(result.status, InvoiceMerchantMasterBindingStatus.created);
    expect(result.merchant?.name, '測試商店');
    expect(result.merchant?.sellerIdentifier, '12345675');
    expect(store.rows, hasLength(1));
  });

  test('seller identifier conflict fails closed without overwriting master', () async {
    final store = _FakeMerchantSellerIdentityStore(
      <MerchantRecord>[
        MerchantRecord(
          id: 'merchant-a',
          name: '既有商家',
          sellerIdentifier: '12345675',
        ),
      ],
    );
    final service = InvoiceMerchantMasterBindingService(store: store);

    final result = await service.bind(
      merchantName: '另一商家',
      sellerTaxId: '12345675',
    );

    expect(result.status, InvoiceMerchantMasterBindingStatus.conflict);
    expect(store.rows, hasLength(1));
    expect(store.rows.single.name, '既有商家');
  });
}

class _FakeMerchantSellerIdentityStore implements MerchantSellerIdentityStore {
  _FakeMerchantSellerIdentityStore([List<MerchantRecord>? seed])
      : rows = <MerchantRecord>[...?seed];

  final List<MerchantRecord> rows;

  @override
  Future<MerchantRecord?> findBySellerIdentifier(
    String sellerIdentifier, {
    bool includeArchived = false,
  }) async {
    for (final row in rows) {
      if (row.sellerIdentifier == sellerIdentifier &&
          (includeArchived || !row.isArchived)) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<List<MerchantRecord>> listMerchants({
    bool includeArchived = false,
  }) async {
    return rows
        .where((row) => includeArchived || !row.isArchived)
        .toList(growable: false);
  }

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    final index = rows.indexWhere((row) => row.id == merchant.id);
    if (index < 0) {
      rows.add(merchant);
    } else {
      rows[index] = merchant;
    }
  }
}
