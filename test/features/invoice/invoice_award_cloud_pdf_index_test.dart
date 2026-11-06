import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
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

  OfficialCloudAwardDownloadedArtifact artifact({String tierCode = 'cloud-800'}) {
    final pdf = File('${tempDir.path}/official.pdf')..writeAsStringSync('%PDF-fixture');
    return OfficialCloudAwardDownloadedArtifact(
      reference: OfficialCloudAwardArtifactReference(
        artifactId: '20260506_20260725124532_sorted_AI_E.pdf',
        sourceUri: Uri.parse(
          'https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124532_sorted_AI_E.pdf',
        ),
        periodId: '115-05-06',
        tierCode: tierCode,
      ),
      file: pdf,
      sizeBytes: pdf.lengthSync(),
      sha256: 'a' * 64,
    );
  }

  test(
    'Owner C direct cloud-500 index build is blocked before PDF decode or output I/O in release',
    () async {
      final output = File('${tempDir.path}/cloud500.index.candidate')
        ..writeAsStringSync('historical-candidate-preserved');
      final extractor = _CountingExtractor();

      // A caller cannot override the compile-time release policy.
      expect(
        Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
          tierCode: 'cloud-500',
          isReleaseBuild: true,
        ),
        isTrue,
      );
      expect(
        Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
          tierCode: 'cloud-500',
          isReleaseBuild: false,
        ),
        isFalse,
      );

      final operation = CloudAwardPdfIndexBuilder(
        extractor: extractor,
      ).buildCandidate(
        artifact: artifact(tierCode: 'cloud-500'),
        candidateIndexFile: output,
      );
      if (kReleaseMode) {
        await expectLater(
          operation,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              Cloud500ProductionPolicy.deferredCode,
            ),
          ),
        );
        expect(extractor.calls, 0);
        expect(output.readAsStringSync(), 'historical-candidate-preserved');
      } else {
        // Debug diagnostics remain usable; this does not authorize release.
        final result = await operation;
        expect(result.manifest.tierCode, 'cloud-500');
        expect(extractor.calls, 1);
        expect(output.readAsLinesSync(), <String>['AD00166192']);
      }
    },
  );

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

  test('Owner C direct cloud-500 local-index lookup fails closed in release',
      () async {
    final historical = File('${tempDir.path}/historical500.index')
      ..writeAsStringSync('AD00166192\\n');
    final missing = File('${tempDir.path}/missing500.index');
    final operation = const CloudAwardLocalIndexLookup().findMatches(
      tierCode: 'cloud-500',
      indexFile: kReleaseMode ? missing : historical,
      invoiceNumbers: const <String>['AD00166192'],
    );

    if (kReleaseMode) {
      await expectLater(
        operation,
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          Cloud500ProductionPolicy.deferredCode,
        )),
      );
      expect(await missing.exists(), isFalse);
    } else {
      // The independent Lab diagnostic path is not release authority.
      expect(await operation, <String>{'AD00166192'});
    }
    expect(historical.readAsStringSync(), 'AD00166192\\n');
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: 'cloud-500',
        isReleaseBuild: true,
      ),
      isTrue,
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
      tierCode: 'cloud-800',
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
        tierCode: 'cloud-800',
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

class _CountingExtractor extends CloudAwardPdfTextExtractor {
  int calls = 0;

  @override
  String get extractorVersion => 'counting-page-extractor-v1';

  @override
  Future<void> forEachPage(
    File pdfFile,
    CloudAwardPdfPageCallback onPage, {
    CloudAwardPdfExtractorProgressCallback? onProgress,
  }) async {
    calls += 1;
    await onPage(1, 1, 'AD00166192');
  }
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