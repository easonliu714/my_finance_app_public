// C500-G0l: isolated bounded XRef-stream object-access experiment.
// Reads only the pinned PDF's startxref stream; never opens a whole-document
// object graph or promotes any invoice/winning/NOT_WIN authority.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'c500_g0_content_glyph_probe.dart';

import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_bounded_stream_decoder.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';

class C500G0BoundedXrefException implements Exception {
  const C500G0BoundedXrefException(this.code);
  final String code;
  @override
  String toString() => code;
}

class C500G0BoundedXrefInspector {
  const C500G0BoundedXrefInspector({
    this.maxHeaderBytes = 1024 * 1024,
    this.maxCompressedBytes = 32 * 1024 * 1024,
    this.maxDecodedBytes = 64 * 1024 * 1024,
    this.maxRootDecodedBytes = 512 * 1024 * 1024,
  });

  final int maxHeaderBytes;
  final int maxCompressedBytes;
  final int maxDecodedBytes;
  // Lab-only total decompressed-byte budget; never a heap or product limit.
  final int maxRootDecodedBytes;

  Future<Map<String, Object?>> inspect({
    required File file,
    required int expectedBytes,
    required String expectedSha256,
    bool verifyObjectOffsets = false,
    bool verifyCompressedMembers = false,
    bool verifyCatalogRoot = false,
    bool verifyFirstPageChild = false,
    bool verifyFirstPagePath = false,
    bool verifyFirstPageContents = false,
    bool verifyFirstPageGlyphOperands = false,
    bool verifyFirstPageFontResources = false,
    bool verifyFirstPageCmapStreams = false,
    bool verifyFirstPageCmapSemantics = false,
    bool verifyFirstPageGlyphUnicode = false,
    bool verifyFirstPageOperandUnicodeRun = false,
  }) async {
    if (maxHeaderBytes < 256 ||
        maxCompressedBytes <= 0 ||
        maxDecodedBytes <= 0 || maxRootDecodedBytes < 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0L_INVALID_LIMITS');
    }
    if (verifyCompressedMembers && !verifyObjectOffsets) {
      throw const C500G0BoundedXrefException('C500_G0O_REQUIRES_OFFSET_VERIFICATION');
    }
    // G0t: one first child only; never claim full page-tree coverage.
    if (verifyFirstPagePath && !verifyFirstPageChild) {
      throw const C500G0BoundedXrefException('C500_G0U_REQUIRES_FIRST_CHILD');
    }
    // G0ai: full first operand must retain the proven first-glyph custody.
    if (verifyFirstPageOperandUnicodeRun && !verifyFirstPageGlyphUnicode) {
      throw const C500G0BoundedXrefException('C500_G0AI_REQUIRES_FIRST_GLYPH');
    }
    // G0ah: real glyph Unicode requires bounded CMap semantics first.
    if (verifyFirstPageGlyphUnicode && !verifyFirstPageCmapSemantics) {
      throw const C500G0BoundedXrefException('C500_G0AH_REQUIRES_SEMANTIC_CMAP');
    }
    // G0ad: semantic CMap inspection is strictly downstream of bounded streams.
    if (verifyFirstPageCmapSemantics && !verifyFirstPageCmapStreams) {
      throw const C500G0BoundedXrefException('C500_G0AD_REQUIRES_CMAP_STREAM');
    }
    // G0ab: CMap access requires verified font bindings.
    if (verifyFirstPageCmapStreams && !verifyFirstPageFontResources) {
      throw const C500G0BoundedXrefException('C500_G0AB_REQUIRES_FONT_BINDING');
    }
    // G0aa: resource-to-font XRef binding requires proven first-leaf glyph state.
    if (verifyFirstPageFontResources && !verifyFirstPageGlyphOperands) {
      throw const C500G0BoundedXrefException('C500_G0AA_REQUIRES_GLYPH_STATE');
    }
    if (verifyFirstPageGlyphOperands && !verifyFirstPageContents) {
      throw const C500G0BoundedXrefException('C500_G0W_REQUIRES_CONTENT');
    }
    if (verifyFirstPageContents && !verifyFirstPagePath) {
      throw const C500G0BoundedXrefException('C500_G0V_REQUIRES_LEAF_PATH');
    }
    if (verifyFirstPageChild && !verifyCatalogRoot) {
      throw const C500G0BoundedXrefException('C500_G0T_REQUIRES_ROOT');
    }
    // G0q: Catalog/Pages-root access validates its own direct or compressed
    // object identity. Unrelated global ObjStm samples are NOT a prerequisite:
    // a sampled oversized parent must not obscure the root's first failure.
    // Reuse the existing fixed-window SHA/topology probe, not PDFBox/qpdf.
    final source = await const CloudAwardPdfStructureProbe().inspect(file: file);
    if (source.byteLength != expectedBytes ||
        source.sha256 != expectedSha256) {
      throw const C500G0BoundedXrefException('C500_G0L_SOURCE_PIN_MISMATCH');
    }
    if (source.xrefTopology != CloudAwardPdfXrefTopology.xrefStream ||
        source.hasEncryptionMarker ||
        source.hasIncrementalPreviousRevision) {
      throw const C500G0BoundedXrefException('C500_G0L_UNSUPPORTED_TOPOLOGY');
    }

    final handle = await file.open(mode: FileMode.read);
    try {
      await handle.setPosition(source.startXrefOffset);
      final headerBytes = await handle.read(
        min(maxHeaderBytes, source.byteLength - source.startXrefOffset),
      );
      final header = latin1.decode(headerBytes, allowInvalid: true);
      if (!RegExp(r'^\s*\d+\s+\d+\s+obj\b').hasMatch(header)) {
        throw const C500G0BoundedXrefException('C500_G0L_XREF_OBJECT_MISSING');
      }
      // G0m: real pinned XRef streams did not match the old 64 KiB,
      // newline-before-stream assumption. Only accept a bounded dictionary
      // terminator and stream token, never scan arbitrary PDF content.
      final streamMarker = RegExp(
        r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
      ).firstMatch(header);
      if (streamMarker == null) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_HEADER_MISSING');
      }
      final dictionary = header.substring(0, streamMarker.start + 2);
      if (!dictionary.endsWith('>>') ||
          !RegExp(r'/Type\s*/XRef\b').hasMatch(dictionary)) {
        throw const C500G0BoundedXrefException('C500_G0L_NOT_XREF_STREAM');
      }
      if (RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
        throw const C500G0BoundedXrefException('C500_G0L_INDIRECT_LENGTH');
      }
      if (!RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
              .hasMatch(dictionary) ||
          dictionary.contains('/DecodeParms')) {
        throw const C500G0BoundedXrefException('C500_G0L_UNSUPPORTED_FILTER');
      }
      int requiredNumber(String key) {
        final match = RegExp('/$key' r'\s+(\d+)\b').firstMatch(dictionary);
        if (match == null) {
          throw const C500G0BoundedXrefException('C500_G0L_REQUIRED_NUMBER_MISSING');
        }
        return int.parse(match.group(1)!);
      }

      final size = requiredNumber('Size');
      final compressedLength = requiredNumber('Length');
      final widthsMatch =
          RegExp(r'/W\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s*\]').firstMatch(dictionary);
      if (widthsMatch == null) {
        throw const C500G0BoundedXrefException('C500_G0L_W_MISSING');
      }
      final widths = <int>[
        int.parse(widthsMatch.group(1)!),
        int.parse(widthsMatch.group(2)!),
        int.parse(widthsMatch.group(3)!),
      ];
      final entryWidth = widths.reduce((a, b) => a + b);
      if (size <= 0 ||
          size > 8000000 ||
          widths.any((value) => value < 0 || value > 8) ||
          entryWidth == 0) {
        throw const C500G0BoundedXrefException('C500_G0L_INVALID_ENTRY_WIDTH');
      }

      final indexMatch = RegExp(r'/Index\s*\[([0-9\s]+)\]').firstMatch(dictionary);
      final indexes = indexMatch == null
          ? <int>[0, size]
          : RegExp(r'\d+')
              .allMatches(indexMatch.group(1)!)
              .map((match) => int.parse(match.group(0)!))
              .toList(growable: false);
      if (indexes.isEmpty || indexes.length.isOdd) {
        throw const C500G0BoundedXrefException('C500_G0L_INVALID_INDEX');
      }
      var entries = 0;
      for (var i = 0; i < indexes.length; i += 2) {
        if (indexes[i] < 0 ||
            indexes[i + 1] <= 0 ||
            indexes[i] + indexes[i + 1] > size) {
          throw const C500G0BoundedXrefException('C500_G0L_INVALID_INDEX');
        }
        entries += indexes[i + 1];
      }
      if (entries > maxDecodedBytes ~/ entryWidth) {
        throw const C500G0BoundedXrefException('C500_G0L_DECODED_LIMIT');
      }
      if (compressedLength <= 0 || compressedLength > maxCompressedBytes) {
        throw const C500G0BoundedXrefException('C500_G0L_COMPRESSED_LIMIT');
      }
      final streamOffset = source.startXrefOffset + streamMarker.end;
      if (streamOffset + compressedLength > source.byteLength) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_TRUNCATED');
      }
      await handle.setPosition(streamOffset);
      final compressed = await handle.read(compressedLength);
      if (compressed.length != compressedLength) {
        throw const C500G0BoundedXrefException('C500_G0L_STREAM_TRUNCATED');
      }
      final decoded = CloudAwardPdfBoundedStreamDecoder(
        maxCompressedBytes: maxCompressedBytes,
        maxDecodedBytes: maxDecodedBytes,
      ).decode(bytes: compressed, filters: const <String>['FlateDecode']);
      if (decoded.length != entries * entryWidth) {
        throw const C500G0BoundedXrefException('C500_G0L_DECODED_LENGTH_MISMATCH');
      }
      final types = <int, int>{0: 0, 1: 0, 2: 0};
      for (var offset = 0; offset < decoded.length; offset += entryWidth) {
        var type = widths[0] == 0 ? 1 : 0;
        for (var i = 0; i < widths[0]; i++) {
          type = (type << 8) | decoded[offset + i];
        }
        if (!types.containsKey(type)) {
          throw const C500G0BoundedXrefException('C500_G0L_UNKNOWN_ENTRY_TYPE');
        }
        types[type] = types[type]! + 1;
      }
      final navigation = verifyObjectOffsets
          ? await _sampleAddresses(handle, source.byteLength, decoded,
              widths, indexes, entryWidth, size, verifyCompressedMembers)
          : const <String, Object?>{};
      final catalog = verifyCatalogRoot
          ? await _verifyCatalogRoot(handle, source.byteLength, dictionary,
              decoded, widths, indexes, entryWidth,
              verifyFirstPageChild, verifyFirstPagePath,
              verifyFirstPageContents, verifyFirstPageGlyphOperands,
              verifyFirstPageFontResources, verifyFirstPageCmapStreams,
              verifyFirstPageCmapSemantics, verifyFirstPageGlyphUnicode)
          : const <String, Object?>{};
      return <String, Object?>{
        'gate': 'C500_G0L_BOUNDED_XREF_ONLY',
        ...navigation,
        ...catalog,
        'sha256': source.sha256,
        'bytes': source.byteLength,
        'startxref': source.startXrefOffset,
        'declared_size': size,
        'xref_entries': entries,
        'entry_width': entryWidth,
        'compressed_bytes': compressedLength,
        'decoded_bytes': decoded.length,
        'free_entries': types[0],
        'uncompressed_entries': types[1],
        'object_stream_entries': types[2],
        'all_pages': 'NOT_VERIFIED',
        'global_not_win': 'NOT_PROVEN',
        'award_authority': 'HOLD',
      };
    } finally {
      await handle.close();
    }
  }


  // G0p: reuse the pinned, bounded XRef for exactly two references.
  // Catalog and Pages-root validation is not page traversal or NOT_WIN.
  Map<String, int>? _lookupXrefEntry(
    List<int> bytes, List<int> widths, List<int> indexes, int stride, int id,
  ) {
    int field(int offset, int count) {
      var value = 0;
      for (var i = 0; i < count; i++) {
        value = (value << 8) | bytes[offset + i];
      }
      return value;
    }
    var base = 0;
    for (var i = 0; i < indexes.length; i += 2) {
      final start = indexes[i], count = indexes[i + 1];
      if (id >= start && id < start + count) {
        final offset = (base + id - start) * stride;
        return <String, int>{
          'type': widths[0] == 0 ? 1 : field(offset, widths[0]),
          'second': field(offset + widths[0], widths[1]),
          'third': field(offset + widths[0] + widths[1], widths[2]),
        };
      }
      base += count;
    }
    return null;
  }

  Future<Map<String, Object?>> _verifyCatalogRoot(
    RandomAccessFile file, int sourceLength, String xrefDictionary,
    List<int> bytes, List<int> widths, List<int> indexes, int stride,
    bool verifyFirstPageChild, bool verifyFirstPagePath,
    bool verifyFirstPageContents, bool verifyFirstPageGlyphOperands,
    bool verifyFirstPageFontResources, bool verifyFirstPageCmapStreams,
    bool verifyFirstPageCmapSemantics, bool verifyFirstPageGlyphUnicode,
  ) async {
    final root = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R\b')
        .firstMatch(xrefDictionary);
    if (root == null) {
      throw const C500G0BoundedXrefException('C500_G0P_ROOT_REFERENCE_MISSING');
    }
    final rootId = int.parse(root.group(1)!);
    final rootGeneration = int.parse(root.group(2)!);

    Future<String> readObject(int id, int generation) async {
      final entry = _lookupXrefEntry(bytes, widths, indexes, stride, id);
      if (entry == null || entry['type'] == 0) {
        throw const C500G0BoundedXrefException('C500_G0P_ROOT_XREF_MISSING');
      }
      if (entry['type'] == 1) {
        if (entry['third'] != generation) {
          throw const C500G0BoundedXrefException('C500_G0P_GENERATION_MISMATCH');
        }
        final offset = entry['second']!;
        if (offset <= 0 || offset >= sourceLength) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_OFFSET_INVALID');
        }
        await file.setPosition(offset);
        final content = latin1.decode(
          await file.read(min(64 * 1024, sourceLength - offset)),
          allowInvalid: true,
        );
        if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(content)) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_HEADER_MISMATCH');
        }
        final end = RegExp(r'\bendobj\b').firstMatch(content);
        if (end == null) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_BUDGET_EXCEEDED');
        }
        return content.substring(0, end.start);
      }
      if (entry['type'] == 2) {
        if (generation != 0) {
          throw const C500G0BoundedXrefException('C500_G0P_GENERATION_MISMATCH');
        }
        final parentId = entry['second']!;
        final parent = _lookupXrefEntry(bytes, widths, indexes, stride, parentId);
        if (parent == null || parent['type'] != 1) {
          throw const C500G0BoundedXrefException('C500_G0P_PARENT_NOT_DIRECT');
        }
        final offset = parent['second']!;
        final parentGeneration = parent['third']!;
        if (offset <= 0 || offset >= sourceLength) {
          throw const C500G0BoundedXrefException('C500_G0P_OBJECT_OFFSET_INVALID');
        }
        await file.setPosition(offset);
        final header = latin1.decode(
          await file.read(min(4096, sourceLength - offset)),
          allowInvalid: true,
        );
        if (!RegExp('^$parentId\\s+$parentGeneration\\s+obj\\b')
                .hasMatch(header) ||
            !RegExp(r'/Type\s*/ObjStm\b').hasMatch(header)) {
          throw const C500G0BoundedXrefException('C500_G0P_PARENT_HEADER_MISMATCH');
        }
        return _verifyCompressedMember(file, sourceLength, offset, header,
            <String, int>{'id': id, 'index': entry['third']!},
            allowLargeRootSpool: true);
      }
      throw const C500G0BoundedXrefException('C500_G0P_UNSUPPORTED_ENTRY_TYPE');
    }

    final catalog = await readObject(rootId, rootGeneration);
    if (!RegExp(r'/Type\s*/Catalog\b').hasMatch(catalog)) {
      throw const C500G0BoundedXrefException('C500_G0P_CATALOG_TYPE_INVALID');
    }
    final pages = RegExp(r'/Pages\s+(\d+)\s+(\d+)\s+R\b')
        .firstMatch(catalog);
    if (pages == null) {
      throw const C500G0BoundedXrefException('C500_G0P_PAGES_REFERENCE_MISSING');
    }
    final pagesId = int.parse(pages.group(1)!);
    final pagesBody = await readObject(pagesId, int.parse(pages.group(2)!));
    if (!RegExp(r'/Type\s*/Pages\b').hasMatch(pagesBody) ||
        !RegExp(r'/Kids\s*\[').hasMatch(pagesBody)) {
      throw const C500G0BoundedXrefException('C500_G0P_PAGES_TYPE_INVALID');
    }
    final count = RegExp(r'/Count\s+(\d+)\b').firstMatch(pagesBody);
    final declared = int.tryParse(count?.group(1) ?? '');
    if (declared == null || declared <= 0 || declared > 1000000) {
      throw const C500G0BoundedXrefException('C500_G0P_PAGE_COUNT_INVALID');
    }
    // G0t: inspect exactly one /Kids child through the pinned XRef.
    // Require the child's /Parent to point back to this Pages root.
    // This is not recursive traversal, award proof, or global NOT_WIN.
    final firstChildEvidence = <String, Object?>{};
    if (verifyFirstPageChild) {
      final kid = RegExp(r'/Kids\s*\[\s*(\d+)\s+(\d+)\s+R\b')
          .firstMatch(pagesBody);
      if (kid == null) {
        throw const C500G0BoundedXrefException('C500_G0T_KIDS_FORM_UNSUPPORTED');
      }
      final childId = int.parse(kid.group(1)!);
      final childGeneration = int.parse(kid.group(2)!);
      if (childId == rootId || childId == pagesId) {
        throw const C500G0BoundedXrefException('C500_G0T_CHILD_CYCLE');
      }
      final entry = _lookupXrefEntry(bytes, widths, indexes, stride, childId);
      if (entry == null || entry['type'] == 0) {
        throw const C500G0BoundedXrefException('C500_G0T_CHILD_XREF_MISSING');
      }
      final childBody = await readObject(childId, childGeneration);
      if (!RegExp(r'/Type\s*/(?:Pages|Page)\b').hasMatch(childBody)) {
        throw const C500G0BoundedXrefException('C500_G0T_CHILD_TYPE_INVALID');
      }
      final parent = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R\b')
          .firstMatch(childBody);
      if (parent == null ||
          int.parse(parent.group(1)!) != pagesId ||
          int.parse(parent.group(2)!) != int.parse(pages.group(2)!)) {
        throw const C500G0BoundedXrefException('C500_G0T_PARENT_MISMATCH');
      }
      // G0u: only the leftmost bounded path to one Page leaf.
      // Each object uses the pinned XRef and capped direct/ObjStm reader.
      // Siblings, whole tree, sorted awards and NOT_WIN remain unverified.
      if (verifyFirstPagePath) {
        const maxDepth = 8;
        final seen = <int>{pagesId, childId};
        var nodeId = childId;
        var nodeGeneration = childGeneration;
        var nodeBody = childBody;
        // Resources are inheritable: retain only this bounded leftmost path.
        final resourcePath = <String>[pagesBody, childBody];
        var parentCount = declared;
        var depth = 1;
        while (RegExp(r'/Type\s*/Pages\b').hasMatch(nodeBody)) {
          if (depth >= maxDepth) {
            throw const C500G0BoundedXrefException('C500_G0U_PATH_DEPTH_LIMIT');
          }
          final countMatch = RegExp(r'/Count\s+(\d+)\b').firstMatch(nodeBody);
          final childCount = int.tryParse(countMatch?.group(1) ?? '');
          if (childCount == null || childCount <= 0 ||
              childCount > parentCount) {
            throw const C500G0BoundedXrefException('C500_G0U_SUBTREE_COUNT_INVALID');
          }
          final next = RegExp(r'/Kids\s*\[\s*(\d+)\s+(\d+)\s+R\b')
              .firstMatch(nodeBody);
          if (next == null) {
            throw const C500G0BoundedXrefException('C500_G0U_KIDS_FORM_UNSUPPORTED');
          }
          final nextId = int.parse(next.group(1)!);
          final nextGeneration = int.parse(next.group(2)!);
          if (nextId == rootId || !seen.add(nextId)) {
            throw const C500G0BoundedXrefException('C500_G0U_CHILD_CYCLE');
          }
          final nextBody = await readObject(nextId, nextGeneration);
          resourcePath.add(nextBody);
          if (!RegExp(r'/Type\s*/(?:Pages|Page)\b').hasMatch(nextBody)) {
            throw const C500G0BoundedXrefException('C500_G0U_CHILD_TYPE_INVALID');
          }
          final parentRef = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R\b')
              .firstMatch(nextBody);
          if (parentRef == null ||
              int.parse(parentRef.group(1)!) != nodeId ||
              int.parse(parentRef.group(2)!) != nodeGeneration) {
            throw const C500G0BoundedXrefException('C500_G0U_PARENT_MISMATCH');
          }
          parentCount = childCount;
          nodeId = nextId;
          nodeGeneration = nextGeneration;
          nodeBody = nextBody;
          depth++;
        }
        if (!RegExp(r'/Type\s*/Page\b').hasMatch(nodeBody)) {
          throw const C500G0BoundedXrefException('C500_G0U_LEAF_TYPE_INVALID');
        }
        firstChildEvidence['leftmost_page_id'] = nodeId;
        firstChildEvidence['leftmost_path_depth'] = depth;
        firstChildEvidence['leftmost_path_verified'] = true;
        if (verifyFirstPageContents) {
          firstChildEvidence.addAll(await _verifyFirstPageContents(
            file, sourceLength, bytes, widths, indexes, stride, nodeBody,
            verifyFirstPageGlyphOperands,
          ));
          // G0ag: the raw candidate is internal and must never reach JSON.
          final firstOperands =
              firstChildEvidence.remove('__g0ag_first_font_operands');
          if (verifyFirstPageFontResources) {
            if (firstOperands is! Map<String, List<int>>) {
              throw const C500G0BoundedXrefException(
                  'C500_G0AG_FIRST_OPERAND_MISSING');
            }
            final names =
                firstChildEvidence['first_page_text_font_names_unverified'];
            if (names is! List<String>) {
              throw const C500G0BoundedXrefException(
                  'C500_G0AA_FONT_STATE_MISSING');
            }
            firstChildEvidence.addAll(
              await const C500G0FontResourceInspector().inspect(
                pageTreeObjects: resourcePath,
                selectedFontNames: names,
                selectedFirstOperands: firstOperands,
                readObject: readObject,
                verifyCmapStreams: verifyFirstPageCmapStreams,
                verifyCmapSemantics: verifyFirstPageCmapSemantics,
                verifyFirstGlyphUnicode: verifyFirstPageGlyphUnicode,
                verifyFirstOperandUnicodeRun: verifyFirstPageOperandUnicodeRun,
              ),
            );
          }
        }
      }
      firstChildEvidence['first_root_child_id'] = childId;
      firstChildEvidence['first_root_child_verified'] = true;
    }
    return <String, Object?>{
      'catalog_root_id': rootId,
      'catalog_root_verified': true,
      'pages_root_id': pagesId,
      'pages_root_verified': true,
      'declared_page_count_unverified': declared,
      ...firstChildEvidence,
      'page_tree': verifyFirstPagePath
          ? 'LEFTMOST_PATH_ONLY_NOT_TRAVERSED'
          : verifyFirstPageChild
          ? 'FIRST_CHILD_ONLY_NOT_TRAVERSED'
          : 'ROOT_ONLY_NOT_TRAVERSED',
    };
  }


  // G0v: bounded access to ONE first-page /Contents stream; lexical evidence
  // only. Not PDF text/award parsing, all-page proof or NOT_WIN authority.
  Future<Map<String, Object?>> _verifyFirstPageContents(
    RandomAccessFile file, int sourceLength, List<int> xref,
    List<int> widths, List<int> indexes, int stride, String leaf,
    bool verifyFirstPageGlyphOperands,
  ) async {
    if (RegExp(r'/Contents\s*\[').hasMatch(leaf)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_ARRAY_UNSUPPORTED');
    }
    final refs = RegExp(r'/Contents\s+(\d+)\s+(\d+)\s+R\b').allMatches(leaf).toList();
    if (refs.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_REFERENCE_MISSING');
    }
    final id = int.parse(refs.single.group(1)!);
    final generation = int.parse(refs.single.group(2)!);
    final entry = _lookupXrefEntry(xref, widths, indexes, stride, id);
    if (entry == null || entry['type'] != 1 || entry['third'] != generation) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_XREF_INVALID');
    }
    final objectOffset = entry['second']!;
    if (objectOffset <= 0 || objectOffset >= sourceLength) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_OFFSET_INVALID');
    }
    await file.setPosition(objectOffset);
    final header = latin1.decode(
      await file.read(min(4096, sourceLength - objectOffset)),
      allowInvalid: true,
    );
    if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(header)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_HEADER_MISMATCH');
    }
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(header);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_STREAM_MISSING');
    }
    final dictionary = header.substring(0, marker.start + 2);
    if (dictionary.contains('/DecodeParms') ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_UNSUPPORTED');
    }
    final lengthMatch = RegExp(r'/Length\s+(\d+)\b').firstMatch(dictionary);
    if (lengthMatch == null) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_LENGTH_MISSING');
    }
    final length = int.parse(lengthMatch.group(1)!);
    const maxCompressed = 2 * 1024 * 1024;
    if (length <= 0 || length > maxCompressed) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_LENGTH_LIMIT');
    }
    final hasFilter = dictionary.contains('/Filter');
    if (hasFilter &&
        !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
            .hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_FILTER_UNSUPPORTED');
    }
    final streamOffset = objectOffset + marker.end;
    if (streamOffset > sourceLength || length > sourceLength - streamOffset) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_TRUNCATED');
    }
    await file.setPosition(streamOffset);
    final compressed = await file.read(length);
    if (compressed.length != length) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_TRUNCATED');
    }
    final suffix = await file.read(min(32, sourceLength - streamOffset - length));
    if (!RegExp(r'^(?:\r\n|\r|\n)?endstream\b')
        .hasMatch(latin1.decode(suffix, allowInvalid: true))) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_ENDSTREAM_MISMATCH');
    }
    List<int> decoded;
    try {
      decoded = hasFilter
          ? const CloudAwardPdfBoundedStreamDecoder(
              maxCompressedBytes: maxCompressed,
              maxDecodedBytes: 8 * 1024 * 1024,
            ).decode(bytes: compressed, filters: const <String>['FlateDecode'])
          : compressed;
    } catch (_) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_DECODE_FAILED');
    }
    final body = latin1.decode(decoded, allowInvalid: true);
    if (!RegExp(r'(?:^|\s)BT(?:\s|$)').hasMatch(body) ||
        !RegExp(r'(?:^|\s)ET(?:\s|$)').hasMatch(body)) {
      throw const C500G0BoundedXrefException('C500_G0V_CONTENT_TEXT_MARKERS_MISSING');
    }
    final firstOperands = <String, List<int>>{};
    final glyphEvidence = verifyFirstPageGlyphOperands
        ? const C500G0GlyphProbe().inspect(decoded,
            onFirstFontOperand: (font, bytes) {
              firstOperands[font] = bytes;
            })
        : const <String, Object?>{};
    return <String, Object?>{
      'leftmost_content_object_id': id,
      'leftmost_content_compressed_bytes': length,
      'leftmost_content_decoded_bytes': decoded.length,
      'leftmost_content_stream_verified': true,
      ...glyphEvidence,
      '__g0ag_first_font_operands': firstOperands,
      'content_semantics': verifyFirstPageGlyphOperands
          ? 'GLYPH_OPERANDS_ONE_PAGE_ONLY'
          : 'UNPARSED_ONE_PAGE_ONLY',
    };
  }

  // G0n: at most five direct and five compressed-parent address samples.
  // Header samples are not a page-tree traversal or a NOT_WIN proof.
  Future<Map<String, Object?>> _sampleAddresses(
    RandomAccessFile file, int length, List<int> bytes,
    List<int> widths, List<int> indexes, int stride, int size,
    bool verifyCompressedMembers,
  ) async {
    int field(int offset, int count) {
      var result = 0;
      for (var i = 0; i < count; i++) {
        result = (result << 8) | bytes[offset + i];
      }
      return result;
    }
    Map<String, int>? lookup(int id) =>
        _lookupXrefEntry(bytes, widths, indexes, stride, id);
    final targets = <int>[0, size ~/ 4, size ~/ 2, size * 3 ~/ 4, size - 1];
    final direct = <Map<String, int>>[], compressed = <Map<String, int>>[];
    var d = 0, c = 0, base = 0;
    for (var i = 0; i < indexes.length; i += 2) {
      for (var j = 0; j < indexes[i + 1]; j++) {
        final id = indexes[i] + j, offset = (base + j) * stride;
        final type = widths[0] == 0 ? 1 : field(offset, widths[0]);
        if (type == 1 && d < targets.length && id >= targets[d]) {
          direct.add(<String, int>{
            'id': id,
            'offset': field(offset + widths[0], widths[1]),
            'generation': field(offset + widths[0] + widths[1], widths[2]),
          });
          d++;
        } else if (type == 2 && c < targets.length && id >= targets[c]) {
          compressed.add(<String, int>{
            'id': id,
            'parent': field(offset + widths[0], widths[1]),
            'index': field(offset + widths[0] + widths[1], widths[2]),
          });
          c++;
        }
      }
      base += indexes[i + 1];
    }
    Future<String> header(int id, int generation, int offset) async {
      if (offset < 0 || offset >= length) {
        throw const C500G0BoundedXrefException('C500_G0N_OBJECT_OFFSET_INVALID');
      }
      await file.setPosition(offset);
      final content = latin1.decode(
        await file.read(min(4096, length - offset)), allowInvalid: true,
      );
      if (!RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(content)) {
        throw const C500G0BoundedXrefException('C500_G0N_OBJECT_HEADER_MISMATCH');
      }
      return content;
    }
    for (final sample in direct) {
      await header(sample['id']!, sample['generation']!, sample['offset']!);
    }
    var verifiedMembers = 0;
    for (final sample in compressed) {
      final id = sample['parent']!, parent = lookup(sample['parent']!);
      if (parent == null || parent['type'] != 1) {
        throw const C500G0BoundedXrefException('C500_G0N_PARENT_NOT_DIRECT');
      }
      final content = await header(id, parent['third']!, parent['second']!);
      if (!RegExp(r'/Type\s*/ObjStm\b').hasMatch(content)) {
        throw const C500G0BoundedXrefException('C500_G0N_PARENT_NOT_OBJSTM');
      }
      final match = RegExp(r'/N\s+(\d+)\b').firstMatch(content);
      final count = int.tryParse(match?.group(1) ?? '');
      if (count == null || count <= 0 || sample['index']! >= count) {
        throw const C500G0BoundedXrefException('C500_G0N_COMPRESSED_INDEX_INVALID');
      }
      if (verifyCompressedMembers) {
        await _verifyCompressedMember(file, length, parent['second']!, content, sample);
        verifiedMembers++;
      }
    }
    return <String, Object?>{
      'object_navigation': verifyCompressedMembers
          ? 'BOUNDED_OBJSTM_MEMBER_SAMPLES_ONLY'
          : 'BOUNDED_HEADER_SAMPLES_ONLY',
      'compressed_members_verified': verifiedMembers,
      'direct_headers_verified': direct.length,
      'objstm_parent_headers_verified': compressed.length,
      'page_tree': 'NOT_TRAVERSED',
    };
  }

  // G0o: decode only a selected size-capped ObjStm and prove that its
  // XRef compressed member id/index pair matches. Not full-page evidence.
  Future<String> _verifyCompressedMember(
    RandomAccessFile file, int sourceLength, int parentOffset,
    String header, Map<String, int> sample, {
    bool allowLargeRootSpool = false,
  }) async {
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(header);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_HEADER_MISSING');
    }
    final dictionary = header.substring(0, marker.start + 2);
    if (!RegExp(r'/Type\s*/ObjStm\b').hasMatch(dictionary) ||
        !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
            .hasMatch(dictionary) ||
        dictionary.contains('/DecodeParms') ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary)) {
      throw const C500G0BoundedXrefException('C500_G0O_UNSUPPORTED_STREAM');
    }
    int number(String key) {
      final match = RegExp('/$key' r'\s+(\d+)\b').firstMatch(dictionary);
      if (match == null) {
        throw const C500G0BoundedXrefException('C500_G0O_REQUIRED_NUMBER_MISSING');
      }
      return int.parse(match.group(1)!);
    }
    final count = number('N'), first = number('First');
    final compressedLength = number('Length');
    // G0q: preserve each independent resource ceiling and attribute the
    // first rejected field; never silently increase a cap for official PDFs.
    if (count <= 0 || count > 100000) {
      throw const C500G0BoundedXrefException('C500_G0O_COUNT_LIMIT');
    }
    if (first <= 0 || first > 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_LIMIT');
    }
    if (compressedLength <= 0 ||
        (!allowLargeRootSpool && compressedLength > 2 * 1024 * 1024)) {
      throw const C500G0BoundedXrefException('C500_G0O_COMPRESSED_LIMIT');
    }
    // G0r: root-only disk-spool experiment, not an in-memory cap increase.
    if (allowLargeRootSpool && compressedLength > 32 * 1024 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0R_COMPRESSED_LIMIT');
    }
    final offset = parentOffset + marker.end;
    if (offset < 0 || offset > sourceLength ||
        compressedLength > sourceLength - offset) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_TRUNCATED');
    }
    if (allowLargeRootSpool && compressedLength > 2 * 1024 * 1024) {
      return _readRootMemberViaBoundedStream(
        file, offset, compressedLength, count, first, sample,
      );
    }
    await file.setPosition(offset);
    final compressed = await file.read(compressedLength);
    if (compressed.length != compressedLength) {
      throw const C500G0BoundedXrefException('C500_G0O_STREAM_TRUNCATED');
    }
    final decoded = const CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 2 * 1024 * 1024,
      maxDecodedBytes: 8 * 1024 * 1024,
    ).decode(bytes: compressed, filters: const <String>['FlateDecode']);
    if (first >= decoded.length) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_INVALID');
    }
    final words = latin1.decode(decoded.sublist(0, first))
        .trim().split(RegExp(r'\s+'));
    if (words.length != 2 * count ||
        words.any((word) => !RegExp(r'^\d+$').hasMatch(word))) {
      throw const C500G0BoundedXrefException('C500_G0O_INDEX_HEADER_INVALID');
    }
    final index = sample['index']!;
    if (index < 0 || index >= count ||
        int.parse(words[2 * index]) != sample['id']) {
      throw const C500G0BoundedXrefException('C500_G0O_MEMBER_ID_MISMATCH');
    }
    var previous = -1;
    for (var i = 0; i < count; i++) {
      final start = int.parse(words[2 * i + 1]);
      if (start < 0 || start <= previous ||
          start >= decoded.length - first) {
        throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
      }
      previous = start;
    }
    final start = first + int.parse(words[2 * index + 1]);
    final end = index + 1 == count
        ? decoded.length
        : first + int.parse(words[2 * (index + 1) + 1]);
    if (end <= start || decoded.sublist(start, end).every((b) => b <= 32)) {
      throw const C500G0BoundedXrefException('C500_G0O_EMPTY_MEMBER');
    }
    return latin1.decode(decoded.sublist(start, end), allowInvalid: true);
  }

  // G0s: root-only, bounded-memory selective stream extraction. The prior
  // 64 MiB disposable spool failed for BOTH pinned genuine MOF PDFs. Do not
  // increase heap/disk allocation to match an untrusted ObjStm: retain only
  // <=1 MiB index + <=64 KiB selected member, while validating the ENTIRE
  // Flate stream and Adler32 under a 512 MiB total-output/32 MiB input cap.
  // This is NOT page-tree traversal, a PDFBox fix, or global NOT_WIN proof.
  Future<String> _readRootMemberViaBoundedStream(
    RandomAccessFile source, int offset, int compressedLength,
    int count, int first, Map<String, int> sample,
  ) async {
    const maxMember = 64 * 1024, maxChunk = 1024 * 1024;
    final indexBytes = <int>[];
    final memberBytes = <int>[];
    List<int>? starts;
    int? begin, end;
    var decodedBytes = 0, adlerA = 1, adlerB = 0;
    try {
      await for (final chunk in ZLibDecoder().bind(
        File(source.path).openRead(offset, offset + compressedLength),
      )) {
        if (chunk.length > maxChunk) {
          throw const C500G0BoundedXrefException('C500_G0S_CHUNK_LIMIT');
        }
        if (chunk.length > maxRootDecodedBytes - decodedBytes) {
          throw const C500G0BoundedXrefException('C500_G0S_TOTAL_DECODED_LIMIT');
        }
        final chunkStart = decodedBytes;
        final chunkEnd = chunkStart + chunk.length;
        if (indexBytes.length < first) {
          final take = min(first - indexBytes.length, chunk.length);
          indexBytes.addAll(chunk.take(take));
          if (indexBytes.length == first) {
            final words = latin1.decode(indexBytes).trim().split(RegExp(r'\s+'));
            if (words.length != count * 2 ||
                words.any((word) => !RegExp(r'^\d+$').hasMatch(word))) {
              throw const C500G0BoundedXrefException('C500_G0O_INDEX_HEADER_INVALID');
            }
            final index = sample['index']!;
            if (index < 0 || index >= count ||
                int.parse(words[index * 2]) != sample['id']) {
              throw const C500G0BoundedXrefException('C500_G0O_MEMBER_ID_MISMATCH');
            }
            starts = <int>[];
            var previous = -1;
            for (var i = 0; i < count; i++) {
              final start = int.parse(words[i * 2 + 1]);
              if (start <= previous) {
                throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
              }
              starts.add(start);
              previous = start;
            }
            begin = first + starts[index];
            if (index + 1 < count) {
              end = first + starts[index + 1];
              if (end <= begin || end - begin > maxMember) {
                throw const C500G0BoundedXrefException('C500_G0R_SELECTED_MEMBER_LIMIT');
              }
            }
          }
        }
        if (begin != null) {
          final overlapStart = max(chunkStart, begin);
          final overlapEnd = min(chunkEnd, end ?? chunkEnd);
          if (overlapEnd > overlapStart) {
            if (overlapEnd - overlapStart > maxMember - memberBytes.length) {
              throw const C500G0BoundedXrefException('C500_G0R_SELECTED_MEMBER_LIMIT');
            }
            memberBytes.addAll(chunk.sublist(
              overlapStart - chunkStart, overlapEnd - chunkStart,
            ));
          }
        }
        for (final value in chunk) {
          adlerA = (adlerA + value) % 65521;
          adlerB = (adlerB + adlerA) % 65521;
        }
        decodedBytes = chunkEnd;
      }
    } on C500G0BoundedXrefException {
      rethrow;
    } catch (_) {
      throw const C500G0BoundedXrefException('C500_G0R_STREAM_DECODE_FAILED');
    }
    // Independently compare the RFC1950 trailer even when zlib accepts it.
    await source.setPosition(offset + compressedLength - 4);
    final trailer = await source.read(4);
    if (trailer.length != 4) {
      throw const C500G0BoundedXrefException('C500_G0R_STREAM_TRUNCATED');
    }
    final expected = (trailer[0] << 24) | (trailer[1] << 16) |
        (trailer[2] << 8) | trailer[3];
    if (((adlerB << 16) | adlerA) != expected) {
      throw const C500G0BoundedXrefException('C500_G0R_ADLER_MISMATCH');
    }
    if (starts == null || first >= decodedBytes || begin == null) {
      throw const C500G0BoundedXrefException('C500_G0O_FIRST_INVALID');
    }
    for (final start in starts) {
      if (start >= decodedBytes - first) {
        throw const C500G0BoundedXrefException('C500_G0O_MEMBER_OFFSET_INVALID');
      }
    }
    final selectedEnd = end ?? decodedBytes;
    if (selectedEnd <= begin || selectedEnd - begin > maxMember) {
      throw const C500G0BoundedXrefException('C500_G0R_SELECTED_MEMBER_LIMIT');
    }
    if (memberBytes.length != selectedEnd - begin ||
        memberBytes.every((b) => b <= 32)) {
      throw const C500G0BoundedXrefException('C500_G0O_EMPTY_MEMBER');
    }
    return latin1.decode(memberBytes, allowInvalid: true);
  }

}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('C500_G0L_USAGE_NO_ARGUMENTS');
    exitCode = 64;
    return;
  }
  const sources = <Map<String, Object>>[
    <String, Object>{
      'period': '115-05-06',
      'env': 'G0_OLD_PDF',
      'bytes': 119769589,
      'sha': '1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe',
    },
    <String, Object>{
      'period': '115-07-08',
      'env': 'G0_NEW_PDF',
      'bytes': 135200798,
      'sha': 'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571',
    },
  ];
  var failures = 0;
  for (final source in sources) {
    final period = source['period']! as String;
    final path = Platform.environment[source['env']! as String];
    try {
      if (path == null || path.isEmpty) {
        throw const C500G0BoundedXrefException('C500_G0L_SOURCE_UNAVAILABLE');
      }
      final result = await const C500G0BoundedXrefInspector().inspect(
        file: File(path),
        expectedBytes: source['bytes']! as int,
        expectedSha256: source['sha']! as String,
        // G0q official experiment: isolate exactly the pinned Catalog and
        // Pages root; never run unrelated sampled ObjStm scans in this mode.
        verifyObjectOffsets: false,
        verifyCompressedMembers: false,
        verifyCatalogRoot: true,
        verifyFirstPageChild: true,
        verifyFirstPagePath: true,
        verifyFirstPageContents: true,
        verifyFirstPageGlyphOperands: true,
        verifyFirstPageFontResources: true,
        verifyFirstPageCmapStreams: true,
        verifyFirstPageCmapSemantics: true,
        verifyFirstPageGlyphUnicode: true,
        verifyFirstPageOperandUnicodeRun: true,
      );
      stdout.writeln(jsonEncode(<String, Object?>{'period': period, ...result}));
    } catch (error) {
      failures++;
      stdout.writeln(jsonEncode(<String, Object?>{
        'period': period,
        'gate': 'C500_G0L_HOLD_BOUNDED_XREF',
        'failure': error.toString(),
        'global_not_win': 'NOT_PROVEN',
        'award_authority': 'HOLD',
      }));
    }
  }
  if (failures != 0) exitCode = 1;
}


