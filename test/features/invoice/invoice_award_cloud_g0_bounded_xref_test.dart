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
  bool wrongMemberId = false,
  bool badFirst = false,
  bool badFilter = false,
  bool oversizedLength = false,
  bool outOfBoundsMemberOffset = false,
}) async {
  const prefix = '%PDF-1.5\n';
  final compressedObject = zlib.encode(latin1.encode(
    '${wrongMemberId ? 9 : 1} ${outOfBoundsMemberOffset ? 999999 : 0} '
    '<< /Type /Catalog >>',
  ));
  final objOffset = latin1.encode(prefix).length;
  final objHead = latin1.encode(
    '2 0 obj\n<< /Type /ObjStm /N 1 /First ${badFirst ? 5 : outOfBoundsMemberOffset ? 9 : 4} '
    '/Length ${oversizedLength ? 2097153 : compressedObject.length} '
    '/Filter ${badFilter ? '/ASCII85Decode' : '/FlateDecode'} >>\nstream\n',
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
    '3 0 obj\n<< /Type /XRef /Size 4 /W [1 4 2] /Index [0 4] '
    '/Length ${xref.length} /Filter /FlateDecode >>\nstream\n',
  );
  final file = File.fromUri(directory.uri.resolve('navigable.pdf'));
  await file.writeAsBytes(<int>[
    ...latin1.encode(prefix), ...objHead, ...compressedObject, ...objTail,
    ...xrefHead, ...xref,
    ...latin1.encode('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n'),
  ], flush: true);
  return file;
}


