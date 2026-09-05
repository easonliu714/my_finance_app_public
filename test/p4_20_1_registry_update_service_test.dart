import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/database/production_schema_v22.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest_codec.dart';
import 'package:my_finance_app/features/merchant/business_registry_nationwide_builder.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:my_finance_app/features/merchant/business_registry_update_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P4.20.1-D controlled registry update service', () {
    late Database db;
    late Directory tempDir;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await createCanonicalProductionV22Tables(db);
      tempDir = await Directory.systemTemp.createTemp('p4_20_1_update_');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('manifest to bounded artifact installs exact nationwide snapshot', () async {
      final fixture = await _buildFixture(version: '2026-09-01');
      final manifestUri = Uri.parse(
        'https://raw.githubusercontent.com/easonliu714/my_finance_app_public/p4-20-1-registry-production-update/registry/manifest.json',
      );
      final client = _RouteClient(<String, _HttpFixture>{
        manifestUri.toString(): _HttpFixture(
          bytes: utf8.encode(fixture.manifest.toCanonicalJsonText()),
        ),
        fixture.manifest.downloadUri.toString(): _HttpFixture(
          bytes: fixture.compressedBytes,
        ),
      });
      final service = BusinessRegistryUpdateService(
        database: db,
        manifestUri: manifestUri,
        client: client,
        tempDirectoryProvider: () async => tempDir,
      );

      expect(service.isDistributionConfigured, isTrue);
      final result = await service.update();

      expect(result.status, BusinessRegistryUpdateStatus.updated);
      expect(result.snapshot?.version, '2026-09-01');
      expect(result.snapshot?.coverage, BusinessRegistryPack.nationwideCoverage);
      expect(result.snapshot?.contentSha256, fixture.manifest.registryContentSha256);
      expect(client.requestCount(manifestUri), 1);
      expect(client.requestCount(fixture.manifest.downloadUri), 1);

      final lookup = await BusinessRegistryRepository(database: db).lookup('12345678');
      expect(lookup.isHit, isTrue);
      expect(lookup.primaryEntity?.legalName, '甲公司');

      final partials = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.partial'));
      expect(partials, isEmpty);
    });

    test('bad artifact fails and preserves previous installed snapshot', () async {
      final previous = await _smallPack(
        version: '2026-08-01',
        sellerIdentifier: '30340553',
        legalName: '上一版官方資料',
      );
      final repository = BusinessRegistryRepository(database: db);
      await repository.install(previous);

      final fixture = await _buildFixture(version: '2026-09-01');
      final manifestUri = Uri.parse(
        'https://raw.githubusercontent.com/easonliu714/my_finance_app_public/p4-20-1-registry-production-update/registry/manifest.json',
      );
      final client = _RouteClient(<String, _HttpFixture>{
        manifestUri.toString(): _HttpFixture(
          bytes: utf8.encode(fixture.manifest.toCanonicalJsonText()),
        ),
        fixture.manifest.downloadUri.toString(): const _HttpFixture(
          bytes: <int>[1, 2, 3, 4],
          declaredLength: null,
        ),
      });
      final service = BusinessRegistryUpdateService(
        database: db,
        manifestUri: manifestUri,
        client: client,
        tempDirectoryProvider: () async => tempDir,
      );

      await expectLater(service.update(), throwsA(anything));

      final retained = await repository.installedSnapshot();
      expect(retained?.version, '2026-08-01');
      final oldLookup = await repository.lookup('30340553');
      expect(oldLookup.primaryEntity?.legalName, '上一版官方資料');
      final newRows = await db.query(
        'business_registry_snapshots',
        where: 'version = ?',
        whereArgs: const <Object?>['2026-09-01'],
      );
      expect(newRows, isEmpty);
    });

    test('manifest acquisition rejects untrusted URL before network request', () async {
      final client = _RouteClient(const <String, _HttpFixture>{});
      final service = BusinessRegistryUpdateService(
        database: db,
        manifestUri: Uri.parse('https://data.gcis.nat.gov.tw/manifest.json'),
        client: client,
        tempDirectoryProvider: () async => tempDir,
      );

      expect(service.isDistributionConfigured, isFalse);
      await expectLater(
        service.fetchAvailableManifest(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_MANIFEST_URL_NOT_ALLOWED',
          ),
        ),
      );
      expect(client.totalRequests, 0);
    });

    test('manifest streaming ceiling rejects oversized response', () async {
      final manifestUri = Uri.parse(
        'https://raw.githubusercontent.com/easonliu714/my_finance_app_public/p4-20-1-registry-production-update/registry/manifest.json',
      );
      final oversized = List<int>.filled(
        BusinessRegistryDistributionManifest.maxManifestSizeBytes + 1,
        0x20,
      );
      final client = _RouteClient(<String, _HttpFixture>{
        manifestUri.toString(): _HttpFixture(
          bytes: oversized,
          declaredLength: null,
          chunkSize: 4096,
        ),
      });
      final service = BusinessRegistryUpdateService(
        database: db,
        manifestUri: manifestUri,
        client: client,
        tempDirectoryProvider: () async => tempDir,
      );

      await expectLater(
        service.fetchAvailableManifest(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_MANIFEST_SIZE_EXCEEDED',
          ),
        ),
      );
    });
  });
}

