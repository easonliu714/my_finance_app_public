import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_update_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P4.20.1-D registry manifest HTTP failure', () {
    test('non-200 manifest response fails closed without touching registry', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await createCanonicalProductionV22Tables(db);

      final manifestUri = Uri.parse(
        'https://raw.githubusercontent.com/easonliu714/my_finance_app_public/'
        'p4-20-1-registry-production-update/registry/manifest.json',
      );
      final client = _StatusClient(statusCode: 503);
      final service = BusinessRegistryUpdateService(
        database: db,
        manifestUri: manifestUri,
        client: client,
      );

      await expectLater(service.fetchAvailableManifest(), throwsA(anything));
      expect(client.requests, 1);

      final snapshots = await db.query('business_registry_snapshots');
      final entities = await db.query('business_registry_entities');
      expect(snapshots, isEmpty);
      expect(entities, isEmpty);
    });
  });
}

class _StatusClient extends http.BaseClient {
  _StatusClient({required this.statusCode});

  final int statusCode;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests += 1;
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      statusCode,
      request: request,
    );
  }
}
