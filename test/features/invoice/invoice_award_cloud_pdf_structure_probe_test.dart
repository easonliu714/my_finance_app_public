import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'cloud_award_pdf_structure_probe_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('characterizes classic xref with bounded structural evidence', () async {
    const candidate = 'BM23888900';
    final file = await _writeFixture(
      tempDir,
      'classic.pdf',
      _classicFixture(candidate: candidate),
    );

    final result = await const CloudAwardPdfStructureProbe().inspect(
      file: file,
      exactCandidateNumbers: const <String>[candidate],
    );

    expect(result.pdfVersion, '1.7');
    expect(result.byteLength, await file.length());
    expect(result.startXrefOffset, greaterThan(0));
    expect(result.xrefTopology, CloudAwardPdfXrefTopology.classicTable);
    expect(result.objectStreamCount, 0);
    expect(result.streamCount, 1);
    expect(result.filterHistogram['FlateDecode'], 1);
    expect(result.declaredPageCounts, contains(77000));
    expect(result.rawVisibleCandidateNumbers, contains(candidate));
    expect(result.hasEncryptionMarker, isFalse);
    expect(result.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('safe diagnostic text never exposes exact candidate values', () async {
    const candidate = 'BM23888900';
    final file = await _writeFixture(
      tempDir,
      'diagnostic.pdf',
      _classicFixture(candidate: candidate),
    );

    final result = await const CloudAwardPdfStructureProbe().inspect(
      file: file,
      exactCandidateNumbers: const <String>[candidate],
    );
    final diagnostic = result.safeDiagnosticText(candidateCount: 1);

    expect(diagnostic, contains('raw_candidate_hits=1/1'));
    expect(diagnostic, contains('sha256='));
    expect(diagnostic, isNot(contains(candidate)));
  });

  test('classifies xref stream without opening a document model', () async {
    final file = await _writeFixture(
      tempDir,
      'xref_stream.pdf',
      _xrefStreamFixture(),
    );

    final result = await const CloudAwardPdfStructureProbe().inspect(
      file: file,
    );

    expect(result.xrefTopology, CloudAwardPdfXrefTopology.xrefStream);
    expect(result.filterHistogram['FlateDecode'], 1);
  });

  test('classifies classic xref with XRefStm as hybrid', () async {
    final file = await _writeFixture(
      tempDir,
      'hybrid.pdf',
      _classicFixture(
        trailerExtras: '/XRefStm 42',
      ),
    );

    final result = await const CloudAwardPdfStructureProbe().inspect(
      file: file,
    );

    expect(result.xrefTopology, CloudAwardPdfXrefTopology.hybrid);
  });

  test('fails closed when terminal startxref is outside the file', () async {
    final file = await _writeFixture(
      tempDir,
      'invalid_startxref.pdf',
      '%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          'startxref\n999999\n%%EOF\n',
    );

    expect(
      () => const CloudAwardPdfStructureProbe().inspect(file: file),
      throwsA(
        isA<CloudAwardPdfStructureProbeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STRUCTURE_STARTXREF_INVALID',
        ),
      ),
    );
  });

  test('finds exact candidate split across bounded scan chunks', () async {
    const candidate = 'BM23888900';
    const chunkBytes = 128;
    const overlapBytes = 32;
    const prefix =
        '%PDF-1.7\n1 0 obj\n<< /Type /Pages /Count 77000 >>\nstream\n';
    final prefixLength = latin1.encode(prefix).length;
    const targetStartModulo = chunkBytes - 4;
    final paddingLength =
        (targetStartModulo - (prefixLength % chunkBytes) + chunkBytes) %
            chunkBytes;
    final body =
        "$prefix${List<String>.filled(paddingLength, 'X').join()}"
        '$candidate\nendstream\nendobj\n';
    final xrefOffset = latin1.encode(body).length;
    final fixture =
        '${body}xref\n0 1\n0000000000 65535 f \n'
        'trailer\n<< /Size 1 >>\n'
        'startxref\n$xrefOffset\n%%EOF\n';
    final file = await _writeFixture(tempDir, 'boundary.pdf', fixture);

    final result = await const CloudAwardPdfStructureProbe(
      scanChunkBytes: chunkBytes,
      scanOverlapBytes: overlapBytes,
      headProbeBytes: 128,
      tailProbeBytes: 256,
      xrefProbeBytes: 256,
    ).inspect(
      file: file,
      exactCandidateNumbers: const <String>[candidate],
    );

    expect(result.rawVisibleCandidateNumbers, contains(candidate));
    expect(
      result.maxResidentScanWindowBytes,
      chunkBytes + overlapBytes,
    );
  });
}

Future<File> _writeFixture(
  Directory directory,
  String name,
  String content,
) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(latin1.encode(content), flush: true);
  return file;
}

String _classicFixture({
  String candidate = 'AB12345678',
  String trailerExtras = '',
}) {
  final body =
      '%PDF-1.7\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      '2 0 obj\n<< /Type /Pages /Count 77000 >>\nendobj\n'
      '3 0 obj\n<< /Length 10 /Filter /FlateDecode >>\n'
      'stream\n$candidate\nendstream\nendobj\n';
  final xrefOffset = latin1.encode(body).length;
  return '${body}xref\n0 4\n'
      '0000000000 65535 f \n'
      '0000000010 00000 n \n'
      '0000000050 00000 n \n'
      '0000000090 00000 n \n'
      'trailer\n<< /Size 4 /Root 1 0 R $trailerExtras >>\n'
      'startxref\n$xrefOffset\n%%EOF\n';
}

String _xrefStreamFixture() {
  const body =
      '%PDF-1.7\n'
      '1 0 obj\n<< /Type /Catalog >>\nendobj\n';
  final xrefOffset = latin1.encode(body).length;
  return '${body}5 0 obj\n'
      '<< /Type /XRef /Length 0 /W [1 4 2] /Size 6 /Filter /FlateDecode >>\n'
      'stream\n\nendstream\nendobj\n'
      'startxref\n$xrefOffset\n%%EOF\n';
}