// G0aa: bounded FIRST-LEAF inherited /Resources -> /Font XRef binding.
// Resolves only selected font objects. No CMap decoding, award numbers,
// sibling pages, full page-tree traversal, or global NOT_WIN authority.
typedef C500G0ReadObject = Future<String> Function(int id, int generation);

class C500G0FontResourceInspector {
  const C500G0FontResourceInspector();

  Future<Map<String, Object?>> inspect({
    required List<String> pageTreeObjects,
    required List<String> selectedFontNames,
    required C500G0ReadObject readObject,
    Map<String, List<int>>? selectedFirstOperands,
    bool verifyCmapStreams = false,
    bool verifyCmapSemantics = false,
    bool verifyFirstGlyphUnicode = false,
    bool verifyFirstOperandUnicodeRun = false,
  }) async {
    if (pageTreeObjects.isEmpty || pageTreeObjects.length > 9 ||
        selectedFontNames.isEmpty || selectedFontNames.length > 16 ||
        selectedFontNames.toSet().length != selectedFontNames.length) {
      throw const C500G0BoundedXrefException('C500_G0AA_RESOURCE_BUDGET');
    }
    String? resources;
    for (final object in pageTreeObjects) {
      final keys = RegExp(r'/Resources\b').allMatches(object).toList();
      if (keys.length > 1) {
        throw const C500G0BoundedXrefException('C500_G0AA_DUPLICATE_RESOURCES');
      }
      if (keys.isNotEmpty) {
        // The nearest page/ancestor definition replaces an inherited one.
        resources = await _resolveDictionary(
          object.substring(keys.single.end), readObject);
      }
    }
    if (resources == null) {
      throw const C500G0BoundedXrefException('C500_G0AA_RESOURCES_MISSING');
    }
    final fontKeys = RegExp(r'/Font\b').allMatches(resources).toList();
    if (fontKeys.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0AA_FONT_DICTIONARY_MISSING');
    }
    final fontDictionary = await _resolveDictionary(
      resources.substring(fontKeys.single.end), readObject);
    final refs = RegExp(r'/([A-Za-z0-9_.-]{1,64})\s+(\d+)\s+(\d+)\s+R\b')
        .allMatches(fontDictionary);
    final bindings = <String, List<int>>{};
    for (final ref in refs) {
      final name = ref.group(1)!;
      if (bindings.containsKey(name) || bindings.length >= 64) {
        throw const C500G0BoundedXrefException('C500_G0AA_FONT_BINDING_DUPLICATE_OR_LIMIT');
      }
      bindings[name] = <int>[
        int.parse(ref.group(2)!), int.parse(ref.group(3)!),
      ];
    }
    if (verifyFirstOperandUnicodeRun && !verifyFirstGlyphUnicode) {
      throw const C500G0BoundedXrefException('C500_G0AI_REQUIRES_FIRST_GLYPH');
    }
    if (verifyFirstGlyphUnicode && !verifyCmapSemantics) {
      throw const C500G0BoundedXrefException('C500_G0AH_REQUIRES_SEMANTIC_CMAP');
    }
    if (verifyCmapSemantics && !verifyCmapStreams) {
      throw const C500G0BoundedXrefException('C500_G0AD_REQUIRES_CMAP_STREAM');
    }
    var cmapReferences = 0, cmapStreams = 0, cmapMappedCodes = 0;
    var cmapBoundOperands = 0, unicodeFirstGlyphs = 0;
    var unicodeFullOperands = 0, unicodeFullOperandGlyphs = 0;
    for (final name in selectedFontNames) {
      final ref = bindings[name];
      if (ref == null) {
        throw const C500G0BoundedXrefException('C500_G0AA_SELECTED_FONT_UNBOUND');
      }
      final candidate = selectedFirstOperands?[name];
      if (selectedFirstOperands != null &&
          (candidate == null || candidate.isEmpty || candidate.length > 64 * 1024)) {
        throw const C500G0BoundedXrefException(
            'C500_G0AG_FIRST_OPERAND_MISSING');
      }
      final font = await readObject(ref[0], ref[1]);
      if (!RegExp(r'/Type\s*/Font\b').hasMatch(font)) {
        throw const C500G0BoundedXrefException('C500_G0AA_FONT_OBJECT_INVALID');
      }
      final cmapKeys = RegExp(r'/ToUnicode\b').allMatches(font).toList();
      if (cmapKeys.length > 1) {
        throw const C500G0BoundedXrefException('C500_G0AA_CMAP_REFERENCE_INVALID');
      }
      if (cmapKeys.isNotEmpty) {
        final tail = font.substring(cmapKeys.single.end).trimLeft();
        if (!RegExp(r'^\d+\s+\d+\s+R\b').hasMatch(tail)) {
          throw const C500G0BoundedXrefException('C500_G0AA_CMAP_REFERENCE_INVALID');
        }
        // G0ab: only selected font CMap objects via pinned XRef.
        final reference = RegExp(r'^(\d+)\s+(\d+)\s+R\b').firstMatch(tail);
        if (reference == null) {
          throw const C500G0BoundedXrefException('C500_G0AA_CMAP_REFERENCE_INVALID');
        }
        cmapReferences++;
        if (verifyCmapStreams) {
          final id = int.parse(reference.group(1)!);
          final generation = int.parse(reference.group(2)!);
          // G0ah: same SHA-pinned selected font/CMap object.
          // Unicode stays private; only a count enters diagnostics.
          final cmapObject = await readObject(id, generation);
          cmapMappedCodes += const C500G0CmapStreamProbe().verify(
            object: cmapObject,
            id: id,
            generation: generation,
            verifyMappings: verifyCmapSemantics,
            firstOperand: verifyFirstGlyphUnicode ? candidate : null,
            verifyFullOperand: verifyFirstOperandUnicodeRun,
            onFullOperandDecoded: (count) {
              unicodeFullOperands++;
              unicodeFullOperandGlyphs += count;
            },
          );
          cmapStreams++;
          if (verifyCmapSemantics && candidate != null) {
            cmapBoundOperands++;
            if (verifyFirstGlyphUnicode) unicodeFirstGlyphs++;
          }
        }
      }
    }
    if (verifyCmapStreams && cmapStreams == 0) {
      throw const C500G0BoundedXrefException('C500_G0AB_CMAP_REFERENCE_MISSING');
    }
    if (verifyFirstGlyphUnicode && unicodeFirstGlyphs == 0) {
      throw const C500G0BoundedXrefException('C500_G0AH_NO_FIRST_GLYPH');
    }
    return <String, Object?>{
      'first_page_font_resource_binding': 'SELECTED_FONT_XREF_OBJECTS_ONLY',
      'first_page_font_objects_verified': selectedFontNames.length,
      'first_page_tounicode_references_unverified': cmapReferences - cmapStreams,
      'first_page_tounicode_streams_structure_verified': cmapStreams,
      'first_page_tounicode_mapping_codes_syntax_verified': cmapMappedCodes,
      // Only the real first-page operand's font-to-CMap object relationship.
      // No code-space segmentation or glyph-to-Unicode decoding is claimed.
      'first_page_font_operand_cmap_candidates_bound': cmapBoundOperands,
      'first_page_font_operand_cmap_unicode_single_glyph_verified': unicodeFirstGlyphs,
      'first_page_font_operand_unicode_full_runs_verified': unicodeFullOperands,
      'first_page_font_operand_unicode_full_run_glyphs_verified': unicodeFullOperandGlyphs,
      'first_page_font_operand_unicode_full_run_status': unicodeFullOperands > 0
          ? 'ONE_BOUNDED_OPERAND_PER_FONT_PRIVATELY_DECODED_NOT_AWARD_PROOF'
          : 'NOT_VERIFIED',
      'first_page_font_operand_cmap_unicode_status': unicodeFirstGlyphs > 0
          ? 'ONE_GLYPH_DECODED_PRIVATELY_NOT_AWARD_NUMBER'
          : 'NOT_VERIFIED',
      'first_page_font_operand_cmap_status': cmapBoundOperands > 0
          ? 'OPERAND_FONT_CMAP_OBJECT_ONLY_NOT_DECODED'
          : 'NOT_VERIFIED',
      'first_page_font_cmap': verifyCmapSemantics && cmapMappedCodes > 0
          ? 'BOUNDED_CMAP_SYNTAX_ONLY_NOT_GLYPH_TEXT'
          : cmapStreams > 0
              ? 'BOUNDED_STREAM_LEXICAL_STRUCTURE_ONLY_NOT_MAPPING'
              : 'NOT_VERIFIED',
      'first_page_text_authority': 'FONT_OBJECTS_ONLY_NOT_AWARD_NUMBERS',
    };
  }

