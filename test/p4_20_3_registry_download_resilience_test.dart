import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/features/merchant/business_registry_bounded_downloader.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';

void main() {
  group('P4.20.3+458 resumable Registry download', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('p4_20_3_resume_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('transient disconnect retains partial and Range retry completes SHA', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      final client = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.disconnectAfter(utf8.encode('abc')),
        _ResponsePlan.partial(utf8.encode('def'), start: 3, total: 6),
      ]);
      final progress = <BusinessRegistryDownloadProgress>[];
      final result = await BusinessRegistryBoundedDownloader(
        client: client,
        maxAttempts: 2,
        retryBackoff: Duration.zero,
      ).download(
        manifest: _manifest(6, 'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721'),
        destinationTempFile: destination,
        onProgress: progress.add,
      );

      expect(await result.file.readAsString(), 'abcdef');
      expect(client.ranges, <String?>[null, 'bytes=3-']);
      expect(progress.any((event) => event.attempt == 2 && event.resumedFromBytes == 3), isTrue);
    });

    test('manual retry after exhausted transient failure resumes retained bytes', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      final first = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.disconnectAfter(utf8.encode('abc')),
      ]);
      await expectLater(
        BusinessRegistryBoundedDownloader(
          client: first,
          maxAttempts: 1,
          retryBackoff: Duration.zero,
        ).download(
          manifest: _manifest(6, 'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721'),
          destinationTempFile: destination,
        ),
        throwsA(isA<BusinessRegistryTransientDownloadException>()),
      );
      expect(await destination.length(), 3);

      final second = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.partial(utf8.encode('def'), start: 3, total: 6),
      ]);
      final result = await BusinessRegistryBoundedDownloader(
        client: second,
        maxAttempts: 1,
        retryBackoff: Duration.zero,
      ).download(
        manifest: _manifest(6, 'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721'),
        destinationTempFile: destination,
      );
      expect(await result.file.readAsString(), 'abcdef');
      expect(second.ranges.single, 'bytes=3-');
    });

    test('server ignoring Range safely truncates and restarts', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      await destination.writeAsString('abc');
      final client = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.full(utf8.encode('abcdef')),
      ]);

      final result = await BusinessRegistryBoundedDownloader(
        client: client,
        maxAttempts: 1,
        retryBackoff: Duration.zero,
      ).download(
        manifest: _manifest(6, 'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721'),
        destinationTempFile: destination,
      );
      expect(client.ranges.single, 'bytes=3-');
      expect(await result.file.readAsString(), 'abcdef');
    });

    test('bad Content-Range fails closed and deletes partial', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      await destination.writeAsString('abc');
      final client = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.partial(utf8.encode('def'), start: 2, total: 6),
      ]);

      await expectLater(
        BusinessRegistryBoundedDownloader(
          client: client,
          maxAttempts: 1,
          retryBackoff: Duration.zero,
        ).download(
          manifest: _manifest(6, 'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721'),
          destinationTempFile: destination,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await destination.exists(), isFalse);
    });

    test('final SHA mismatch deletes completed partial', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      final client = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.full(utf8.encode('abcdef')),
      ]);
      await expectLater(
        BusinessRegistryBoundedDownloader(
          client: client,
          maxAttempts: 1,
          retryBackoff: Duration.zero,
        ).download(
          manifest: _manifest(6, '0' * 64),
          destinationTempFile: destination,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await destination.exists(), isFalse);
    });

    test('progress is monotonic and ETA never negative', () async {
      final destination = File('${tempDir.path}/registry.gz.partial');
      final client = _SequenceClient(<_ResponsePlan>[
        _ResponsePlan.full(utf8.encode('abcdef')),
      ]);
      final progress = <BusinessRegistryDownloadProgress>[];
      await BusinessRegistryBoundedDownloader(
        client: client,
        maxAttempts: 1,
        retryBackoff: Duration.zero,
      ).download(
        manifest: _manifest(6, 'bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721'),
        destinationTempFile: destination,
        onProgress: progress.add,
      );
      expect(progress, isNotEmpty);
      for (var index = 1; index < progress.length; index += 1) {
        expect(progress[index].downloadedBytes, greaterThanOrEqualTo(progress[index - 1].downloadedBytes));
      }
      expect(progress.every((event) => event.eta == null || !event.eta!.isNegative), isTrue);
      expect(progress.last.fraction, 1.0);
    });
  });
}

BusinessRegistryDistributionManifest _manifest(int size, String sha) {
  return BusinessRegistryDistributionManifest(
    schemaVersion: BusinessRegistryDistributionManifest.currentSchemaVersion,
    registryVersion: '2026-09-09-hotfix-458',
    sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
    sourceDataset: 'BGMOPEN1',
    sourceDataDate: '2026-09-09',
    coverage: 'taiwan_nationwide',
    format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
    entityCount: 1,
    downloadUri: Uri.parse('https://github.com/easonliu714/my_finance_app_public/releases/download/p4.20.3-registry/nationwide_registry.ndjson.gz'),
    downloadSha256: sha,
    registryContentSha256: '1' * 64,
    compressedSizeBytes: size,
    uncompressedSizeBytes: size + 1,
    attribution: 'FIA BGMOPEN1',
    licenseUri: Uri.parse('https://data.gov.tw/license'),
  );
}

class _SequenceClient extends http.BaseClient {
  _SequenceClient(this.plans);

  final List<_ResponsePlan> plans;
  final List<String?> ranges = <String?>[];
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    ranges.add(request.headers[HttpHeaders.rangeHeader]);
    final plan = plans[_index++];
    return plan.build(request);
  }
}

class _ResponsePlan {
  const _ResponsePlan({
    required this.bytes,
    required this.statusCode,
    this.headers = const <String, String>{},
    this.disconnect = false,
  });

  factory _ResponsePlan.full(List<int> bytes) => _ResponsePlan(
        bytes: bytes,
        statusCode: HttpStatus.ok,
      );

  factory _ResponsePlan.partial(List<int> bytes, {required int start, required int total}) =>
      _ResponsePlan(
        bytes: bytes,
        statusCode: HttpStatus.partialContent,
        headers: <String, String>{
          HttpHeaders.contentRangeHeader: 'bytes $start-${start + bytes.length - 1}/$total',
        },
      );

  factory _ResponsePlan.disconnectAfter(List<int> bytes) => _ResponsePlan(
        bytes: bytes,
        statusCode: HttpStatus.ok,
        disconnect: true,
      );

  final List<int> bytes;
  final int statusCode;
  final Map<String, String> headers;
  final bool disconnect;

  http.StreamedResponse build(http.BaseRequest request) {
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() {
      controller.add(bytes);
      if (disconnect) {
        controller.addError(const SocketException('simulated transient disconnect'));
      }
      controller.close();
    });
    return http.StreamedResponse(
      controller.stream,
      statusCode,
      contentLength: bytes.length,
      headers: headers,
      request: request,
    );
  }
}
