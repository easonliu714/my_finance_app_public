import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_index.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_award_index_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  OfficialCloudAwardDownloadedArtifact artifact() {
    final pdf = File('${tempDir.path}/official.pdf')..writeAsStringSync('%PDF-fixture');
    return OfficialCloudAwardDownloadedArtifact(
      reference: OfficialCloudAwardArtifactReference(
        artifactId: '20260506_20260725124532_sorted_AI_E.pdf',
        sourceUri: Uri.parse(
          'https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124532_sorted_AI_E.pdf',
        ),
        periodId: '115-05-06',
        tierCode: 'cloud-800',
      ),
      file: pdf,
      sizeBytes: pdf.lengthSync(),
      sha256: 'a' * 64,
    );
  }

  test('builds candidate index page by page with exact provenance', () async {
    final output = File('${tempDir.path}/cloud-800.index.candidate');
    final result = await const CloudAwardPdfIndexBuilder(
      extractor: _FakeExtractor(<String>[
        'header AD00166192 other text AD 00169681 A D 0 0 1 7 0 0 0 1',
        'AE12345678 footer',
      ]),
    ).buildCandidate(
      artifact: artifact(),
      candidateIndexFile: output,
      builtAt: DateTime.utc(2026, 7, 25, 7),
    );

    expect(
      await output.readAsLines(),
      <String>['AD00166192', 'AD00169681', 'AD00170001', 'AE12345678'],
    );
    expect(result.manifest.periodId, '115-05-06');
    expect(result.manifest.tierCode, 'cloud-800');
    expect(result.manifest.pdfSha256, 'a' * 64);
    expect(result.manifest.indexSha256, hasLength(64));
    expect(result.manifest.rowCount, 4);
    expect(
      result.manifest.extractorVersion,
      'fake-page-extractor-v1',
    );
  });

  test('lookup streams index and returns exact track plus 8-digit matches', () async {
    final index = File('${tempDir.path}/index.txt')
      ..writeAsStringSync(
        'AD00166192\n'
        'AD00169681\n'
        'AE12345678\n',
      );

    final matches = await const CloudAwardLocalIndexLookup().findMatches(
      indexFile: index,
      invoiceNumbers: const <String>[
        'AD-00169681',
        'ZZ99999999',
      ],
    );

    expect(matches, <String>{'AD00169681'});
  });

  test('malformed index fails closed during lookup', () async {
    final index = File('${tempDir.path}/index.txt')
      ..writeAsStringSync('AD00166192\nMALFORMED\n');

    await expectLater(
      const CloudAwardLocalIndexLookup().findMatches(
        indexFile: index,
        invoiceNumbers: const <String>['ZZ99999999'],
      ),
      throwsFormatException,
    );
  });

  test('empty extraction fails closed and removes candidate index', () async {
    final output = File('${tempDir.path}/empty.index.candidate');

    await expectLater(
      const CloudAwardPdfIndexBuilder(
        extractor: _FakeExtractor(<String>['no invoice numbers here']),
      ).buildCandidate(
        artifact: artifact(),
        candidateIndexFile: output,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'CLOUD_AWARD_INDEX_EMPTY',
        ),
      ),
    );

    expect(await output.exists(), isFalse);
  });

  test('embedded alphanumeric sequence is not accepted as an invoice number',
      () async {
    final output = File('${tempDir.path}/boundary.index.candidate');

    await expectLater(
      const CloudAwardPdfIndexBuilder(
        extractor: _FakeExtractor(<String>['XAD00166192Y']),
      ).buildCandidate(
        artifact: artifact(),
        candidateIndexFile: output,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeExtractor extends CloudAwardPdfTextExtractor {
  const _FakeExtractor(this.pages);

  final List<String> pages;

  @override
  String get extractorVersion => 'fake-page-extractor-v1';

  @override
  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage, {
    CloudAwardPdfExtractorProgressCallback? onProgress,
  }) async {
    for (var index = 0; index < pages.length; index += 1) {
      await onPage(index + 1, pages.length, pages[index]);
    }
  }
}