// G0p: hermetic Catalog -> Pages-root fixture; no complete page evidence.
Future<File> makeCatalogSynthetic(
  Directory directory, {
  bool missingRoot = false,
  bool forgedRoot = false,
  bool wrongCatalogType = false,
  bool missingPages = false,
  bool forgedPages = false,
  bool wrongPagesType = false,
  bool zeroPageCount = false,
  bool includeFirstChild = false,
  bool wrongFirstChildParent = false,
  bool nestedFirstChild = false,
  bool wrongNestedParent = false,
  bool nestedCycle = false,
  bool nestedExcessCount = false,
  bool includePageContent = false,
  bool badContentFilter = false,
  bool badContentLength = false,
  bool forgedContentReference = false,
}) async {
  if (includePageContent && (!includeFirstChild || nestedFirstChild)) {
    throw StateError('G0V_FIXTURE_REQUIRES_DIRECT_LEAF');
  }
  const prefix = '%PDF-1.5\n';
  final catalog = '<< /Type /${wrongCatalogType ? 'Page' : 'Catalog'} '
      '${missingPages ? '' : '/Pages ${forgedPages ? 9 : 3} 0 R'} >>';
  final member = zlib.encode(latin1.encode('1 0 $catalog'));
  final obj2Offset = latin1.encode(prefix).length;
  final obj2 = latin1.encode(
    '2 0 obj\n<< /Type /ObjStm /N 1 /First 4 '
    '/Length ${member.length} /Filter /FlateDecode >>\nstream\n',
  );
  final obj2Tail = latin1.encode('\nendstream\nendobj\n');
  final obj3Offset = obj2Offset + obj2.length + member.length + obj2Tail.length;
  final obj3 = latin1.encode(
    '3 0 obj\n<< /Type /${wrongPagesType ? 'Page' : 'Pages'} '
    '/Count ${zeroPageCount ? 0 : 1} /Kids [5 0 R] >>\nendobj\n',
  );
  final obj5Offset = obj3Offset + obj3.length;
  final obj5 = includeFirstChild
      ? latin1.encode('5 0 obj\n<< /Type /${nestedFirstChild ? 'Pages' : 'Page'} /Parent '
          '${wrongFirstChildParent ? 9 : 3} 0 R '
          '${nestedFirstChild ? '/Count ${nestedExcessCount ? 2 : 1} /Kids [${nestedCycle ? 3 : 6} 0 R]' : ''}'
          '${includePageContent ? '/Contents ${forgedContentReference ? 9 : 7} 0 R' : ''} >>\nendobj\n')
      : <int>[];
  final obj6Offset = obj5Offset + obj5.length;
  final obj6 = nestedFirstChild
      ? latin1.encode('6 0 obj\n<< /Type /Page /Parent '
          '${wrongNestedParent ? 9 : 5} 0 R >>\nendobj\n')
      : <int>[];
  final contentCompressed = zlib.encode(latin1.encode('BT /F1 12 Tf (TEST) Tj ET'));
  final obj7Offset = obj6Offset + obj6.length;
  final obj7 = includePageContent ? <int>[
    ...latin1.encode('7 0 obj\n<< /Length ${badContentLength ? 2097153 : contentCompressed.length} '
        '/Filter ${badContentFilter ? '/ASCII85Decode' : '/FlateDecode'} >>\nstream\n'),
    ...contentCompressed,
    ...latin1.encode('\nendstream\nendobj\n'),
  ] : <int>[];
  final xrefOffset = obj7Offset + obj7.length;
  List<int> four(int n) => <int>[
    (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255,
  ];
  final xref = zlib.encode(<int>[
    0, ...four(0), 0, 0,
    2, ...four(2), 0, 0,
    1, ...four(obj2Offset), 0, 0,
    1, ...four(obj3Offset), 0, 0,
    1, ...four(xrefOffset), 0, 0,
    if (includeFirstChild) ...<int>[1, ...four(obj5Offset), 0, 0],
    if (nestedFirstChild) ...<int>[1, ...four(obj6Offset), 0, 0],
    if (includePageContent) ...<int>[
      0, ...four(0), 0, 0,
      1, ...four(obj7Offset), 0, 0,
    ],
  ]);
  final xrefHead = latin1.encode(
    '4 0 obj\n<< /Type /XRef /Size ${includePageContent ? 8 : nestedFirstChild ? 7 : includeFirstChild ? 6 : 5} '
    '/W [1 4 2] /Index [0 ${includePageContent ? 8 : nestedFirstChild ? 7 : includeFirstChild ? 6 : 5}] '
    '${missingRoot ? '' : '/Root ${forgedRoot ? 9 : 1} 0 R'} '
    '/Length ${xref.length} /Filter /FlateDecode >>\nstream\n',
  );
  final file = File.fromUri(directory.uri.resolve('catalog.pdf'));
  await file.writeAsBytes(<int>[
    ...latin1.encode(prefix), ...obj2, ...member, ...obj2Tail,
    ...obj3, ...obj5, ...obj6, ...obj7, ...xrefHead, ...xref,
    ...latin1.encode('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n'),
  ], flush: true);
  return file;
}


/* G0r synthetic-only: a 2.3 MiB incompressible second member forces
   /Length > 2 MiB while the Catalog remains a tiny first member. */
Future<File> makeLargeRootSynthetic(Directory directory, {
  bool corruptTrailer = false,
  int decodedPaddingBytes = 0,
}) async {
  const prefix = '%PDF-1.5\n';
  final catalog = latin1.encode('<< /Type /Catalog /Pages 3 0 R >>');
  final random = List<int>.filled(2300000, 0);
  var state = 0x12345678;
  for (var i = 0; i < random.length; i++) {
    state ^= (state << 13) & 0xffffffff;
    state ^= state >> 17;
    state ^= (state << 5) & 0xffffffff;
    random[i] = state & 255;
  }
  final indexHeader = latin1.encode('1 0 5 ${catalog.length} ');
  final compressed = zlib.encode(<int>[
    ...indexHeader, ...catalog, ...random,
    ...List<int>.filled(decodedPaddingBytes, 0),
  ]);
  if (compressed.length <= 2 * 1024 * 1024) {
    throw StateError('G0R_FIXTURE_NOT_LARGE_ENOUGH');
  }
  if (corruptTrailer) compressed[compressed.length - 1] ^= 1;
  final objOffset = latin1.encode(prefix).length;
  final objHead = latin1.encode('2 0 obj\n<< /Type /ObjStm /N 2 '
      '/First ${indexHeader.length} /Length ${compressed.length} '
      '/Filter /FlateDecode >>\nstream\n');
  final objTail = latin1.encode('\nendstream\nendobj\n');
  final pagesOffset = objOffset + objHead.length + compressed.length + objTail.length;
  const pages = '3 0 obj\n<< /Type /Pages /Count 1 /Kids [6 0 R] >>\nendobj\n';
  final xrefOffset = pagesOffset + latin1.encode(pages).length;
  List<int> four(int n) => <int>[
    (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255,
  ];
  final xref = zlib.encode(<int>[
    0, ...four(0), 0, 0,
    2, ...four(2), 0, 0,
    1, ...four(objOffset), 0, 0,
    1, ...four(pagesOffset), 0, 0,
    1, ...four(xrefOffset), 0, 0,
    2, ...four(2), 0, 1,
  ]);
  final xrefHead = latin1.encode('4 0 obj\n<< /Type /XRef /Size 6 '
      '/W [1 4 2] /Index [0 6] /Root 1 0 R '
      '/Length ${xref.length} /Filter /FlateDecode >>\nstream\n');
  final file = File.fromUri(directory.uri.resolve('large-root.pdf'));
  await file.writeAsBytes(<int>[
    ...latin1.encode(prefix), ...objHead, ...compressed, ...objTail,
    ...latin1.encode(pages), ...xrefHead, ...xref,
    ...latin1.encode('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n'),
  ], flush: true);
  return file;
}

Future<Map<String, Object?>> inspectSynthetic(
  File file, {
  C500G0BoundedXrefInspector inspector = const C500G0BoundedXrefInspector(),
  String? overrideSha,
  bool verifyObjectOffsets = false,
  bool verifyCompressedMembers = false,
  bool verifyCatalogRoot = false,
  bool verifyFirstPageChild = false,
  bool verifyFirstPagePath = false,
  bool verifyFirstPageContents = false,
}) async {
  final source = await const CloudAwardPdfStructureProbe().inspect(file: file);
  return inspector.inspect(
    file: file,
    expectedBytes: source.byteLength,
    expectedSha256: overrideSha ?? source.sha256,
    verifyObjectOffsets: verifyObjectOffsets,
    verifyCompressedMembers: verifyCompressedMembers,
    verifyCatalogRoot: verifyCatalogRoot,
    verifyFirstPageChild: verifyFirstPageChild,
    verifyFirstPagePath: verifyFirstPagePath,
    verifyFirstPageContents: verifyFirstPageContents,
  );
}

void main() {
  late Directory directory;

  test('G0r streams >2 MiB root ObjStm with bounded memory', () async {
    final file = await makeLargeRootSynthetic(directory);
    final result = await inspectSynthetic(file, verifyCatalogRoot: true);
    expect(result['catalog_root_verified'], isTrue);
    expect(result['pages_root_verified'], isTrue);
    expect(result['global_not_win'], 'NOT_PROVEN');
    expect(result['award_authority'], 'HOLD');
  });

  test('G0r corrupted large zlib trailer fails closed', () async {
    final file = await makeLargeRootSynthetic(directory, corruptTrailer: true);
    await expectLater(
      inspectSynthetic(file, verifyCatalogRoot: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0R_STREAM_DECODE_FAILED',
      )),
    );
  });

  // G0s synthetic >64 MiB regression: verify selective streaming without
  // spooling all decoded bytes; never claim official page-tree coverage.
  test('G0s extracts selected root across old 64 MiB spool ceiling', () async {
    final file = await makeLargeRootSynthetic(
      directory, decodedPaddingBytes: 65 * 1024 * 1024,
    );
    final result = await inspectSynthetic(file, verifyCatalogRoot: true);
    expect(result['catalog_root_verified'], true);
    expect(result['pages_root_verified'], true);
    expect(result['global_not_win'], 'NOT_PROVEN');
  });

  test('G0s total decoded budget rejects before unbounded expansion', () async {
    final file = await makeLargeRootSynthetic(directory);
    await expectLater(
      inspectSynthetic(file,
        inspector: const C500G0BoundedXrefInspector(
          maxRootDecodedBytes: 2 * 1024 * 1024,
        ),
        verifyCatalogRoot: true,
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0S_TOTAL_DECODED_LIMIT',
      )),
    );
  });

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


  // G0o synthetic contracts are not official PDF or global negative proof.
  test('G0o verifies bounded ObjStm member identity', () async {
    final file = await makeNavigableSynthetic(directory);
    final result = await inspectSynthetic(file,
        verifyObjectOffsets: true, verifyCompressedMembers: true);
    expect(result['compressed_members_verified'], greaterThan(0));
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('G0o requires parent-offset verification', () async {
    final file = await makeNavigableSynthetic(directory);
    await expectLater(
      inspectSynthetic(file, verifyCompressedMembers: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0O_REQUIRES_OFFSET_VERIFICATION',
      )),
    );
  });
  test('G0o rejects forged ObjStm member id', () async {
    final file = await makeNavigableSynthetic(directory, wrongMemberId: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true,
          verifyCompressedMembers: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0O_MEMBER_ID_MISMATCH',
      )),
    );
  });
  test('G0o rejects invalid First index boundary', () async {
    final file = await makeNavigableSynthetic(directory, badFirst: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true,
          verifyCompressedMembers: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0O_INDEX_HEADER_INVALID',
      )),
    );
  });
  test('G0o rejects unsupported ObjStm filter', () async {
    final file = await makeNavigableSynthetic(directory, badFilter: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true,
          verifyCompressedMembers: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0O_UNSUPPORTED_STREAM',
      )),
    );
  });


  test('G0o oversized ObjStm declared Length fails before read', () async {
    final file = await makeNavigableSynthetic(directory, oversizedLength: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true,
          verifyCompressedMembers: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0O_COMPRESSED_LIMIT',
      )),
    );
  });
  test('G0o out-of-bounds ObjStm member offset fails closed', () async {
    final file = await makeNavigableSynthetic(
        directory, outOfBoundsMemberOffset: true);
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true,
          verifyCompressedMembers: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0O_MEMBER_OFFSET_INVALID',
      )),
    );
  });


  // G0p tests are synthetic; page traversal and NOT_WIN remain unproven.
  test('G0p verifies bounded Catalog and Pages root only', () async {
    final file = await makeCatalogSynthetic(directory);
    final result = await inspectSynthetic(file,
        verifyObjectOffsets: true, verifyCompressedMembers: true,
        verifyCatalogRoot: true);
    expect(result['catalog_root_verified'], true);
    expect(result['pages_root_verified'], true);
    expect(result['declared_page_count_unverified'], 1);
    expect(result['page_tree'], 'ROOT_ONLY_NOT_TRAVERSED');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  Future<void> rejectsCatalog(
      String expected, Future<File> Function() make) async {
    final file = await make();
    await expectLater(
      inspectSynthetic(file, verifyObjectOffsets: true,
          verifyCompressedMembers: true, verifyCatalogRoot: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', expected,
      )),
    );
  }
  test('G0p missing Root reference fails closed', () async {
    await rejectsCatalog('C500_G0P_ROOT_REFERENCE_MISSING',
        () => makeCatalogSynthetic(directory, missingRoot: true));
  });
  test('G0p forged Root XRef reference fails closed', () async {
    await rejectsCatalog('C500_G0P_ROOT_XREF_MISSING',
        () => makeCatalogSynthetic(directory, forgedRoot: true));
  });
  test('G0p Catalog type mismatch fails closed', () async {
    await rejectsCatalog('C500_G0P_CATALOG_TYPE_INVALID',
        () => makeCatalogSynthetic(directory, wrongCatalogType: true));
  });
  test('G0p missing Pages reference fails closed', () async {
    await rejectsCatalog('C500_G0P_PAGES_REFERENCE_MISSING',
        () => makeCatalogSynthetic(directory, missingPages: true));
  });
  test('G0p forged Pages reference fails closed', () async {
    await rejectsCatalog('C500_G0P_ROOT_XREF_MISSING',
        () => makeCatalogSynthetic(directory, forgedPages: true));
  });
  test('G0p wrong Pages root type fails closed', () async {
    await rejectsCatalog('C500_G0P_PAGES_TYPE_INVALID',
        () => makeCatalogSynthetic(directory, wrongPagesType: true));
  });
  test('G0p zero declared page count fails closed', () async {
    await rejectsCatalog('C500_G0P_PAGE_COUNT_INVALID',
        () => makeCatalogSynthetic(directory, zeroPageCount: true));
  });
  // G0q: root-only mode is independently bounded; unrelated sampled parents
  // must not be touched before the authoritative Root/Pages path is examined.
  test('G0q verifies Catalog/Pages without unrelated ObjStm samples', () async {
    final file = await makeCatalogSynthetic(directory);
    final result = await inspectSynthetic(file, verifyCatalogRoot: true);
    expect(result['catalog_root_verified'], true);
    expect(result['pages_root_verified'], true);
    expect(result.containsKey('compressed_members_verified'), false);
    expect(result['page_tree'], 'ROOT_ONLY_NOT_TRAVERSED');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('G0q root-only mode still rejects a forged Root reference', () async {
    final file = await makeCatalogSynthetic(directory, forgedRoot: true);
    await expectLater(
      inspectSynthetic(file, verifyCatalogRoot: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0P_ROOT_XREF_MISSING',
      )),
    );
  });


  // G0t synthetic-only positive/negative first-child contracts.
  test('G0t first root child and parent verified, no global proof', () async {
    final file = await makeCatalogSynthetic(directory, includeFirstChild: true);
    final result = await inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true);
    expect(result['first_root_child_id'], 5);
    expect(result['first_root_child_verified'], true);
    expect(result['page_tree'], 'FIRST_CHILD_ONLY_NOT_TRAVERSED');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('G0t missing child XRef fails closed', () async {
    final file = await makeCatalogSynthetic(directory);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0T_CHILD_XREF_MISSING')));
  });
  test('G0t forged child parent fails closed', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, wrongFirstChildParent: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0T_PARENT_MISMATCH')));
  });
  test('G0t requires root verification', () async {
    final file = await makeCatalogSynthetic(directory, includeFirstChild: true);
    await expectLater(inspectSynthetic(file, verifyFirstPageChild: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0T_REQUIRES_ROOT')));
  });


  // G0u lab-only: a bounded leftmost path does not validate any siblings.
  test('G0u nested leftmost path reaches a Page leaf, not global proof', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, nestedFirstChild: true);
    final result = await inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true);
    expect(result['leftmost_page_id'], 6);
    expect(result['leftmost_path_depth'], 2);
    expect(result['leftmost_path_verified'], true);
    expect(result['page_tree'], 'LEFTMOST_PATH_ONLY_NOT_TRAVERSED');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('G0u nested forged Parent fails closed', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, nestedFirstChild: true,
        wrongNestedParent: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0U_PARENT_MISMATCH')));
  });
  test('G0u nested cycle fails closed', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, nestedFirstChild: true,
        nestedCycle: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0U_CHILD_CYCLE')));
  });
  test('G0u subtree Count larger than parent fails closed', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, nestedFirstChild: true,
        nestedExcessCount: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0U_SUBTREE_COUNT_INVALID')));
  });
  test('G0u path requires first-child verification', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPagePath: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0U_REQUIRES_FIRST_CHILD')));
  });


  // G0v is one leaf stream, not text parsing or all-page coverage.
  test('G0v decodes bounded first-leaf stream without award authority', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true);
    final result = await inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true, verifyFirstPageContents: true);
    expect(result['leftmost_content_object_id'], 7);
    expect(result['leftmost_content_stream_verified'], true);
    expect(result['content_semantics'], 'UNPARSED_ONE_PAGE_ONLY');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('G0v missing content reference fails closed', () async {
    final file = await makeCatalogSynthetic(directory, includeFirstChild: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true, verifyFirstPageContents: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0V_CONTENT_REFERENCE_MISSING')));
  });
  test('G0v forged content XRef fails closed', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true,
        forgedContentReference: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true, verifyFirstPageContents: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0V_CONTENT_XREF_INVALID')));
  });
  test('G0v oversized stream fails before allocation', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true,
        badContentLength: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true, verifyFirstPageContents: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0V_CONTENT_LENGTH_LIMIT')));
  });
  test('G0v unsupported content filter fails closed', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true,
        badContentFilter: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPagePath: true, verifyFirstPageContents: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0V_CONTENT_FILTER_UNSUPPORTED')));
  });
  test('G0v requires verified leftmost leaf', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true);
    await expectLater(inspectSynthetic(file,
        verifyCatalogRoot: true, verifyFirstPageChild: true,
        verifyFirstPageContents: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0V_REQUIRES_LEAF_PATH')));
  });

}
