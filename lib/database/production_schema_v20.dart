import 'package:sqflite/sqflite.dart';

import 'production_schema_v19.dart' show createCanonicalProductionV19Tables;
import 'production_schema_v20_wallet_top_up_tables.dart';

const int canonicalProductionSchemaVersion = 20;

enum ProductionSchemaV20MigrationStage {
  afterV19Base,
  afterWalletTopUpTables,
}

typedef ProductionSchemaV20MigrationHook = Future<void> Function(
  ProductionSchemaV20MigrationStage stage,
);

Future<void> createCanonicalProductionV20Tables(
  DatabaseExecutor db, {
  ProductionSchemaV20MigrationHook? stageHook,
}) async {
  await createCanonicalProductionV19Tables(db);
  await stageHook?.call(ProductionSchemaV20MigrationStage.afterV19Base);
  await createWalletTopUpPersistenceTables(db);
  await stageHook?.call(
    ProductionSchemaV20MigrationStage.afterWalletTopUpTables,
  );
}
