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
  bool verifyFirstPageFontResources = false,
  bool verifyFirstPageCmapStreams = false,
  bool verifyFirstPageCmapSemantics = false,
  bool verifyFirstPageGlyphUnicode = false,
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
    verifyFirstPageFontResources: verifyFirstPageFontResources,
    verifyFirstPageCmapStreams: verifyFirstPageCmapStreams,
    verifyFirstPageCmapSemantics: verifyFirstPageCmapSemantics,
    verifyFirstPageGlyphUnicode: verifyFirstPageGlyphUnicode,
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


  // G0aa: synthetic resource/XRef binding is not a real CMap or award proof.
  test('G0aa binds selected inherited fonts through bounded object reader', () async {
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Type /Pages /Resources << /Font << /F1 11 0 R /F2 12 0 R >> >> >>',
        '<< /Type /Page /Parent 3 0 R >>',
      ],
      selectedFontNames: <String>['F1', 'F2'],
      readObject: (id, generation) async {
        if (generation != 0) throw StateError('unexpected generation');
        if (id == 11) return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
        if (id == 12) return '12 0 obj << /Type /Font >> endobj';
        throw const C500G0BoundedXrefException('C500_G0P_ROOT_XREF_MISSING');
      },
    );
    expect(result['first_page_font_objects_verified'], 2);
    expect(result['first_page_tounicode_references_unverified'], 1);
    expect(result['first_page_font_cmap'], 'NOT_VERIFIED');
    expect(result['first_page_text_authority'], 'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0aa nearest leaf Resources overrides inherited mapping', () async {
    final readIds = <int>[];
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Resources << /Font << /F1 11 0 R >> >> >>',
        '<< /Resources << /Font << /F1 12 0 R >> >> >>',
      ],
      selectedFontNames: <String>['F1'],
      readObject: (id, generation) async {
        readIds.add(id);
        return '$id $generation obj << /Type /Font >> endobj';
      },
    );
    expect(readIds, <int>[12]);
    expect(result['first_page_font_objects_verified'], 1);
  });

  test('G0aa unbound selected font fails closed', () async {
    await expectLater(
      const C500G0FontResourceInspector().inspect(
        pageTreeObjects: <String>[
          '<< /Resources << /Font << /F2 12 0 R >> >> >>',
        ],
        selectedFontNames: <String>['F1'],
        readObject: (id, generation) async => '<< /Type /Font >>',
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AA_SELECTED_FONT_UNBOUND',
      )),
    );
  });

  test('G0aa forged font XRef is not swallowed', () async {
    await expectLater(
      const C500G0FontResourceInspector().inspect(
        pageTreeObjects: <String>[
          '<< /Resources << /Font << /F1 99 0 R >> >> >>',
        ],
        selectedFontNames: <String>['F1'],
        readObject: (id, generation) async =>
            throw const C500G0BoundedXrefException('C500_G0P_ROOT_XREF_MISSING'),
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0P_ROOT_XREF_MISSING',
      )),
    );
  });

  test('G0aa unsupported ToUnicode form fails closed', () async {
    await expectLater(
      const C500G0FontResourceInspector().inspect(
        pageTreeObjects: <String>[
          '<< /Resources << /Font << /F1 11 0 R >> >> >>',
        ],
        selectedFontNames: <String>['F1'],
        readObject: (id, generation) async =>
            '11 0 obj << /Type /Font /ToUnicode << /Fake true >> >> endobj',
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AA_CMAP_REFERENCE_INVALID',
      )),
    );
  });

  test('G0aa requires first-leaf glyph evidence', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true);
    await expectLater(
      inspectSynthetic(file, verifyFirstPageFontResources: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AA_REQUIRES_GLYPH_STATE',
      )),
    );
  });


  // G0ab synthetic CMap streams are NOT official or Unicode mapping proof.
  String g0abCmapObject(int id, {
    bool compressed = false,
    bool badFilter = false,
    bool badMarkers = false,
    bool badLength = false,
    bool decodedBomb = false,
    String? cmapBody,
  }) {
    const valid = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    // G0ac: fail closed on highly compressible >256KiB decoded CMap.
    final content = decodedBomb
        ? '$valid${List<String>.filled(300000, 'X').join()}'
        : (badMarkers ? 'begincmap\nendcmap\n' : (cmapBody ?? valid));
    final payload = compressed
        ? zlib.encode(latin1.encode(content))
        : latin1.encode(content);
    final filter = badFilter
        ? ' /Filter /LZWDecode'
        : compressed ? ' /Filter /FlateDecode' : '';
    final length = badLength ? payload.length + 5 : payload.length;
    return '$id 0 obj\n<< /Length $length$filter >>\nstream\n'
        '${latin1.decode(payload)}\nendstream\nendobj';
  }

  test('G0ab selected CMap Flate stream lexical structure only', () async {
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Resources << /Font << /F1 11 0 R >> >> >>',
      ],
      selectedFontNames: <String>['F1'],
      verifyCmapStreams: true,
      readObject: (id, generation) async {
        if (generation != 0) throw StateError('generation');
        if (id == 11) return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
        if (id == 21) return g0abCmapObject(21, compressed: true);
        throw StateError('unexpected XRef id');
      },
    );
    expect(result['first_page_tounicode_streams_structure_verified'], 1);
    expect(result['first_page_tounicode_references_unverified'], 0);
    expect(result['first_page_font_cmap'],
        'BOUNDED_STREAM_LEXICAL_STRUCTURE_ONLY_NOT_MAPPING');
    expect(result['first_page_text_authority'],
        'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0ab uncompressed bounded CMap structure accepted', () {
    const C500G0CmapStreamProbe().verify(
      object: g0abCmapObject(21),
      id: 21,
      generation: 0,
    );
  });

  test('G0ac Flate CMap expansion beyond 256KiB fails closed', () {
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, compressed: true, decodedBomb: true),
        id: 21, generation: 0,
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AB_STREAM_DECODE_FAILED')),
    );
  });

  test('G0ab forged CMap object identity fails closed', () {
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(22), id: 21, generation: 0),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AB_OBJECT_IDENTITY_OR_BUDGET')),
    );
  });

  test('G0ab unsupported filter fails closed', () {
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, badFilter: true),
        id: 21, generation: 0),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AB_FILTER_UNSUPPORTED')),
    );
  });

  test('G0ab mismatched stream length fails closed', () {
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, badLength: true),
        id: 21, generation: 0),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AB_ENDSTREAM_MISMATCH')),
    );
  });

  test('G0ab missing CMap lexical sections fails closed', () {
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, badMarkers: true),
        id: 21, generation: 0),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AB_CMAP_LEXICAL_MARKERS_MISSING')),
    );
  });

  test('G0ab CMap stream requires selected font binding', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true);
    await expectLater(
      inspectSynthetic(file, verifyFirstPageCmapStreams: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AB_REQUIRES_FONT_BINDING')),
    );
  });


  // G0ae: selected-font XRef semantic-flag regression; never award authority.
  test('G0ae selected font CMap semantic flag counts bounded mappings', () async {
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Resources << /Font << /F1 11 0 R >> >> >>',
      ],
      selectedFontNames: <String>['F1'],
      verifyCmapStreams: true,
      verifyCmapSemantics: true,
      readObject: (id, generation) async {
        if (generation != 0) throw StateError('generation');
        if (id == 11) {
          return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
        }
        if (id == 21) return g0abCmapObject(21, compressed: true);
        throw StateError('unexpected XRef id');
      },
    );
    expect(result['first_page_tounicode_streams_structure_verified'], 1);
    expect(result['first_page_tounicode_mapping_codes_syntax_verified'], 1);
    expect(result['first_page_font_cmap'],
        'BOUNDED_CMAP_SYNTAX_ONLY_NOT_GLYPH_TEXT');
    expect(result['first_page_text_authority'],
        'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0ae selected font CMap semantic flag rejects forged UTF16', () async {
    const malformed = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <D800>\n'
        'endbfchar\nendcmap\n';
    await expectLater(
      const C500G0FontResourceInspector().inspect(
        pageTreeObjects: <String>[
          '<< /Resources << /Font << /F1 11 0 R >> >> >>',
        ],
        selectedFontNames: <String>['F1'],
        verifyCmapStreams: true,
        verifyCmapSemantics: true,
        readObject: (id, generation) async {
          if (generation != 0) throw StateError('generation');
          if (id == 11) {
            return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
          }
          if (id == 21) return g0abCmapObject(21, cmapBody: malformed);
          throw StateError('unexpected XRef id');
        },
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_UTF16_INVALID')),
    );
  });

  // G0ad validates mapping syntax only, not glyph-to-invoice authority.
  test('G0ad bfchar and bfrange sequential plus array syntax accepted', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\nendbfchar\n'
        '1 beginbfrange\n<40> <42> <0041>\nendbfrange\n'
        '1 beginbfrange\n<50> <51> [<0061> <0062>]\n'
        'endbfrange\nendcmap\n';
    final count = const C500G0CmapStreamProbe().verify(
      object: g0abCmapObject(21, cmapBody: cmap),
      id: 21, generation: 0, verifyMappings: true,
    );
    expect(count, 6);
  });

  test('G0ad malformed UTF16 surrogate fails closed', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <D800>\n'
        'endbfchar\nendcmap\n';
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, cmapBody: cmap),
        id: 21, generation: 0, verifyMappings: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_UTF16_INVALID')),
    );
  });

  test('G0ad duplicate mapping source fails closed', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n2 beginbfchar\n<31> <0031>\n'
        '<31> <0032>\nendbfchar\nendcmap\n';
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, cmapBody: cmap),
        id: 21, generation: 0, verifyMappings: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_DUPLICATE_OR_BUDGET')),
    );
  });

  test('G0ad out-of-codespace source fails closed', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <30>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, cmapBody: cmap),
        id: 21, generation: 0, verifyMappings: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_CODESPACE_INVALID')),
    );
  });

  test('G0ad unsupported usecmap fails closed', () {
    const cmap = 'begincmap\n/Other usecmap\n'
        '1 begincodespacerange\n<00> <FF>\nendcodespacerange\n'
        '1 beginbfchar\n<31> <0031>\nendbfchar\nendcmap\n';
    expect(
      () => const C500G0CmapStreamProbe().verify(
        object: g0abCmapObject(21, cmapBody: cmap),
        id: 21, generation: 0, verifyMappings: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_UNSUPPORTED_SEMANTICS')),
    );
  });

  // G0af: synthetic one-code lookup exercises actual ToUnicode output,
  // but never uses official PDF glyphs or asserts winning/NOT_WIN authority.
  test('G0af bounded bfchar and both bfrange forms decode one glyph', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\nendbfchar\n'
        '1 beginbfrange\n<40> <42> <0041>\nendbfrange\n'
        '1 beginbfrange\n<50> <51> [<0061> <0062>]\n'
        'endbfrange\nendcmap\n';
    const probe = C500G0CmapSemanticProbe();
    expect(probe.decodeOneGlyph(body: cmap, codeBytes: <int>[0x31]), '1');
    expect(probe.decodeOneGlyph(body: cmap, codeBytes: <int>[0x41]), 'B');
    expect(probe.decodeOneGlyph(body: cmap, codeBytes: <int>[0x51]), 'b');
  });

  test('G0af two-byte source code is width-sensitive', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<0000> <00FF>\n'
        'endcodespacerange\n1 beginbfchar\n<0031> <0032>\n'
        'endbfchar\nendcmap\n';
    const probe = C500G0CmapSemanticProbe();
    expect(probe.decodeOneGlyph(body: cmap, codeBytes: <int>[0, 0x31]), '2');
    expect(
      () => probe.decodeOneGlyph(body: cmap, codeBytes: <int>[0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AF_GLYPH_UNMAPPED')),
    );
  });

  test('G0af missing or invalid glyph source fails closed', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    const probe = C500G0CmapSemanticProbe();
    expect(
      () => probe.decodeOneGlyph(body: cmap, codeBytes: <int>[0x32]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AF_GLYPH_UNMAPPED')),
    );
    expect(
      () => probe.decodeOneGlyph(body: cmap, codeBytes: <int>[256]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AF_GLYPH_CODE_INVALID')),
    );
    expect(
      () => probe.decodeOneGlyph(body: cmap, codeBytes: <int>[]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AF_GLYPH_CODE_INVALID')),
    );
  });

  test('G0af selected glyph cannot hide unrelated forged UTF16', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n2 beginbfchar\n<31> <0031>\n'
        '<32> <D800>\nendbfchar\nendcmap\n';
    expect(
      () => const C500G0CmapSemanticProbe().decodeOneGlyph(
        body: cmap, codeBytes: <int>[0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_UTF16_INVALID')),
    );
  });

  test('G0af selected glyph cannot hide duplicate source mapping', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n2 beginbfchar\n<31> <0031>\n'
        '<31> <0032>\nendbfchar\nendcmap\n';
    expect(
      () => const C500G0CmapSemanticProbe().decodeOneGlyph(
        body: cmap, codeBytes: <int>[0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_DUPLICATE_OR_BUDGET')),
    );
  });

  test('G0ad semantic request without bounded CMap prerequisite rejects', () async {
    final file = await makeCatalogSynthetic(directory,
        includeFirstChild: true, includePageContent: true);
    await expectLater(
      inspectSynthetic(file, verifyFirstPageCmapSemantics: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_REQUIRES_CMAP_STREAM')),
    );
  });


  // G0ag: a real first text-show operand is attached only to its selected
  // font and verified CMap reference. No glyph bytes or Unicode are emitted.
  test('G0ag binds one selected-font operand to bounded CMap object', () async {
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Resources << /Font << /F1 11 0 R >> >> >>',
      ],
      selectedFontNames: <String>['F1'],
      selectedFirstOperands: <String, List<int>>{'F1': <int>[0x31]},
      verifyCmapStreams: true,
      verifyCmapSemantics: true,
      readObject: (id, generation) async {
        if (generation != 0) throw StateError('generation');
        if (id == 11) {
          return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
        }
        if (id == 21) return g0abCmapObject(21, compressed: true);
        throw StateError('unexpected object');
      },
    );
    expect(result['first_page_font_operand_cmap_candidates_bound'], 1);
    expect(result['first_page_font_operand_cmap_status'],
        'OPERAND_FONT_CMAP_OBJECT_ONLY_NOT_DECODED');
    expect(result['first_page_text_authority'],
        'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0ag missing first operand for selected font fails closed', () async {
    await expectLater(
      const C500G0FontResourceInspector().inspect(
        pageTreeObjects: <String>[
          '<< /Resources << /Font << /F1 11 0 R >> >> >>',
        ],
        selectedFontNames: <String>['F1'],
        selectedFirstOperands: <String, List<int>>{},
        readObject: (id, generation) async =>
            '11 0 obj << /Type /Font >> endobj',
      ),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AG_FIRST_OPERAND_MISSING',
      )),
    );
  });


  // G0ah: source-backed flow is exercised on official PDFs only in the lab.
  // Synthetic Unicode here is never official prize data.
  test('G0ah first bound operand decodes one private glyph only', () async {
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Resources << /Font << /F1 11 0 R >> >> >>',
      ],
      selectedFontNames: <String>['F1'],
      selectedFirstOperands: <String, List<int>>{'F1': <int>[0x31, 0x32]},
      verifyCmapStreams: true,
      verifyCmapSemantics: true,
      verifyFirstGlyphUnicode: true,
      readObject: (id, generation) async {
        if (generation != 0) throw StateError('generation');
        if (id == 11) {
          return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
        }
        if (id == 21) return g0abCmapObject(21, compressed: true);
        throw StateError('unexpected object');
      },
    );
    expect(result['first_page_font_operand_cmap_unicode_single_glyph_verified'], 1);
    expect(result['first_page_font_operand_cmap_unicode_status'],
        'ONE_GLYPH_DECODED_PRIVATELY_NOT_AWARD_NUMBER');
    expect(result['first_page_text_authority'],
        'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS');
  });

  test('G0ah two-byte codespace consumes only the first glyph', () {
    const body = 'begincmap\n1 begincodespacerange\n<0000> <00FF>\n'
        'endcodespacerange\n1 beginbfchar\n<0031> <0032>\n'
        'endbfchar\nendcmap\n';
    expect(const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
      body: body, operand: <int>[0, 0x31, 0x39]), '2');
  });

  test('G0ah ambiguous one- and two-byte codespaces fail closed', () {
    const body = 'begincmap\n2 begincodespacerange\n<00> <FF>\n'
        '<0000> <00FF>\nendcodespacerange\n2 beginbfchar\n'
        '<00> <0030>\n<0031> <0031>\nendbfchar\nendcmap\n';
    expect(() => const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
      body: body, operand: <int>[0, 0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AH_CODESPACE_AMBIGUOUS_OR_MISSING')));
  });

  test('G0ah unmapped first code cannot skip ahead to a mapped code', () {
    const body = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    expect(() => const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
      body: body, operand: <int>[0x32, 0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AH_FIRST_GLYPH_UNMAPPED')));
  });

  test('G0ah unrelated forged UTF16 cannot hide behind first glyph', () {
    const body = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n2 beginbfchar\n<31> <0031>\n'
        '<32> <D800>\nendbfchar\nendcmap\n';
    expect(() => const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
      body: body, operand: <int>[0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AD_UTF16_INVALID')));
  });

  test('G0ah empty and oversized operands reject before CMap work', () {
    const body = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    for (final operand in <List<int>>[<int>[], List<int>.filled(65537, 0x31)]) {
      expect(() => const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
        body: body, operand: operand),
        throwsA(isA<C500G0BoundedXrefException>().having(
          (e) => e.code, 'code', 'C500_G0AH_OPERAND_BUDGET')));
    }
  });

  test('G0ah semantic prerequisite is mandatory', () async {
    final directory = await Directory.systemTemp.createTemp('g0ah-prereq-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await makeSyntheticXref(directory);
    await expectLater(inspectSynthetic(file, verifyFirstPageGlyphUnicode: true),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AH_REQUIRES_SEMANTIC_CMAP')));
  });

  // G0ai: bounded full-operand counts are not award numbers or full-page proof.
  test('G0ai multi-glyph one-byte and two-byte runs count privately', () {
    const cmap = 'begincmap\n2 begincodespacerange\n<20> <7F>\n'
        '<8100> <81FF>\nendcodespacerange\n3 beginbfchar\n'
        '<31> <0031>\n<32> <0032>\n<8133> <0033>\n'
        'endbfchar\nendcmap\n';
    expect(const C500G0CmapSemanticProbe().countFullyDecodedOperandGlyphs(
      body: cmap, operand: <int>[0x31, 0x81, 0x33, 0x32]), 3);
  });

  test('G0ai unmapped later glyph is not hidden by valid first glyph', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    expect(() => const C500G0CmapSemanticProbe().countFullyDecodedOperandGlyphs(
      body: cmap, operand: <int>[0x31, 0x32]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AI_OPERAND_GLYPH_UNMAPPED')));
  });

  test('G0ai truncated multi-byte and ambiguous codespace reject', () {
    const two = 'begincmap\n1 begincodespacerange\n<8100> <81FF>\n'
        'endcodespacerange\n1 beginbfchar\n<8133> <0033>\n'
        'endbfchar\nendcmap\n';
    expect(() => const C500G0CmapSemanticProbe().countFullyDecodedOperandGlyphs(
      body: two, operand: <int>[0x81]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AI_CODESPACE_AMBIGUOUS_OR_TRUNCATED')));
    const ambiguous = 'begincmap\n2 begincodespacerange\n<00> <FF>\n'
        '<0000> <00FF>\nendcodespacerange\n2 beginbfchar\n'
        '<00> <0030>\n<0031> <0031>\nendbfchar\nendcmap\n';
    expect(() => const C500G0CmapSemanticProbe().countFullyDecodedOperandGlyphs(
      body: ambiguous, operand: <int>[0, 0x31]),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AI_CODESPACE_AMBIGUOUS_OR_TRUNCATED')));
  });

  test('G0ai operand length and glyph count budgets fail closed', () {
    const cmap = 'begincmap\n1 begincodespacerange\n<00> <FF>\n'
        'endcodespacerange\n1 beginbfchar\n<31> <0031>\n'
        'endbfchar\nendcmap\n';
    final probe = const C500G0CmapSemanticProbe();
    expect(() => probe.countFullyDecodedOperandGlyphs(
      body: cmap, operand: List<int>.filled(257, 0x31)),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AI_OPERAND_BUDGET')));
    expect(() => probe.countFullyDecodedOperandGlyphs(
      body: cmap, operand: List<int>.filled(65, 0x31)),
      throwsA(isA<C500G0BoundedXrefException>().having(
        (e) => e.code, 'code', 'C500_G0AI_GLYPH_BUDGET')));
  });

  test('G0ai source-bound full operand records counts, never text', () async {
    final result = await const C500G0FontResourceInspector().inspect(
      pageTreeObjects: <String>[
        '<< /Resources << /Font << /F1 11 0 R >> >> >>',
      ],
      selectedFontNames: <String>['F1'],
      selectedFirstOperands: <String, List<int>>{'F1': <int>[0x31]},
      verifyCmapStreams: true,
      verifyCmapSemantics: true,
      verifyFirstGlyphUnicode: true,
      verifyFirstOperandUnicodeRun: true,
      readObject: (id, generation) async {
        if (id == 11) return '11 0 obj << /Type /Font /ToUnicode 21 0 R >> endobj';
        if (id == 21) return g0abCmapObject(21);
        throw StateError('unexpected XRef id');
      },
    );
    expect(result['first_page_font_operand_unicode_full_runs_verified'], 1);
    expect(result['first_page_font_operand_unicode_full_run_glyphs_verified'], 1);
    expect(result.toString().contains('0031'), false);
    expect(result['first_page_text_authority'],
        'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS');
  });
}
