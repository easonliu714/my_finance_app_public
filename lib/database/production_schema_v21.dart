import 'package:sqflite/sqflite.dart';

import 'production_schema_v20.dart' show createCanonicalProductionV20Tables;
import 'production_schema_v21_wallet_top_up_execution.dart';

const int canonicalProductionSchemaVersion = 21;

enum ProductionSchemaV21MigrationStage {
  afterV20Base,
  afterWalletTopUpExecution,
}

typedef ProductionSchemaV21MigrationHook = Future<void> Function(
  ProductionSchemaV21MigrationStage stage,
);

Future<void> createCanonicalProductionV21Tables(
  DatabaseExecutor db, {
  ProductionSchemaV21MigrationHook? stageHook,
}) async {
  await createCanonicalProductionV20Tables(db);
  await stageHook?.call(ProductionSchemaV21MigrationStage.afterV20Base);
  await createWalletTopUpExecutionTable(db);
  await stageHook?.call(
    ProductionSchemaV21MigrationStage.afterWalletTopUpExecution,
  );
}
