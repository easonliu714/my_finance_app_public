import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/ephemeral_authenticated_csv_download.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ephemeral_csv_test_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  EphemeralAuthenticatedCsvDownloadService buildService() {
    return EphemeralAuthenticatedCsvDownloadService(
      tempDirectoryProvider: () async => root,
      allowedHosts: const <String>{'www.einvoice.nat.gov.tw'},
    );
  }

  EphemeralCsvDownloadRequest requestFor(Uri url) {
    return EphemeralCsvDownloadRequest(
      url: url,
      userAgent: 'test-agent',
      mimeType: 'text/csv',
      contentDisposition: 'attachment; filename="invoice.csv"',
      suggestedFilename: 'invoice.csv',
      contentLength: 100,
      cookieHeader: 'session=transient',
    );
  }

  test('rejects non-HTTPS before any network request', () async {
    final service = buildService();

    await expectLater(
      service.downloadAndParse(
        requestFor(
          Uri.parse('http://www.einvoice.nat.gov.tw/export.csv'),
        ),
      ),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'code',
          'CSV_HTTPS_REQUIRED',
        ),
      ),
    );
  });

  test('rejects a non-approved host before reading cookies or bytes', () async {
    final service = buildService();

    await expectLater(
      service.downloadAndParse(
        requestFor(Uri.parse('https://example.test/export.csv')),
      ),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'code',
          'CSV_HOST_NOT_APPROVED',
        ),
      ),
    );
  });

  test('rejected metadata does not poison the next request', () async {
    final service = buildService();

    await expectLater(
      service.downloadAndParse(
        requestFor(
          Uri.parse('http://www.einvoice.nat.gov.tw/export.csv'),
        ),
      ),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'first code',
          'CSV_HTTPS_REQUIRED',
        ),
      ),
    );

    await expectLater(
      service.downloadAndParse(
        requestFor(Uri.parse('https://example.test/export.csv')),
      ),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'second code',
          'CSV_HOST_NOT_APPROVED',
        ),
      ),
    );
  });

  test('rejects download-start metadata above the size cap', () async {
    final service = buildService();
    final request = EphemeralCsvDownloadRequest(
      url: Uri.parse('https://www.einvoice.nat.gov.tw/export.csv'),
      userAgent: 'test-agent',
      mimeType: 'text/csv',
      contentDisposition: 'attachment; filename="invoice.csv"',
      suggestedFilename: 'invoice.csv',
      contentLength: 10 * 1024 * 1024 + 1,
      cookieHeader: 'session=transient',
    );

    await expectLater(
      service.downloadAndParse(request),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'code',
          'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
        ),
      ),
    );
  });

  test('startup cleanup removes only ephemeral cache files', () async {
    final cache = Directory(
      p.join(
        root.path,
        EphemeralAuthenticatedCsvDownloadService.cacheDirectoryName,
      ),
    );
    await cache.create(recursive: true);
    final stale = File(
      p.join(
        cache.path,
        '${EphemeralAuthenticatedCsvDownloadService.filePrefix}old.part',
      ),
    );
    final unrelated = File(p.join(cache.path, 'keep.txt'));
    await stale.writeAsString('sensitive');
    await unrelated.writeAsString('unrelated');

    await buildService().cleanupStaleFiles();

    expect(await stale.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('error text exposes only a stable code', () {
    const error = EphemeralCsvDownloadException('CSV_NETWORK_FAILED');
    expect(error.toString(), 'CSV_NETWORK_FAILED');
    expect(error.toString(), isNot(contains('session=')));
    expect(error.toString(), isNot(contains('einvoice')));
  });
}
