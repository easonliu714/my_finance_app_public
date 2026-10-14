import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_index_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_index.dart';

void main() {
  late Directory tempDir;
  late CloudAwardIndexLkgRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_award_lkg_');
    repository = CloudAwardIndexLkgRepository(
      supportDirectoryProvider: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<CloudAwardIndexBuildResult> build({
    String periodId = '115-05-06',
    String tierCode = 'cloud-800',
    String source =
        'https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124532_sorted_AI_E.pdf',
    String body = 'AD00166192\nAD00169681\n',
    DateTime? builtAt,
  }) async {
    final file = File('${tempDir.path}/candidate-$tierCode.index')
      ..writeAsStringSync(body);
    final sha = await _sha256(file);
    final rows = body
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    return CloudAwardIndexBuildResult(
      candidateIndexFile: file,
      manifest: CloudAwardLocalIndexManifest(
        periodId: periodId,
        tierCode: tierCode,
        officialSourceUri: Uri.parse(source),
        pdfSha256: 'a' * 64,
        indexSha256: sha,
        extractorVersion: 'fixture-v1',
        rowCount: rows,
        builtAt: builtAt ?? DateTime.utc(2026, 7, 25, 8),
      ),
    );
  }

  test('promotes validated immutable index and reads it back', () async {
    final result = await repository.promoteValidated(build: await build());

    expect(result.status, CloudAwardIndexPromotionStatus.promoted);
    expect(await result.snapshot.indexFile.readAsLines(), <String>[
      'AD00166192',
      'AD00169681',
    ]);
    expect(result.snapshot.manifest.rowCount, 2);

    final readBack = await repository.readLatest(
      periodId: '115-05-06',
      tierCode: 'cloud-800',
    );
    expect(readBack, isNotNull);
    expect(
      readBack!.manifest.indexSha256,
      result.snapshot.manifest.indexSha256,
    );
  });

  test('same content-addressed snapshot is reused as already current', () async {
    final first = await build();
    final firstResult = await repository.promoteValidated(build: first);
    final second = await build();

    final secondResult = await repository.promoteValidated(build: second);

    expect(firstResult.status, CloudAwardIndexPromotionStatus.promoted);
    expect(secondResult.status, CloudAwardIndexPromotionStatus.alreadyCurrent);
    expect(
      secondResult.snapshot.indexFile.path,
      firstResult.snapshot.indexFile.path,
    );
  });

  test('bad candidate index SHA fails without replacing prior LKG', () async {
    final old = await repository.promoteValidated(
      build: await build(
        body: 'AD00166192\n',
        builtAt: DateTime.utc(2026, 7, 25, 7),
      ),
    );

    final invalid = await build(
      body: 'ZZ99999999\n',
      builtAt: DateTime.utc(2026, 7, 25, 9),
    );
    final forged = CloudAwardIndexBuildResult(
      candidateIndexFile: invalid.candidateIndexFile,
      manifest: CloudAwardLocalIndexManifest(
        periodId: invalid.manifest.periodId,
        tierCode: invalid.manifest.tierCode,
        officialSourceUri: invalid.manifest.officialSourceUri,
        pdfSha256: invalid.manifest.pdfSha256,
        indexSha256: '0' * 64,
        extractorVersion: invalid.manifest.extractorVersion,
        rowCount: invalid.manifest.rowCount,
        builtAt: invalid.manifest.builtAt,
      ),
    );

    await expectLater(
      repository.promoteValidated(build: forged),
      throwsA(isA<StateError>()),
    );

    final latest = await repository.readLatest(
      periodId: '115-05-06',
      tierCode: 'cloud-800',
    );
    expect(latest, isNotNull);
    expect(latest!.manifest.indexSha256, old.snapshot.manifest.indexSha256);
  });

  test('malformed candidate line fails closed and leaves old LKG', () async {
    final old = await repository.promoteValidated(
      build: await build(body: 'AD00166192\n'),
    );

    final bad = File('${tempDir.path}/candidate-bad.index')
      ..writeAsStringSync('MALFORMED\n');
    final badSha = await _sha256(bad);
    final invalid = CloudAwardIndexBuildResult(
      candidateIndexFile: bad,
      manifest: CloudAwardLocalIndexManifest(
        periodId: '115-05-06',
        tierCode: 'cloud-800',
        officialSourceUri: Uri.parse(
          'https://invoice.etax.nat.gov.tw/pdf/20260506_bad_sorted_AI_E.pdf',
        ),
        pdfSha256: 'b' * 64,
        indexSha256: badSha,
        extractorVersion: 'fixture-v1',
        rowCount: 1,
        builtAt: DateTime.utc(2026, 7, 25, 10),
      ),
    );

    await expectLater(
      repository.promoteValidated(build: invalid),
      throwsFormatException,
    );

    final latest = await repository.readLatest(
      periodId: '115-05-06',
      tierCode: 'cloud-800',
    );
    expect(latest!.manifest.indexSha256, old.snapshot.manifest.indexSha256);
  });

  test('wrong period tier or source fails before promotion', () async {
    await expectLater(
      repository.promoteValidated(
        build: await build(periodId: 'bad-period'),
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.promoteValidated(
        build: await build(tierCode: 'cloud-123'),
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.promoteValidated(
        build: await build(source: 'https://example.com/cloud.pdf'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<String> _sha256(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  final hash = await sink.hash();
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