  Future<String> _resolveDictionary(
    String value, C500G0ReadObject readObject,
  ) async {
    final tail = value.trimLeft();
    if (tail.startsWith('<<')) return _boundedDictionary(tail);
    final reference = RegExp(r'^(\d+)\s+(\d+)\s+R\b').firstMatch(tail);
    if (reference == null) {
      throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_FORM_UNSUPPORTED');
    }
    final object = await readObject(
      int.parse(reference.group(1)!), int.parse(reference.group(2)!));
    final start = object.indexOf('<<');
    if (start < 0) {
      throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_FORM_UNSUPPORTED');
    }
    return _boundedDictionary(object.substring(start));
  }

  String _boundedDictionary(String text) {
    if (!text.startsWith('<<') || text.length > 64 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_BUDGET');
    }
    var depth = 0;
    for (var i = 0; i < text.length - 1; i++) {
      final a = text.codeUnitAt(i), b = text.codeUnitAt(i + 1);
      if (a == 60 && b == 60) {
        depth++;
        if (depth > 16) {
          throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_DEPTH');
        }
        i++;
      } else if (a == 62 && b == 62) {
        depth--;
        i++;
        if (depth == 0) return text.substring(2, i - 1);
        if (depth < 0) {
          throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_UNBALANCED');
        }
      }
    }
    throw const C500G0BoundedXrefException('C500_G0AA_DICTIONARY_UNBALANCED');
  }
}


