import 'package:sqflite/sqflite.dart';

const String merchantSellerIdentifierColumn = 'seller_identifier';

Future<void> ensureMerchantSellerIdentifierSchema(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(merchants)');
  final hasColumn = columns.any(
    (row) => row['name']?.toString() == merchantSellerIdentifierColumn,
  );
  if (!hasColumn) {
    await db.execute(
      "ALTER TABLE merchants ADD COLUMN seller_identifier TEXT NOT NULL DEFAULT ''",
    );
  }

  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_seller_identifier_unique
    ON merchants(seller_identifier)
    WHERE seller_identifier <> ''
  ''');
}
