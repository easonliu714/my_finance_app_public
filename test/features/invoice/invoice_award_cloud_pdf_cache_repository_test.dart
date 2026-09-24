import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_cache_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cloud_pdf_cache_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CloudAwardPdfCacheRepository repository() => CloudAwardPdfCacheRepository(
        rootDirectoryProvider: () async => root,
      );

  test('promotes validated PDF and reuses exact publication artifact', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}download.partial',
    );
    final bytes = _pdfBytes();
    await source.writeAsBytes(bytes, flush: true);
    final sha = await _sha256(source);
    final reference = _reference();

    final snapshot = await repository().promoteValidated(
      artifact: OfficialCloudAwardDownloadedArtifact(
        reference: reference,
        file: source,
        sizeBytes: bytes.length,
        sha256: sha,
      ),
      downloadedAtUtc: DateTime.utc(2026, 9, 24),
      retentionUntilUtc: DateTime.utc(2026, 11, 5, 23, 59, 59),
    );

    expect(await snapshot.pdfFile.exists(), isTrue);
    expect(snapshot.manifest.pdfSha256, sha);
    expect(snapshot.manifest.artifactId, reference.artifactId);

    final reused = await repository().readValidated(reference: reference);
    expect(reused, isNotNull);
    expect(reused!.manifest.pdfSha256, sha);
    expect(await reused.pdfFile.length(), bytes.length);
  });

  test('different official artifact identity is never reused', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}download.partial',
    );
    final bytes = _pdfBytes();
    await source.writeAsBytes(bytes, flush: true);
    final sha = await _sha256(source);
    final reference = _reference();

    await repository().promoteValidated(
      artifact: OfficialCloudAwardDownloadedArtifact(
        reference: reference,
        file: source,
        sizeBytes: bytes.length,
        sha256: sha,
      ),
      downloadedAtUtc: DateTime.utc(2026, 9, 24),
      retentionUntilUtc: DateTime.utc(2026, 11, 5, 23, 59, 59),
    );

    final changed = OfficialCloudAwardArtifactReference(
      artifactId: '20260506_20260924130000_sorted_AI_D.pdf',
      sourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/pdf/'
        '20260506_20260924130000_sorted_AI_D.pdf',
      ),
      periodId: '115-05-06',
      tierCode: 'cloud-500',
    );
    expect(await repository().readValidated(reference: changed), isNull);
  });

  test('expired period PDF cache is pruned after redemption deadline', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}download.partial',
    );
    final bytes = _pdfBytes();
    await source.writeAsBytes(bytes, flush: true);
    final sha = await _sha256(source);
    final reference = _reference();

    final snapshot = await repository().promoteValidated(
      artifact: OfficialCloudAwardDownloadedArtifact(
        reference: reference,
        file: source,
        sizeBytes: bytes.length,
        sha256: sha,
      ),
      downloadedAtUtc: DateTime.utc(2026, 9, 24),
      retentionUntilUtc: DateTime.utc(2026, 11, 5, 23, 59, 59),
    );

    expect(
      await repository().pruneExpired(
        nowUtc: DateTime.utc(2026, 11, 6),
      ),
      1,
    );
    expect(await snapshot.pdfFile.exists(), isFalse);
    expect(await repository().readValidated(reference: reference), isNull);
  });

  test('corrupt cached PDF fails closed', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}download.partial',
    );
    final bytes = _pdfBytes();
    await source.writeAsBytes(bytes, flush: true);
    final sha = await _sha256(source);
    final reference = _reference();

    final snapshot = await repository().promoteValidated(
      artifact: OfficialCloudAwardDownloadedArtifact(
        reference: reference,
        file: source,
        sizeBytes: bytes.length,
        sha256: sha,
      ),
      downloadedAtUtc: DateTime.utc(2026, 9, 24),
      retentionUntilUtc: DateTime.utc(2026, 11, 5, 23, 59, 59),
    );
    await snapshot.pdfFile.writeAsString('corrupt', flush: true);

    expect(await repository().readValidated(reference: reference), isNull);
  });
}

OfficialCloudAwardArtifactReference _reference() =>
    OfficialCloudAwardArtifactReference(
      artifactId: '20260506_20260725124620_sorted_AI_D.pdf',
      sourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/pdf/'
        '20260506_20260725124620_sorted_AI_D.pdf',
      ),
      periodId: '115-05-06',
      tierCode: 'cloud-500',
    );

List<int> _pdfBytes() => <int>[
      ...'%PDF-1.7\n'.codeUnits,
      ...List<int>.filled(96, 65),
      ...'\n%%EOF\n'.codeUnits,
    ];

Future<String> _sha256(File file) async {
  final hash = await Sha256().hashStream(file.openRead());
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