// G0ab: one SHA-pinned XRef-resolved /ToUnicode stream at a time.
// This validates only bounded CMap lexical structure, never Unicode mapping,
// invoice numbers, all pages, or global NOT_WIN.
class C500G0CmapStreamProbe {
  const C500G0CmapStreamProbe();

  int verify({
    required String object,
    required int id,
    required int generation,
    bool verifyMappings = false,
    List<int>? firstOperand,
    bool verifyFullOperand = false,
    void Function(int glyphCount)? onFullOperandDecoded,
  }) {
    if (object.length > 64 * 1024 ||
        !RegExp('^$id\\s+$generation\\s+obj\\b').hasMatch(object)) {
      throw const C500G0BoundedXrefException('C500_G0AB_OBJECT_IDENTITY_OR_BUDGET');
    }
    final marker = RegExp(
      r'>>[ \t]*(?:\r\n|\r|\n)?stream(?:\r\n|\r|\n)',
    ).firstMatch(object);
    if (marker == null) {
      throw const C500G0BoundedXrefException('C500_G0AB_STREAM_HEADER_MISSING');
    }
    final dictionary = object.substring(0, marker.start + 2);
    final lengths = RegExp(r'/Length\s+(\d+)\b').allMatches(dictionary).toList();
    if (lengths.length != 1 ||
        RegExp(r'/Length\s+\d+\s+\d+\s+R\b').hasMatch(dictionary) ||
        dictionary.contains('/DecodeParms')) {
      throw const C500G0BoundedXrefException('C500_G0AB_UNSUPPORTED_DICTIONARY');
    }
    final length = int.parse(lengths.single.group(1)!);
    if (length <= 0 || length > 32 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0AB_COMPRESSED_LENGTH_LIMIT');
    }
    final filters = RegExp(r'/Filter\b').allMatches(dictionary).length;
    if (filters > 1 ||
        (filters == 1 &&
            !RegExp(r'/Filter\s*(?:/FlateDecode\b|\[\s*/FlateDecode\s*\])')
                .hasMatch(dictionary))) {
      throw const C500G0BoundedXrefException('C500_G0AB_FILTER_UNSUPPORTED');
    }
    if (length > object.length - marker.end) {
      throw const C500G0BoundedXrefException('C500_G0AB_STREAM_TRUNCATED');
    }
    final suffix = object.substring(marker.end + length);
    if (!RegExp(r'^(?:\r\n|\r|\n)?endstream\b').hasMatch(suffix)) {
      throw const C500G0BoundedXrefException('C500_G0AB_ENDSTREAM_MISMATCH');
    }
    final bytes = latin1.encode(object.substring(marker.end, marker.end + length));
    List<int> decoded;
    try {
      decoded = filters == 1
          ? const CloudAwardPdfBoundedStreamDecoder(
              maxCompressedBytes: 32 * 1024,
              maxDecodedBytes: 256 * 1024,
            ).decode(bytes: bytes, filters: const <String>['FlateDecode'])
          : bytes;
    } catch (_) {
      throw const C500G0BoundedXrefException('C500_G0AB_STREAM_DECODE_FAILED');
    }
    final body = latin1.decode(decoded, allowInvalid: true);
    if (RegExp(r'\bbegincmap\b').allMatches(body).length != 1 ||
        RegExp(r'\bendcmap\b').allMatches(body).length != 1 ||
        !RegExp(r'\bbegincodespacerange\b').hasMatch(body) ||
        !RegExp(r'\bendcodespacerange\b').hasMatch(body) ||
        !(RegExp(r'\bbeginbfchar\b').hasMatch(body) ||
            RegExp(r'\bbeginbfrange\b').hasMatch(body))) {
      throw const C500G0BoundedXrefException('C500_G0AB_CMAP_LEXICAL_MARKERS_MISSING');
    }
    if (firstOperand != null && !verifyMappings) {
      throw const C500G0BoundedXrefException('C500_G0AH_REQUIRES_SEMANTIC_CMAP');
    }
    final mapped = verifyMappings ? const C500G0CmapSemanticProbe().verify(body) : 0;
    if (firstOperand != null) {
      // Never serialize Unicode or raw operand; no invoice-number authority.
      const C500G0CmapSemanticProbe().decodeFirstOperandGlyph(
        body: body, operand: firstOperand,
      );
    }
    if (verifyFullOperand) {
      if (firstOperand == null || !verifyMappings) {
        throw const C500G0BoundedXrefException('C500_G0AI_REQUIRES_FIRST_GLYPH');
      }
      final count = const C500G0CmapSemanticProbe()
          .countFullyDecodedOperandGlyphs(body: body, operand: firstOperand);
      onFullOperandDecoded?.call(count);
    }
    return mapped;
  }
}


