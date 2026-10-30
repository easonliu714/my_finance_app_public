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
  int headerPaddingBytes = 0,
  String streamSeparator = '\n',
}) async {
  // Two entries: object 0 free, object 1 uncompressed at offset 10.
  final compressed = zlib.encode(<int>[0, 0, 0, 0, 1, 0, 10, 0]);
  const prefix = '%PDF-1.5\n';
  // G0m: long synthetic dictionaries and EOL variants test bounded access;
  // synthetic PDFs are not official source or global page evidence.
  final headerPadding = List<String>.filled(headerPaddingBytes, ' ').join();
  final dictionary =
      '1 0 obj\n<< /Type /XRef /Size 2 /W $widths /Index [0 2] '
      '/Length ${compressed.length} /Filter $filter$headerPadding '
      '>>${streamSeparator}stream\n';
  final suffix =
      '\nendstream\nendobj\nstartxref\n${latin1.encode(prefix).length}\n%%EOF\n';
  final file = File.fromUri(directory.uri.resolve('synthetic.pdf'));
  await file.writeAsBytes(<int>[
    ...latin1.encode(prefix),
    ...latin1.encode(dictionary),
    ...compressed,
    ...latin1.encode(suffix),
  ], flush: true);
  return file;
}


// G0n: hermetic PDF object addresses, never official evidence.
Future<File> makeNavigableSynthetic(
  Directory directory, {
  bool forgedOffset = false,
  bool wrongParent = false,
  bool invalidIndex = false,
}) async {
  const prefix = '%PDF-1.5\n';
  final compressedObject = zlib.encode(latin1.encode('1 0 << /Type /Catalog >>'));
  final objOffset = latin1.encode(prefix).length;
  final objHead = latin1.encode(
    '2 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Length ' +
    compressedObject.length.toString() + ' /Filter /FlateDecode >>\nstream\n',
  );
  final objTail = latin1.encode('\nendstream\nendobj\n');
  final xrefOffset = objOffset + objHead.length +
      compressedObject.length + objTail.length;
  List<int> four(int n) => <int>[
    (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255,
  ];
  final xref = zlib.encode(<int>[
    0, ...four(0), 0, 0,
    2, ...four(wrongParent ? 3 : 2), 0, invalidIndex ? 1 : 0,
    1, ...four(objOffset + (forgedOffset ? 1 : 0)), 0, 0,
    1, ...four(xrefOffset), 0, 0,
  ]);
  final xrefHead = latin1.encode(
    '3 0 obj\n<< /Type /XRef /Size 4 /W [1 4 2] /Index [0 4] /Length ' +
    xref.length.toString() + ' /Filter /FlateDecode >>\nstream\n',
  );
  final file = File.fromUri(directory.uri.resolve('navigable.pdf'));
  await file.writeAsBytes(<int>[
    ...latin1.encode(prefix), ...objHead, ...compressedObject, ...objTail,
    ...xrefHead, ...xref,
    ...latin1.encode('\nendstream\nendobj\nstartxref\n' +
        xrefOffset.toString() + '\n%%EOF\n'),
  ], flush: true);
  return file;
}

Future<Map<String, Object?>> inspectSynthetic(
  File file, {
  C500G0BoundedXrefInspector inspector = const C500G0BoundedXrefInspector(),
  String? overrideSha,
  bool verifyObjectOffsets = false,
}) async {
  final source = await const CloudAwardPdfStructureProbe().inspect(file: file);
  return inspector.inspect(
    file: file,
    expectedBytes: source.byteLength,
    expectedSha256: overrideSha ?? source.sha256,
    verifyObjectOffsets: verifyObjectOffsets,
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
  test('bounded long XRef dictionary does not require whole-document load', () async {
    final file = await makeSyntheticXref(directory, headerPaddingBytes: 70 * 1024);
    final result = await inspectSynthetic(file);
    expect(result['xref_entries'], 2);
    expect(result['global_not_win'], 'NOT_PROVEN');
  });

  test('XRef dictionary immediately followed by stream is accepted', () async {
    final file = await makeSyntheticXref(directory, streamSeparator: '');
    final result = await inspectSynthetic(file);
    expect(result['xref_entries'], 2);
    expect(result['award_authority'], 'HOLD');
  });

  test('insufficient header budget fails closed before stream access', () async {
    final file = await makeSyntheticXref(directory, headerPaddingBytes: 4096);
    await expectLater(
      inspectSynthetic(
        file,
        inspector: const C500G0BoundedXrefInspector(maxHeaderBytes: 256),
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (error) => error.code,
        'code',
        'C500_G0L_STREAM_HEADER_MISSING',
      )),
    );
  });

  test('G0n validates sampled direct and ObjStm parent headers', () async {
    final file = await makeNavigableSynthetic(directory);
    final result = await inspectSynthetic(file, verifyObjectOffsets: true);
    expect(result['direct_headers_verified'], greaterThan(0));
    expect(result['objstm_parent_headers_verified'], greaterThan(0));
    expect(result['page_tree'], 'NOT_TRAVERSED');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('G0n forged direct offset fails closed', () async {
    final file = await makeNavigableSynthetic(directory, forgedOffset: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0N_OBJECT_HEADER_MISMATCH',
      )),
    );
  });
  test('G0n non-ObjStm parent fails closed', () async {
    final file = await makeNavigableSynthetic(directory, wrongParent: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0N_PARENT_NOT_OBJSTM',
      )),
    );
  });
  test('G0n compressed index beyond N fails closed', () async {
    final file = await makeNavigableSynthetic(directory, invalidIndex: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0N_COMPRESSED_INDEX_INVALID',
      )),
    );
  });

}