Future<_RegistryFixture> _buildFixture({required String version}) async {
  const entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: '12345678',
      entityType: BusinessRegistryEntityType.company,
      legalName: '甲公司',
      registrationStatus: '核准設立',
      sourceDataset: 'nationwide_company_business_branch',
    ),
    BusinessRegistryEntity(
      sellerIdentifier: '87654321',
      entityType: BusinessRegistryEntityType.business,
      legalName: '乙商號',
      registrationStatus: '核准設立',
      sourceDataset: 'nationwide_company_business_branch',
    ),
  ];
  final entityLines = entities
      .map(BusinessRegistryNationwideBuildPass.canonicalEntityLine)
      .toList(growable: false);
  final contentSha = await _sha256(utf8.encode(entityLines.join()));
  final header = '${jsonEncode(<String, Object?>{
    'record_type': 'header',
    'registry_version': version,
    'source_authority': 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    'source_dataset': 'nationwide_company_business_branch',
    'source_data_date': '2026-09-01',
    'coverage': BusinessRegistryPack.nationwideCoverage,
    'entity_count': entities.length,
    'registry_content_sha256': contentSha,
  })}\n';
  final uncompressed = utf8.encode('$header${entityLines.join()}');
  final compressed = gzip.encode(uncompressed);
  final downloadSha = await _sha256(compressed);
  final manifest = BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: version,
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'nationwide_company_business_branch',
    sourceDataDate: '2026-09-01',
    coverage: BusinessRegistryPack.nationwideCoverage,
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: entities.length,
    downloadUri: Uri.parse(
      'https://github.com/easonliu714/my_finance_app_public/releases/download/business-registry-v1/$version.registry.gz',
    ),
    downloadSha256: downloadSha,
    registryContentSha256: contentSha,
    compressedSizeBytes: compressed.length,
    uncompressedSizeBytes: uncompressed.length,
    attribution: '資料提供機關／經濟部商業發展署',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
  return _RegistryFixture(manifest: manifest, compressedBytes: compressed);
}

Future<BusinessRegistryPack> _smallPack({
  required String version,
  required String sellerIdentifier,
  required String legalName,
}) async {
  final entities = <BusinessRegistryEntity>[
    BusinessRegistryEntity(
      sellerIdentifier: sellerIdentifier,
      entityType: BusinessRegistryEntityType.business,
      legalName: legalName,
      sourceDataset: 'previous_nationwide',
    ),
  ];
  return BusinessRegistryPack(
    version: version,
    sourceAuthority: 'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    sourceDataset: 'previous_nationwide',
    sourceDataDate: version,
    coverage: BusinessRegistryPack.nationwideCoverage,
    contentSha256: await computeBusinessRegistryPayloadSha256(entities),
    entities: entities,
  );
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class _RegistryFixture {
  const _RegistryFixture({
    required this.manifest,
    required this.compressedBytes,
  });

  final BusinessRegistryDistributionManifest manifest;
  final List<int> compressedBytes;
}

class _HttpFixture {
  const _HttpFixture({
    required this.bytes,
    this.declaredLength,
    this.chunkSize,
  });

  final List<int> bytes;
  final int? declaredLength;
  final int? chunkSize;
}

class _RouteClient extends http.BaseClient {
  _RouteClient(this.fixtures);

  final Map<String, _HttpFixture> fixtures;
  final Map<String, int> _counts = <String, int>{};

  int get totalRequests =>
      _counts.values.fold<int>(0, (total, count) => total + count);

  int requestCount(Uri uri) => _counts[uri.toString()] ?? 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.toString();
    _counts[key] = (_counts[key] ?? 0) + 1;
    final fixture = fixtures[key];
    if (fixture == null) {
      throw StateError('UNEXPECTED_HTTP_REQUEST:$key');
    }
    final chunkSize = fixture.chunkSize ?? fixture.bytes.length;
    final chunks = <List<int>>[];
    if (fixture.bytes.isEmpty) {
      chunks.add(const <int>[]);
    } else {
      for (var offset = 0; offset < fixture.bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize < fixture.bytes.length)
            ? offset + chunkSize
            : fixture.bytes.length;
        chunks.add(fixture.bytes.sublist(offset, end));
      }
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      HttpStatus.ok,
      contentLength: fixture.declaredLength ?? fixture.bytes.length,
      request: request,
    );
  }
}
