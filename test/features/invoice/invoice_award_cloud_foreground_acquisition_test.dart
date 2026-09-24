import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_foreground_acquisition.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_index_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_index.dart';

void main() {
  late Directory supportDir;
  late Directory tempDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('cloud_fg_support_');
    tempDir = await Directory.systemTemp.createTemp('cloud_fg_temp_');
  });

  tearDown(() async {
    for (final directory in <Directory>[supportDir, tempDir]) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  CloudAwardIndexLkgRepository repository() =>
      CloudAwardIndexLkgRepository(
        supportDirectoryProvider: () async => supportDir,
      );

  MinistryOfFinanceCloudAwardForegroundAcquisitionService service({
    required http.Client client,
    CloudAwardIndexLkgRepository? repo,
    Uri? publicationUri,
    CloudAwardPdfIndexBuilder? indexBuilder,
  }) =>
      MinistryOfFinanceCloudAwardForegroundAcquisitionService(
        client: client,
        repository: repo ?? repository(),
        publicationUri: publicationUri,
        indexBuilder: indexBuilder ??
            const CloudAwardPdfIndexBuilder(
              extractor: _FixtureExtractor(),
            ),
        temporaryDirectoryProvider: () async => tempDir,
        clock: () => DateTime.utc(2026, 9, 25, 6),
      );

  test('downloads four official PDFs sequentially and promotes complete LKG',
      () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      if (request.url.path.startsWith('/pdf/')) {
        return _pdf();
      }
      return http.Response('unexpected', 404);
    });

    final result = await service(client: client).refresh(
      periodId: '115-07-08',
    );

    expect(result.isComplete, isTrue);
    expect(result.tiers, hasLength(4));
    expect(
      result.tiers.every(
        (item) => item.status == CloudAwardTierRefreshStatus.promoted,
      ),
      isTrue,
    );
    expect(requests.where((uri) => uri.path.startsWith('/pdf/')), hasLength(4));
    expect(
      requests.every(
        (uri) =>
            uri.scheme == 'https' &&
            uri.host == 'invoice.etax.nat.gov.tw',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (uri) =>
            uri.query.contains('invoice') ||
            uri.query.contains('transaction'),
      ),
      isFalse,
    );
  });

  test('current source and extractor LKG reuses all tiers with zero PDF GET',
      () async {
    final repo = repository();
    final seedClient = MockClient((request) async {
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      return _pdf();
    });
    final seeded = await service(client: seedClient, repo: repo).refresh(
      periodId: '115-07-08',
    );
    expect(seeded.isComplete, isTrue);

    final requests = <Uri>[];
    final reuseClient = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      return http.Response('PDF should not be requested', 500);
    });

    final result = await service(client: reuseClient, repo: repo).refresh(
      periodId: '115-07-08',
    );

    expect(result.isComplete, isTrue);
    expect(
      result.tiers.every(
        (item) => item.status == CloudAwardTierRefreshStatus.reused,
      ),
      isTrue,
    );
    expect(requests, hasLength(1));
    expect(requests.single.path, '/cloudNowNumber.html');
  });

  test('wrong period publication fails before any artifact request', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return _html(
        _publicationFixture.replaceAll('115年07-08月', '115年05-06月'),
      );
    });

    final result = await service(client: client).refresh(
      periodId: '115-07-08',
    );

    expect(result.isComplete, isFalse);
    expect(result.publicationFailureCode, 'CLOUD_AWARD_FORMAT_INVALID');
    expect(requests, hasLength(1));
  });

  test('one tier HTTP failure is incomplete while successful tiers remain LKG',
      () async {
    final repo = repository();
    final client = MockClient((request) async {
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      if (request.url.path.contains('_AI_E.pdf')) {
        return http.Response('temporary failure', 503);
      }
      return _pdf();
    });

    final result = await service(client: client, repo: repo).refresh(
      periodId: '115-07-08',
    );

    expect(result.isComplete, isFalse);
    expect(
      result.tiers
          .where((item) => item.status == CloudAwardTierRefreshStatus.failed),
      hasLength(1),
    );
    expect(
      await repo.readLatest(
        periodId: '115-07-08',
        tierCode: 'cloud-1000000',
      ),
      isNotNull,
    );
    expect(
      await repo.readLatest(
        periodId: '115-07-08',
        tierCode: 'cloud-800',
      ),
      isNull,
    );
  });

  test('temporary PDF and candidate index files are cleaned after refresh',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      return _pdf();
    });

    final result = await service(client: client).refresh(
      periodId: '115-07-08',
    );
    expect(result.isComplete, isTrue);

    final work = Directory(
      '${tempDir.path}${Platform.pathSeparator}invoice_award_cloud_refresh',
    );
    final leftovers = await work.exists()
        ? await work.list(followLinks: false).toList()
        : const <FileSystemEntity>[];
    expect(leftovers, isEmpty);
  });

  test('validated PDF cache survives extraction failure and prevents redownload',
      () async {
    final firstRequests = <Uri>[];
    final firstClient = MockClient((request) async {
      firstRequests.add(request.url);
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      if (request.url.path.startsWith('/pdf/')) return _pdf();
      return http.Response('unexpected', 404);
    });

    final first = await service(
      client: firstClient,
      indexBuilder: const CloudAwardPdfIndexBuilder(
        extractor: _AlwaysFailExtractor(),
      ),
    ).refresh(
      periodId: '115-07-08',
      retentionUntil: DateTime.utc(2027, 1, 5, 23, 59, 59),
    );

    expect(first.isComplete, isFalse);
    expect(
      firstRequests.where((uri) => uri.path.startsWith('/pdf/')),
      hasLength(4),
    );

    final secondRequests = <Uri>[];
    final secondClient = MockClient((request) async {
      secondRequests.add(request.url);
      if (request.url.path == '/cloudNowNumber.html') {
        return _html(_publicationFixture);
      }
      return http.Response('PDF must be reused from durable cache', 500);
    });

    final second = await service(client: secondClient).refresh(
      periodId: '115-07-08',
      retentionUntil: DateTime.utc(2027, 1, 5, 23, 59, 59),
    );

    expect(second.isComplete, isTrue);
    expect(secondRequests, hasLength(1));
    expect(secondRequests.single.path, '/cloudNowNumber.html');
  });

  test('previous-period cloud publication source can be explicitly selected',
      () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/cloudLastNumber.html') {
        return _html(
          _publicationFixture
              .replaceAll('115年07-08月', '115年05-06月')
              .replaceAll('20260708_', '20260506_'),
        );
      }
      if (request.url.path.startsWith('/pdf/')) return _pdf();
      return http.Response('unexpected', 404);
    });

    final result = await service(
      client: client,
      publicationUri:
          MinistryOfFinanceCloudAwardForegroundAcquisitionService
              .previousPublicationUri,
    ).refresh(periodId: '115-05-06');

    expect(result.isComplete, isTrue);
    expect(requests.first.path, '/cloudLastNumber.html');
  });
}

