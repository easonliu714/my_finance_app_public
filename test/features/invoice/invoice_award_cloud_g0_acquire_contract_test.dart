// C500-G0a: synthetic acquisition regressions. No official binary is
// substituted, and these tests do not assert an Android parser/OOM result.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../tool/c500_g0_acquire.dart';

void main() {
  late Directory scratch;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('c500_g0_acquire_test_');
  });
  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test('official fixed periods, URLs, and archived 07-08 pins are stable', () {
    expect(c500G0Sources, hasLength(2));
    expect(c500G0Sources.first.period, '115-05-06');
    expect(c500G0Sources.first.expectedBytes, 119769589);
    expect(c500G0Sources.first.expectedSha256, isNull);
    expect(c500G0Sources.last.period, '115-07-08');
    expect(c500G0Sources.last.expectedBytes, 135200798);
    expect(c500G0Sources.last.expectedSha256,
        'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571');
    for (final source in c500G0Sources) {
      expect(source.reference.isApprovedOfficialSource, isTrue);
      expect(source.reference.tierCode, 'cloud-500');
      expect(source.artifactId, endsWith('_sorted_AI_D.pdf'));
    }
  });

  test('bounded synthetic stream reuses downloader and structure probe',
      () async {
    final bytes = _syntheticPdf();
    final source = C500G0Source(
      period: '115-05-06',
      uriText: c500G0Sources.first.uriText,
      expectedBytes: bytes.length,
    );
    final client = _SyntheticClient(bytes);
    final result = await acquireC500G0Source(
      source: source, labDirectory: scratch, client: client,
    );
    expect(client.requests, 1);
    expect(result['bytes'], bytes.length);
    expect(result['pdf_version'], '1.7');
    expect(result['xref_type'], 'classicTable');
    expect(result['sha_pin'], 'PENDING_INDEPENDENT_OLD_BINARY_PIN');
    expect(result['pdfbox_pdfium_pdfrenderer'], 'NOT_RUN');
    expect(result['global_negative_proof'], 'NOT_RUN');
    expect(result['award_authority'], 'HOLD');
    expect(await File(result['lab_file'] as String).readAsBytes(), bytes);
  });

  test('size mismatch removes partial and never creates final lab file',
      () async {
    final bytes = _syntheticPdf();
    final source = C500G0Source(
      period: '115-05-06',
      uriText: c500G0Sources.first.uriText,
      expectedBytes: bytes.length + 1,
    );
    await expectLater(
      acquireC500G0Source(
        source: source, labDirectory: scratch,
        client: _SyntheticClient(bytes),
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message, 'code', 'G0_SOURCE_BYTES_MISMATCH',
      )),
    );
    expect(await scratch.list().toList(), isEmpty);
  });

  test('wrong archived SHA is rejected without retaining a PDF', () async {
    final bytes = _syntheticPdf();
    final source = C500G0Source(
      period: '115-07-08',
      uriText: c500G0Sources.last.uriText,
      expectedBytes: bytes.length,
      expectedSha256: List<String>.filled(64, '0').join(),
    );
    await expectLater(
      acquireC500G0Source(
        source: source, labDirectory: scratch,
        client: _SyntheticClient(bytes),
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message, 'code', 'G0_SOURCE_SHA256_MISMATCH',
      )),
    );
    expect(await scratch.list().toList(), isEmpty);
  });

  test('HTTP redirect is not an official binary and leaves no file',
      () async {
    final bytes = _syntheticPdf();
    final source = C500G0Source(
      period: '115-05-06',
      uriText: c500G0Sources.first.uriText,
      expectedBytes: bytes.length,
    );
    await expectLater(
      acquireC500G0Source(
        source: source, labDirectory: scratch,
        client: _SyntheticClient(bytes, statusCode: HttpStatus.found),
      ),
      throwsA(isA<HttpException>()),
    );
    expect(await scratch.list().toList(), isEmpty);
  });
}

List<int> _syntheticPdf() {
  const body = '%PDF-1.7\n1 0 obj\n<< /Type /Pages /Count 2 >>\nendobj\n';
  final xrefOffset = latin1.encode(body).length;
  final text = StringBuffer(body)
    ..write('xref\n0 1\n0000000000 65535 f \n')
    ..write('trailer\n<< /Size 1 >>\nstartxref\n')
    ..write(xrefOffset)
    ..write('\n%%EOF\n');
  return latin1.encode(text.toString());
}

class _SyntheticClient extends http.BaseClient {
  _SyntheticClient(this.bytes, {this.statusCode = HttpStatus.ok});

  final List<int> bytes;
  final int statusCode;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests += 1;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[
        bytes.sublist(0, 5), bytes.sublist(5),
      ]),
      statusCode,
      headers: const <String, String>{'content-type': 'application/pdf'},
      contentLength: bytes.length,
      request: request,
    );
  }
}