// G0ad: bounded syntax and UTF-16 consistency for one already verified CMap.
// This never promotes glyph bytes to invoice numbers, and never proves the
// remaining pages, global ordering, or NOT_WIN. Unsupported syntax fails closed.
class C500G0CmapSemanticProbe {
  const C500G0CmapSemanticProbe();

  // G0ai: decode every code in ONE bounded first text-show operand only.
  // Full CMap validation precedes segmentation; Unicode never leaves memory.
  // This is neither a page-level nor an invoice-level authority decision.
  int countFullyDecodedOperandGlyphs({
    required String body,
    required List<int> operand,
  }) {
    if (operand.isEmpty || operand.length > 256 ||
        operand.any((byte) => byte < 0 || byte > 255)) {
      throw const C500G0BoundedXrefException('C500_G0AI_OPERAND_BUDGET');
    }
    final codespaces = <List<int>>[];
    final mappings = <int, List<int>>{};
    verify(body,
      onCodespace: (width, low, high) {
        codespaces.add(<int>[width, low, high]);
      },
      onMapping: (width, source, units) {
        mappings[(width << 32) | source] = List<int>.of(units);
      },
    );
    var position = 0;
    var glyphCount = 0;
    while (position < operand.length) {
      if (glyphCount >= 64) {
        throw const C500G0BoundedXrefException('C500_G0AI_GLYPH_BUDGET');
      }
      final matches = <int>[];
      var prefix = 0;
      for (var width = 1; width <= 4 &&
          position + width <= operand.length; width++) {
        prefix = (prefix << 8) | operand[position + width - 1];
        for (final range in codespaces) {
          if (range[0] == width && range[1] <= prefix &&
              prefix <= range[2]) {
            matches.add(width);
          }
        }
      }
      if (matches.length != 1) {
        throw const C500G0BoundedXrefException(
            'C500_G0AI_CODESPACE_AMBIGUOUS_OR_TRUNCATED');
      }
      final width = matches.single;
      var source = 0;
      for (var i = 0; i < width; i++) {
        source = (source << 8) | operand[position + i];
      }
      if (!mappings.containsKey((width << 32) | source)) {
        throw const C500G0BoundedXrefException(
            'C500_G0AI_OPERAND_GLYPH_UNMAPPED');
      }
      position += width;
      glyphCount++;
    }
    return glyphCount;
  }

