// C500-G0l: synthetic XRef-only cases. No synthetic PDF is official evidence.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';
import '../../../tool/c500_g0_bounded_xref.dart';

Future<File> makeSyntheticXref(
  Directory directory, {
  String filter = '/FlateDecode',
  String widths = '[1 2 1]',
}) async {
  // Two entries: object 0 free, object 1 uncompressed at offset 10.
  final compressed = zlib.encode(<int>[0, 0, 0, 0, 1, 0, 10, 0]);
  const prefix = '%PDF-1.5\n';
  final dictionary = '1 0 obj\n<< /Type /XRef /Size 2 /W ' +
      widths +
      ' /Index [0 2] /Length ' +
      compressed.length.toString() +
      ' /Filter ' +
      filter +
      ' >>\nstream\n';
  final suffix = '\nendstream\nendobj\nstartxref\n' +
      latin1.encode(prefix).length.toString() +
      '\n%%EOF\n';
  final file = File.fromUri(directory.uri.resolve('synthetic.pdf'));
  await file.writeAsBytes(<int>[
    ...latin1.encode(prefix),
    ...latin1.encode(dictionary),
    ...compressed,
    ...latin1.encode(suffix),
  ], flush: true);
  return file;
}

Future<Map<String, Object?>> inspectSynthetic(
  File file, {
  C500G0BoundedXrefInspector inspector = const C500G0BoundedXrefInspector(),
  String? overrideSha,
}) async {
  final source = await const CloudAwardPdfStructureProbe().inspect(file: file);
  return inspector.inspect(
    file: file,
    expectedBytes: source.byteLength,
    expectedSha256: overrideSha ?? source.sha256,
  );
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('c500_g0l_synthetic_');
  });
  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('bounded XRef decodes only two entries, never grants authority', () async {
    final file = await makeSyntheticXref(directory);
    final result = await inspectSynthetic(file);
    expect(result['xref_entries'], 2);
    expect(result['free_entries'], 1);
    expect(result['uncompressed_entries'], 1);
    expect(result['object_stream_entries'], 0);
    expect(result['global_not_win'], 'NOT_PROVEN');
    expect(result['award_authority'], 'HOLD');
  });

  test('wrong source SHA is rejected before stream access', () async {
    final file = await makeSyntheticXref(directory);
    await expectLater(
      inspectSynthetic(file, overrideSha: 'wrong-sha'),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (error) => error.code,
        'code',
        'C500_G0L_SOURCE_PIN_MISMATCH',
      )),
    );
  });

  test('compressed stream above bound fails before allocation', () async {
    final file = await makeSyntheticXref(directory);
    await expectLater(
      inspectSynthetic(
        file,
        inspector: const C500G0BoundedXrefInspector(maxCompressedBytes: 1),
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (error) => error.code,
        'code',
        'C500_G0L_COMPRESSED_LIMIT',
      )),
    );
  });

  test('decoded XRef entry budget is enforced before inflate', () async {
    final file = await makeSyntheticXref(directory);
    await expectLater(
      inspectSynthetic(
        file,
        inspector: const C500G0BoundedXrefInspector(maxDecodedBytes: 4),
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (error) => error.code,
        'code',
        'C500_G0L_DECODED_LIMIT',
      )),
    );
  });

  test('unsupported filter fails closed', () async {
    final file = await makeSyntheticXref(directory, filter: '/ASCII85Decode');
    await expectLater(
      inspectSynthetic(file),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (error) => error.code,
        'code',
        'C500_G0L_UNSUPPORTED_FILTER',
      )),
    );
  });

  test('declared width inconsistent with decoded bytes fails closed', () async {
    final file = await makeSyntheticXref(directory, widths: '[1 2 2]');
    await expectLater(
      inspectSynthetic(file),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (error) => error.code,
        'code',
        'C500_G0L_DECODED_LENGTH_MISMATCH',
      )),
    );
  });
}
