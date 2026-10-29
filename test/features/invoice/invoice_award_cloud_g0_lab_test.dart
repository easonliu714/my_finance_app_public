// G0 read-only, headless PDF structure lab. Run:
// flutter test test/features/invoice/invoice_award_cloud_g0_lab_test.dart
// For actual binary comparison, set G0_OLD_PDF and G0_NEW_PDF to local,
// independently acquired official files. Never promotes award authority.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';

const _oldUri = 'https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf';
const _newUri = 'https://invoice.etax.nat.gov.tw/pdf/20260708_20260925124717_sorted_AI_D.pdf';
const _newSha = 'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571';
const _oldHttpLength = 119769589; // Observed HTTP length; SHA not pinned.
const _newPinnedLength = 135200798;
const _inputBudget = 256 * 1024 * 1024; // Lab budget, not Android size limit.

Future<Map<String, Object?>> _measure(
  File file, {
  required String period,
  required int expectedLength,
  String? expectedSha,
}) async {
  if (!await file.exists()) throw StateError('SOURCE_BINARY_UNAVAILABLE:$period');
  final bytes = await file.length();
  if (bytes > _inputBudget || bytes <= 0) {
    throw StateError('G0_LAB_INPUT_BUDGET_EXCEEDED:$period');
  }
  if (bytes != expectedLength) {
    throw StateError('G0_SOURCE_BYTES_MISMATCH:$period');
  }
  final sw = Stopwatch()..start();
  final before = ProcessInfo.currentRss;
  var peak = before;
  final sampler = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final rss = ProcessInfo.currentRss;
    if (rss > peak) peak = rss;
  });
  late CloudAwardPdfStructureProbeResult result;
  try {
    result = await const CloudAwardPdfStructureProbe().inspect(file: file);
  } finally {
    sampler.cancel();
    sw.stop();
  }
  if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
  if (expectedSha != null && result.sha256 != expectedSha) {
    throw StateError('G0_SOURCE_SHA256_MISMATCH:$period');
  }
  return <String, Object?>{
    'period': period,
    'bytes': result.byteLength,
    'sha256': result.sha256,
    'sha_pin_verified': expectedSha != null,
    'pdf_version': result.pdfVersion,
    'xref_type': result.xrefTopology.name,
    'startxref': result.startXrefOffset,
    'object_stream_markers': result.objectStreamCount,
    'stream_markers': result.streamCount,
    'filter_markers': result.filterHistogram,
    'pages_count_markers': result.declaredPageCounts,
    'encryption_marker': result.hasEncryptionMarker,
    'incremental_prev_marker': result.hasIncrementalPreviousRevision,
    'max_scan_window_bytes': result.maxResidentScanWindowBytes,
    'dart_rss_before_bytes': before,
    'dart_rss_sampled_peak_bytes': peak,
    'elapsed_ms': sw.elapsedMilliseconds,
    'java_heap': 'NOT_MEASURED',
    'native_heap': 'NOT_MEASURED',
    'android_pss': 'NOT_MEASURED',
    'pdfbox_pdfium_pdfrenderer': 'NOT_RUN',
    'award_authority': 'HOLD',
  };
}

void main() {
  late Directory scratch;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('cloud500_g0_lab_');
  });
  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test('synthetic multi-MiB structure scan uses bounded existing probe', () async {
    final file = File(scratch.path + '/synthetic.pdf');
    final sink = file.openWrite();
    const header = '%PDF-1.7\n1 0 obj\n<< /Type /Pages /Count 87000 >>\nendobj\n';
    sink.add(latin1.encode(header));
    final block = List<String>.filled(65536, 'X').join();
    for (var i = 0; i < 32; i++) {
      sink.add(latin1.encode(block));
    }
    final xrefOffset = latin1.encode(header).length + 32 * 65536;
    sink.add(latin1.encode('xref\n0 1\n0000000000 65535 f \n'
        'trailer\n<< /Size 1 >>\nstartxref\n$xrefOffset\n%%EOF\n'));
    await sink.close();
    final evidence = await _measure(
      file,
      period: 'SYNTHETIC_NOT_OFFICIAL',
      expectedLength: await file.length(),
    );
    expect(evidence['xref_type'], 'classicTable');
    expect(evidence['max_scan_window_bytes'], 65536 + 1024);
    expect(evidence['bytes'], greaterThan(2 * 1024 * 1024));
    expect(evidence['pdfbox_pdfium_pdfrenderer'], 'NOT_RUN');
    expect(evidence['award_authority'], 'HOLD');
  });

  test('missing source and incorrect binary pins fail closed', () async {
    final file = File(scratch.path + '/missing.pdf');
    await expectLater(
      _measure(file, period: 'SYNTHETIC', expectedLength: 42),
      throwsA(isA<StateError>().having(
          (e) => e.toString(), 'code', contains('SOURCE_BINARY_UNAVAILABLE'))),
    );
    await file.writeAsBytes(latin1.encode('%PDF-1.7\n'), flush: true);
    await expectLater(
      _measure(file, period: 'SYNTHETIC', expectedLength: 999),
      throwsA(isA<StateError>().having(
          (e) => e.toString(), 'code', contains('G0_SOURCE_BYTES_MISMATCH'))),
    );
  });

  final oldPath = Platform.environment['G0_OLD_PDF'];
  final newPath = Platform.environment['G0_NEW_PDF'];
  test('actual official 115-05-06 and 115-07-08 structure comparison', () async {
    if (oldPath == null || newPath == null) {
      // This is a SOURCE_BINARY_UNAVAILABLE HOLD, not an official-file PASS.
      fail('SOURCE_BINARY_UNAVAILABLE: provide both verified local PDF paths');
    }
    final oldFile = File(oldPath);
    final newFile = File(newPath);
    final old = await _measure(
      oldFile, period: '115-05-06', expectedLength: _oldHttpLength,
    );
    final newer = await _measure(
      newFile, period: '115-07-08',
      expectedLength: _newPinnedLength, expectedSha: _newSha,
    );
    // Both files go through the same parser. Android engine-specific
    // root cause and Java/native/PSS are NOT established by this test.
    print(jsonEncode(<String, Object?>{
      'gate': 'G0_STRUCTURE_ONLY_ANDROID_ENGINES_NOT_RUN',
      'official_uris': <String>[_oldUri, _newUri],
      'old_sha_pin': 'UNAVAILABLE',
      'old': old,
      'new': newer,
      'production_authority': 'HOLD',
    }));
  }, skip: oldPath == null || newPath == null
      ? 'SOURCE_BINARY_UNAVAILABLE: official files not mounted' : false);
}