  // G0ah: first code-space-delimited glyph in a verified text-show operand.
  // Entire CMap is validated before decoding; ambiguous/missing fails closed.
  String decodeFirstOperandGlyph({
    required String body,
    required List<int> operand,
  }) {
    if (operand.isEmpty || operand.length > 64 * 1024) {
      throw const C500G0BoundedXrefException('C500_G0AH_OPERAND_BUDGET');
    }
    final prefixes = <int, int>{};
    var code = 0;
    for (var i = 0; i < min(4, operand.length); i++) {
      final byte = operand[i];
      if (byte < 0 || byte > 255) {
        throw const C500G0BoundedXrefException('C500_G0AH_OPERAND_BUDGET');
      }
      code = (code << 8) | byte;
      prefixes[i + 1] = code;
    }
    final matches = <int>[];
    List<int>? decodedUnits;
    verify(body,
      onCodespace: (width, low, high) {
        final prefix = prefixes[width];
        if (prefix != null && low <= prefix && prefix <= high) {
          matches.add(width);
        }
      },
      onMapping: (width, source, units) {
        if (prefixes[width] == source) decodedUnits = List<int>.of(units);
      },
    );
    if (matches.length != 1) {
      throw const C500G0BoundedXrefException('C500_G0AH_CODESPACE_AMBIGUOUS_OR_MISSING');
    }
    if (decodedUnits == null) {
      throw const C500G0BoundedXrefException('C500_G0AH_FIRST_GLYPH_UNMAPPED');
    }
    return String.fromCharCodes(decodedUnits!);
  }

