import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/features/merchant/business_registry_bounded_downloader.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';

void main() {
  group('P4.20.1-C bounded registry downloader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('p4_20_1_registry_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('streams exact bytes and verifies manifest SHA-256', () async {
      final payload = utf8.encode('abc');
      final client = _StreamingClient(
        payload: payload,
        declaredLength: payload.length,
      );
      final destination = File('${tempDir.path}/registry.gz.partial');
      final downloader = BusinessRegistryBoundedDownloader(client: client);

      final result = await downloader.download(
        manifest: _manifest(
          compressedSizeBytes: payload.length,
          downloadSha256:
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
        destinationTempFile: destination,
      );

      expect(await result.file.readAsBytes(), payload);
      expect(result.sizeBytes, payload.length);
      expect(
        result.sha256,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('fails closed and removes partial file on SHA mismatch', () async {
      final payload = utf8.encode('abc');
      final destination = File('${tempDir.path}/registry.gz.partial');
      final downloader = BusinessRegistryBoundedDownloader(
        client: _StreamingClient(
          payload: payload,
          declaredLength: payload.length,
        ),
      );

      await expectLater(
        downloader.download(
          manifest: _manifest(
            compressedSizeBytes: payload.length,
            downloadSha256: '0' * 64,
          ),
          destinationTempFile: destination,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_DOWNLOAD_SHA256_MISMATCH',
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
    });

    test('rejects declared Content-Length drift before writing bytes', () async {
      final payload = utf8.encode('abc');
      final destination = File('${tempDir.path}/registry.gz.partial');
      final downloader = BusinessRegistryBoundedDownloader(
        client: _StreamingClient(payload: payload, declaredLength: 4),
      );

      await expectLater(
        downloader.download(
          manifest: _manifest(
            compressedSizeBytes: payload.length,
            downloadSha256:
                'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
          destinationTempFile: destination,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_DOWNLOAD_CONTENT_LENGTH_MISMATCH',
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
    });

    test('rejects streamed bytes beyond manifest ceiling and cleans partial', () async {
      final payload = utf8.encode('abcd');
      final destination = File('${tempDir.path}/registry.gz.partial');
      final downloader = BusinessRegistryBoundedDownloader(
        client: _StreamingClient(payload: payload, declaredLength: null),
      );

      await expectLater(
        downloader.download(
          manifest: _manifest(
            compressedSizeBytes: 3,
            downloadSha256:
                'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
          destinationTempFile: destination,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'REGISTRY_DOWNLOAD_COMPRESSED_SIZE_EXCEEDED',
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
    });

    test('rejects non-200 response without leaving partial bytes', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      final downloader = BusinessRegistryBoundedDownloader(
        client: _StreamingClient(
          payload: const <int>[],
          declaredLength: 0,
          statusCode: HttpStatus.serviceUnavailable,
        ),
      );

      await expectLater(
        downloader.download(
          manifest: _manifest(
            compressedSizeBytes: 3,
            downloadSha256:
                'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
          destinationTempFile: destination,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(await destination.exists(), isFalse);
    });
  });
}

BusinessRegistryDistributionManifest _manifest({
  required int compressedSizeBytes,
  required String downloadSha256,
}) {
  return BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: '2026-09-01',
    sourceAuthority: 'MOEA_GCIS',
    sourceDataset: 'nationwide_company_business_branch',
    sourceDataDate: '2026-09-01',
    coverage: 'nationwide',
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: 1,
    downloadUri: Uri.parse(
      'https://github.com/easonliu714/my_finance_app_public/releases/download/registry-v1/registry.gz',
    ),
    downloadSha256: downloadSha256,
    registryContentSha256: '1' * 64,
    compressedSizeBytes: compressedSizeBytes,
    uncompressedSizeBytes: compressedSizeBytes + 1,
    attribution: '經濟部商業發展署 / data.gov.tw',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient({
    required this.payload,
    required this.declaredLength,
    this.statusCode = HttpStatus.ok,
  });

  final List<int> payload;
  final int? declaredLength;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(payload),
      statusCode,
      contentLength: declaredLength,
      request: request,
    );
  }
}
