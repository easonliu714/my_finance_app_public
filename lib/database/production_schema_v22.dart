import 'package:sqflite/sqflite.dart';

import 'production_schema_v21.dart' show createCanonicalProductionV21Tables;
import 'production_schema_v22_merchant_identity.dart';
export 'production_schema_v22_merchant_identity.dart'
    show normalizeMerchantIdentityName;

const int canonicalProductionSchemaVersion = 22;

enum ProductionSchemaV22MigrationStage {
  afterV21Base,
  afterMerchantIdentityTables,
}

typedef ProductionSchemaV22MigrationHook = Future<void> Function(
  ProductionSchemaV22MigrationStage stage,
);

Future<void> createCanonicalProductionV22Tables(
  DatabaseExecutor db, {
  ProductionSchemaV22MigrationHook? stageHook,
}) async {
  await createCanonicalProductionV21Tables(db);
  await stageHook?.call(ProductionSchemaV22MigrationStage.afterV21Base);
  await createMerchantIdentityV22CandidateTables(db);
  await stageHook?.call(
    ProductionSchemaV22MigrationStage.afterMerchantIdentityTables,
  );
}