  // G0af: bounded one-glyph ToUnicode lookup after validating the ENTIRE
  // selected CMap. This is a lab-only code-unit experiment, not a PDF invoice,
  // complete-page, sorting, or NOT_WIN decision.
  String decodeOneGlyph({
    required String body,
    required List<int> codeBytes,
  }) {
    if (codeBytes.isEmpty || codeBytes.length > 4 ||
        codeBytes.any((byte) => byte < 0 || byte > 255)) {
      throw const C500G0BoundedXrefException('C500_G0AF_GLYPH_CODE_INVALID');
    }
    var sourceCode = 0;
    for (final byte in codeBytes) {
      sourceCode = (sourceCode << 8) | byte;
    }
    List<int>? matchedUnits;
    verify(body, onMapping: (width, code, utf16Units) {
      if (width == codeBytes.length && code == sourceCode) {
        matchedUnits = List<int>.of(utf16Units);
      }
    });
    if (matchedUnits == null) {
      throw const C500G0BoundedXrefException('C500_G0AF_GLYPH_UNMAPPED');
    }
    return String.fromCharCodes(matchedUnits!);
  }

  int verify(String body, {
    void Function(int width, int code, List<int> utf16Units)? onMapping,
    void Function(int width, int low, int high)? onCodespace,
  }) {
    if (body.length > 256 * 1024 ||
        RegExp(r'\busecmap\b|\b(?:begin|end)(?:cidchar|cidrange|notdefchar|notdefrange)\b')
            .hasMatch(body)) {
      throw const C500G0BoundedXrefException('C500_G0AD_UNSUPPORTED_SEMANTICS');
    }
    final codespaces = <List<int>>[];
    final seen = <int>{};
    var mapped = 0;
    String? kind;
    var expected = 0;
    final entries = <String>[];
    final begin = RegExp(r'^(\d+)[ \t]+begin(codespacerange|bfchar|bfrange)$');
    final control = RegExp(r'\b(?:begin|end)(?:codespacerange|bfchar|bfrange)\b');
    final tokens = RegExp(r'<[0-9A-Fa-f]+>|\[|\]|[^\s]+');

    for (final rawLine in body.split(RegExp(r'\r\n|\r|\n'))) {
      final line = rawLine.split('%').first.trim();
      if (line.isEmpty) continue;
      if (kind == null) {
        final match = begin.firstMatch(line);
        if (match != null) {
          expected = int.parse(match.group(1)!);
          if (expected < 1 || expected > 256) {
            throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_BUDGET');
          }
          kind = match.group(2)!;
          entries.clear();
        } else if (control.hasMatch(line)) {
          throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
        }
        continue;
      }
      if (line == 'end$kind') {
        var index = 0;
        for (var row = 0; row < expected; row++) {
          if (index + 1 >= entries.length) {
            throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
          }
          final low = _source(entries[index++]);
          final highOrTarget = entries[index++];
          if (kind == 'codespacerange') {
            final high = _source(highOrTarget);
            if (low.$1 != high.$1 || low.$2 > high.$2 ||
                codespaces.length >= 16) {
              throw const C500G0BoundedXrefException('C500_G0AD_CODESPACE_INVALID');
            }
            codespaces.add(<int>[low.$1, low.$2, high.$2]);
            onCodespace?.call(low.$1, low.$2, high.$2);
            continue;
          }
          _requireCodespace(low, codespaces);
          if (kind == 'bfchar') {
            final units = _utf16(highOrTarget);
            _record(low.$1, low.$2, seen);
            onMapping?.call(low.$1, low.$2, units);
            mapped++;
            continue;
          }
          final high = _source(highOrTarget);
          if (high.$1 != low.$1 || high.$2 < low.$2 ||
              high.$2 - low.$2 >= 8192) {
            throw const C500G0BoundedXrefException('C500_G0AD_RANGE_INVALID');
          }
          final span = high.$2 - low.$2 + 1;
          if (index >= entries.length) {
            throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
          }
          final destination = entries[index++];
          final mappedUnits = <List<int>>[];
          if (destination == '[') {
            for (var offset = 0; offset < span; offset++) {
              if (index >= entries.length) {
                throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
              }
              mappedUnits.add(_utf16(entries[index++]));
            }
            if (index >= entries.length || entries[index++] != ']') {
              throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
            }
          } else {
            final units = _utf16(destination);
            if (units.length != 1) {
              throw const C500G0BoundedXrefException('C500_G0AD_RANGE_INVALID');
            }
            for (var offset = 0; offset < span; offset++) {
              final unit = units.single + offset;
              if (unit > 0xffff || (unit >= 0xd800 && unit <= 0xdfff)) {
                throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
              }
              mappedUnits.add(<int>[unit]);
            }
          }
          for (var offset = 0; offset < span; offset++) {
            _requireCodespace((low.$1, low.$2 + offset), codespaces);
            _record(low.$1, low.$2 + offset, seen);
            onMapping?.call(low.$1, low.$2 + offset, mappedUnits[offset]);
          }
          mapped += span;
          if (mapped > 8192) {
            throw const C500G0BoundedXrefException('C500_G0AD_MAPPING_BUDGET');
          }
        }
        if (index != entries.length) {
          throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
        }
        kind = null;
        entries.clear();
        continue;
      }
      if (control.hasMatch(line)) {
        throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
      }
      entries.addAll(tokens.allMatches(line).map((match) => match.group(0)!));
      if (entries.length > 32768) {
        throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_BUDGET');
      }
    }
    if (kind != null || codespaces.isEmpty || mapped == 0) {
      throw const C500G0BoundedXrefException('C500_G0AD_BLOCK_GRAMMAR');
    }
    return mapped;
  }

