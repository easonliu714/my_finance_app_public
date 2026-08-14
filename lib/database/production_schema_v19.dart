import 'package:sqflite/sqflite.dart';

import 'production_schema_v18.dart' show createCanonicalProductionV18Tables;
import 'production_schema_v19_confirmation_tables.dart';

const int canonicalProductionSchemaVersion = 19;

Future<void> createCanonicalProductionV19Tables(
  DatabaseExecutor db,
) async {
  await createCanonicalProductionV18Tables(db);
  await createDebitCardSettlementConfirmationAuditTable(db);
}
