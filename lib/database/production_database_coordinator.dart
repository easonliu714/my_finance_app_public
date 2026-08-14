import 'package:sqflite/sqflite.dart';

import '../features/account/account_repository.dart';
import 'production_schema_audit.dart';
import 'production_schema_v21.dart';

class ProductionDatabaseCoordinator {
  ProductionDatabaseCoordinator._();

  static final ProductionDatabaseCoordinator instance =
      ProductionDatabaseCoordinator._();

  static const String databaseName = 'my_finance_app.db';
  static const int schemaVersion = canonicalProductionSchemaVersion;

  final ProductionSchemaAuditService _schemaAudit =
      const ProductionSchemaAuditService();

  Future<Database> get database => AccountRepository.instance.database;

  Future<ProductionSchemaAuditReport> auditSchema() async {
    final db = await database;
    return _schemaAudit.inspect(db);
  }
}