  (int, int) _source(String token) {
    final match = RegExp(r'^<([0-9A-Fa-f]{2,8})>$').firstMatch(token);
    final hex = match?.group(1);
    if (hex == null || hex.length.isOdd) {
      throw const C500G0BoundedXrefException('C500_G0AD_SOURCE_INVALID');
    }
    return (hex.length ~/ 2, int.parse(hex, radix: 16));
  }

  List<int> _utf16(String token) {
    final match = RegExp(r'^<([0-9A-Fa-f]{4,64})>$').firstMatch(token);
    final hex = match?.group(1);
    if (hex == null || hex.length % 4 != 0) {
      throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
    }
    final units = <int>[];
    for (var i = 0; i < hex.length; i += 4) {
      units.add(int.parse(hex.substring(i, i + 4), radix: 16));
    }
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length ||
            units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const C500G0BoundedXrefException('C500_G0AD_UTF16_INVALID');
      }
    }
    return units;
  }

  void _requireCodespace((int, int) code, List<List<int>> ranges) {
    if (!ranges.any((range) => range[0] == code.$1 &&
        range[1] <= code.$2 && code.$2 <= range[2])) {
      throw const C500G0BoundedXrefException('C500_G0AD_CODESPACE_INVALID');
    }
  }

  void _record(int width, int value, Set<int> seen) {
    if (!seen.add((width << 32) | value) || seen.length > 8192) {
      throw const C500G0BoundedXrefException('C500_G0AD_DUPLICATE_OR_BUDGET');
    }
  }
}