class _AlwaysFailExtractor extends CloudAwardPdfTextExtractor {
  const _AlwaysFailExtractor();

  @override
  String get extractorVersion => 'fixture-page-extractor-v1';

  @override
  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage,
  ) async {
    throw StateError('FIXTURE_EXTRACTION_FAILURE');
  }
}


class _FixtureExtractor extends CloudAwardPdfTextExtractor {
  const _FixtureExtractor();

  @override
  String get extractorVersion => 'fixture-page-extractor-v1';

  @override
  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage,
  ) async {
    await onPage(1, 1, 'ZX00000001 ZX00000002');
  }
}

http.Response _html(String value) => http.Response.bytes(
      utf8.encode(value),
      200,
      headers: const <String, String>{
        'content-type': 'text/html; charset=utf-8',
      },
    );

http.Response _pdf() {
  final bytes = utf8.encode(
    '%PDF-1.7\n'
    'fixture cloud award data fixture cloud award data fixture cloud award data\n'
    'fixture cloud award data fixture cloud award data fixture cloud award data\n'
    '%%EOF\n',
  );
  return http.Response.bytes(
    bytes,
    200,
    headers: const <String, String>{'content-type': 'application/pdf'},
  );
}

const _publicationFixture = '''
<html><body>
<h2>115年07-08月中獎號碼單</h2>
<a href="/pdf/20260708_20260925124520_sorted_AI_D.pdf">五百元獎中獎號碼清單PDF檔(已排序)</a>
<a href="/pdf/20260708_20260925124532_sorted_AI_E.pdf">八百元獎中獎號碼清單PDF檔(已排序)</a>
<a href="/pdf/20260708_20260925124524_sorted_AI_B.pdf">兩千元獎中獎號碼清單PDF檔(已排序)</a>
<a href="/pdf/20260708_20260925124522_sorted_AI_C.pdf">百萬元獎中獎清單PDF檔(已排序)</a>
</body></html>
''';