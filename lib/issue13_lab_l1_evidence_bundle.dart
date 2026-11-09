import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

import 'issue13_lab_l1_cursor.dart';

/// Lab-only, explicitly shared, bounded evidence. Never reads the official
/// PDF, a finance database, or any file outside the exact Lab allowlist.
class LabL1EvidenceBundle {
  static const maxBatches = 12;
  static const maxBatchBytes = 4000000;
  static const maxJsonlBytes = 48000000;
  static const maxLogBytes = 2 * 1024 * 1024;
  static const maxZipBytes = 64 * 1024 * 1024;
  static const expectedPageCount = 87000;
  static const officialSha256 =
      'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571';

  static Future<String> _sha(File file) async {
    final sink = cryptography.Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = await sink.hash();
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<String> _shaBytes(List<int> bytes) async {
    final digest = await cryptography.Sha256().hash(bytes);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _trusted(Directory parent, File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('L1_BUNDLE_UNTRUSTED_FILE');
    }
    final base = await parent.resolveSymbolicLinks();
    final actual = await file.resolveSymbolicLinks();
    final name = file.uri.pathSegments.last;
    if (actual != '$base${Platform.pathSeparator}$name') {
      throw StateError('L1_BUNDLE_PATH_ESCAPE');
    }
  }

  /// Each explicitly selected window contains at most twelve native batches.
  /// The legacy no-window call still refuses a thirteenth batch. Every window
  /// validates the retained global page chain before creating a bounded ZIP.
  /// Neither path advances the durable cursor or modifies source JSONL.
  static Future<LabL1EvidenceBundleResult> create({
    required Directory lab,
    required String labHead,
    int? windowIndex,
    Future<void> Function()? afterArchiveWriteForTesting,
  }) async {
    if (windowIndex != null && windowIndex < 1) {
      throw ArgumentError('L1_BUNDLE_WINDOW_INDEX_INVALID');
    }
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(labHead)) {
      throw ArgumentError('L1_BUNDLE_HEAD_INVALID');
    }
    final inflight = '${lab.path}/l1-native-inflight.json';
    if (await FileSystemEntity.type(inflight, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('L1_BUNDLE_NATIVE_INFLIGHT_HOLD');
    }
    final cursor = File('${lab.path}/l1-next-page.txt');
    await _trusted(lab, cursor);
    if (await cursor.length() > 32) {
      throw StateError('L1_BUNDLE_CURSOR_INVALID');
    }
    final next = int.tryParse((await cursor.readAsString()).trim());
    if (next == null || next < 2 || next > expectedPageCount + 1) {
      throw StateError('L1_BUNDLE_CURSOR_INVALID');
    }

    final batches = <int, File>{};
    await for (final entity in lab.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('l1-pages-')) continue;
      final match = LabL1Cursor.namePattern.firstMatch(name);
      if (match == null || entity is! File) {
        throw StateError('L1_BUNDLE_PARTIAL_OR_UNTRUSTED_BATCH');
      }
      final first = int.parse(match.group(1)!);
      if (batches.containsKey(first)) {
        throw StateError('L1_BUNDLE_DUPLICATE_START');
      }
      batches[first] = File(entity.path);
      if (windowIndex == null && batches.length > maxBatches) {
        throw StateError('L1_BUNDLE_BATCH_BUDGET');
      }
      if (batches.length > (expectedPageCount + 3) ~/ 4) {
        throw StateError('L1_BUNDLE_RETAINED_BATCH_BUDGET');
      }
    }
    if (batches.isEmpty) throw StateError('L1_BUNDLE_NO_BATCHES');

    final starts = batches.keys.toList()..sort();
    var expected = 1;
    var windowBytes = 0;
    final allEntries = <Map<String, Object>>[];
    for (final first in starts) {
      if (first != expected) {
        throw StateError('L1_BUNDLE_PAGE_CHAIN_GAP');
      }
      final file = batches[first]!;
      await _trusted(lab, file);
      final batch = await LabL1Cursor.verify(
        lab, file, first, officialSha256,
        count: expectedPageCount,
      );
      final size = await file.length();
      if (size < 1 || size > maxBatchBytes) {
        throw StateError('L1_BUNDLE_BATCH_SIZE');
      }
      windowBytes += size;
      if (windowBytes > maxJsonlBytes) {
        throw StateError('L1_BUNDLE_TOTAL_SIZE');
      }
      allEntries.add(<String, Object>{
        'name': file.uri.pathSegments.last,
        'first_page': first,
        'last_page': batch.last,
        'bytes': size,
        'sha256': await _sha(file),
      });
      if (allEntries.length % maxBatches == 0) windowBytes = 0;
      expected = batch.last + 1;
    }
    if (expected != next) {
      throw StateError('L1_BUNDLE_CURSOR_CHAIN_MISMATCH');
    }
    final windowCount = (allEntries.length + maxBatches - 1) ~/ maxBatches;
    if (windowIndex != null && windowIndex > windowCount) {
      throw StateError('L1_BUNDLE_WINDOW_OUT_OF_RANGE');
    }
    final selectedStart =
        windowIndex == null ? 0 : (windowIndex - 1) * maxBatches;
    final selectedEnd = windowIndex == null
        ? allEntries.length
        : (selectedStart + maxBatches < allEntries.length
            ? selectedStart + maxBatches
            : allEntries.length);
    final entries = allEntries.sublist(selectedStart, selectedEnd);

    // The chain is based on immutable page metadata and JSONL digests, not
    // mutable debug logs or the cursor, so separate share sessions can link.
    final windowDigests = <String>[];
    var previousDigest = List<String>.filled(64, '0').join();
    for (var start = 0; start < allEntries.length; start += maxBatches) {
      final end = start + maxBatches < allEntries.length
          ? start + maxBatches
          : allEntries.length;
      previousDigest = await _shaBytes(utf8.encode(jsonEncode(<String, Object>{
        'schema': 'cloud500-lab-l1-window-chain-v1',
        'period': '115-07-08',
        'official_pdf_expected_sha256': officialSha256,
        'previous_window_chain_sha256': previousDigest,
        'jsonl': allEntries.sublist(start, end),
      })));
      windowDigests.add(previousDigest);
    }

    final dartLog = File('${lab.path}/issue13_cloud500_diag.log');
    final nativePrimary =
        File('${lab.parent.path}/issue13_cloud500_diag_native.log');
    final nativeAlternate =
        File('${lab.path}/issue13_cloud500_diag_native.log');
    final nativeLog = await FileSystemEntity.type(
              nativePrimary.path, followLinks: false,
            ) ==
            FileSystemEntityType.notFound
        ? nativeAlternate
        : nativePrimary;
    await _trusted(lab, dartLog);
    await _trusted(nativeLog.parent, nativeLog);
    final dartBytes = await dartLog.length();
    final nativeBytes = await nativeLog.length();
    if (dartBytes < 1 || nativeBytes < 1 ||
        dartBytes + nativeBytes > maxLogBytes) {
      throw StateError('L1_BUNDLE_LOG_BUDGET_OR_MISSING');
    }
    final dartHash = await _sha(dartLog);
    final nativeHash = await _sha(nativeLog);

    final manifest = <String, Object>{
      'schema': windowIndex == null
          ? 'cloud500-lab-l1-evidence-bundle-v1'
          : 'cloud500-lab-l1-evidence-window-v2',
      'lab_head': labHead,
      'period': '115-07-08',
      'tier': 'cloud-500',
      'engine': 'android.graphics.pdf.PdfRenderer',
      'official_pdf_expected_bytes': 135200798,
      'official_pdf_expected_sha256': officialSha256,
      'official_pdf_in_bundle': false,
      'source_pin_basis': 'owner_runtime_log_not_independent_pdf_rehash',
      'page_count': expectedPageCount,
      'first_page': entries.first['first_page']!,
      'last_page': entries.last['last_page']!,
      'cursor_next_page': next,
      'batch_count': entries.length,
      'jsonl': entries,
      'logs': <Map<String, Object>>[
        <String, Object>{
          'name': 'dart-debug.log', 'bytes': dartBytes, 'sha256': dartHash,
        },
        <String, Object>{
          'name': 'native-debug.log', 'bytes': nativeBytes, 'sha256': nativeHash,
        },
      ],
      'chain_structure': 'CONTIGUOUS_CURSOR_VERIFIED',
      'independent_token_and_source_audit': 'PENDING',
      'native_pss_rss_and_process_exit': 'UNKNOWN',
      'official_full_page_evidence': 'HOLD',
      'global_not_win': 'HOLD',
      'production_authority': 'HOLD',
    };
    if (windowIndex != null) {
      manifest.addAll(<String, Object>{
        'window_index': windowIndex,
        'window_count_at_export': windowCount,
        'window_first_page': entries.first['first_page']!,
        'window_last_page': entries.last['last_page']!,
        'durable_cursor_next_page': next,
        'previous_window_chain_sha256': windowIndex == 1
            ? List<String>.filled(64, '0').join()
            : windowDigests[windowIndex - 2],
        'window_chain_sha256': windowDigests[windowIndex - 1],
        'window_chain_basis': 'SHA256_UTF8_ORDERED_JSON_METADATA_V1',
        'export_slot': ((windowIndex - 1) % 2) + 1,
        'window_coverage': 'PARTIAL_WINDOW_NOT_FULL_87000',
      });
      manifest['chain_structure'] = 'CONTIGUOUS_GLOBAL_CURSOR_AND_WINDOW_VERIFIED';
    }

    // Two rolling output slots cap retained ZIP copies even after thousands
    // of captures. Share/save each selected window before reusing its slot.
    final slot = windowIndex == null ? null : ((windowIndex - 1) % 2) + 1;
    final suffix = slot == null
        ? ''
        : '-window-${slot.toString().padLeft(4, '0')}';
    final partial = File('${lab.path}/l1-evidence-share$suffix.zip.part');
    final output = File('${lab.path}/l1-evidence-share$suffix.zip');
    final manifestFile = File('${lab.path}/l1-evidence-share$suffix-manifest.part');
    for (final file in <File>[partial, manifestFile]) {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('L1_BUNDLE_UNRESOLVED_EXPORT_PART');
      }
    }
    if (await FileSystemEntity.type(output.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('L1_BUNDLE_OUTPUT_SYMLINK');
    }

    var started = false;
    var completed = false;
    try {
      await manifestFile.writeAsString(
        '${jsonEncode(manifest)}\n', flush: true,
      );
      final zip = ZipFileEncoder();
      started = true;
      zip.create(partial.path, level: 0);
      try {
        for (final entry in entries) {
          final name = entry['name']! as String;
          await zip.addFile(File('${lab.path}/$name'), name, 0);
        }
        await zip.addFile(dartLog, 'dart-debug.log', 0);
        await zip.addFile(nativeLog, 'native-debug.log', 0);
        await zip.addFile(manifestFile, 'manifest.json', 0);
      } finally {
        await zip.close();
      }
      final zipBytes = await partial.length();
      if (zipBytes < 1 || zipBytes > maxZipBytes) {
        throw StateError('L1_BUNDLE_ZIP_BUDGET');
      }
      // Rehash the full indexed chain, not only the selected window. A
      // concurrent edit to an earlier window must invalidate its successor.
      if (afterArchiveWriteForTesting != null) {
        await afterArchiveWriteForTesting();
      }
      for (final entry in allEntries) {
        final file = File('${lab.path}/${entry['name']}');
        await _trusted(lab, file);
        if (await file.length() != entry['bytes'] ||
            await _sha(file) != entry['sha256']) {
          throw StateError('L1_BUNDLE_SOURCE_CHANGED');
        }
      }
      if (await dartLog.length() != dartBytes ||
          await nativeLog.length() != nativeBytes ||
          await _sha(dartLog) != dartHash ||
          await _sha(nativeLog) != nativeHash) {
        throw StateError('L1_BUNDLE_LOG_CHANGED');
      }
      await _trusted(lab, cursor);
      if (await FileSystemEntity.type(inflight, followLinks: false) !=
              FileSystemEntityType.notFound ||
          (await cursor.readAsString()).trim() != '$next') {
        throw StateError('L1_BUNDLE_CURSOR_CHANGED_DURING_EXPORT');
      }
      await partial.rename(output.path);
      completed = true;
      return LabL1EvidenceBundleResult(
        output, manifest, await _sha(output),
      );
    } finally {
      if (await manifestFile.exists()) await manifestFile.delete();
      if (started && !completed && await partial.exists()) {
        await partial.delete();
      }
    }
  }
}

class LabL1EvidenceBundleResult {
  const LabL1EvidenceBundleResult(
    this.file, this.manifest, this.zipSha256,
  );
  final File file;
  final Map<String, Object> manifest;
  final String zipSha256;
}
