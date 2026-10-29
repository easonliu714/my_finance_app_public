// C500-G0a: isolated, read-only official PDF acquisition for the root-cause lab.
// Run only on a controlled engineering runner: dart run tool/c500_g0_acquire.dart
// Creates a new private system-temp directory; never touches app SQLite/LKG.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_finance_app/features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_structure_probe.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

class C500G0Source {
  const C500G0Source({
    required this.period,
    required this.uriText,
    required this.expectedBytes,
    this.expectedSha256,
  });

  final String period;
  final String uriText;
  final int expectedBytes;
  final String? expectedSha256;

  Uri get uri => Uri.parse(uriText);
  String get artifactId => uri.pathSegments.last;

  OfficialCloudAwardArtifactReference get reference =>
      OfficialCloudAwardArtifactReference(
        artifactId: artifactId,
        sourceUri: uri,
        periodId: period,
        tierCode: 'cloud-500',
      );
}

const c500G0Sources = <C500G0Source>[
  C500G0Source(
    period: '115-05-06',
    uriText:
        'https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf',
    // G0b 2026-10-30: independent ephemeral GitHub-runner HTTPS fetch
    // verified this exact binary; pin is lab-only, not award authority.
    expectedBytes: 119769589,
    expectedSha256:
        '1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe',
  ),
  C500G0Source(
    period: '115-07-08',
    uriText:
        'https://invoice.etax.nat.gov.tw/pdf/20260708_20260925124717_sorted_AI_D.pdf',
    expectedBytes: 135200798,
    expectedSha256:
        'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571',
  ),
];

/// Reuses the production bounded streaming downloader and structural probe.
/// No result from this lab may be promoted to award or ledger authority.
Future<Map<String, Object?>> acquireC500G0Source({
  required C500G0Source source,
  required Directory labDirectory,
  required http.Client client,
}) async {
  if (!source.reference.isApprovedOfficialSource ||
      source.reference.tierCode != 'cloud-500' ||
      !RegExp(r'^\d{8}_\d{14}_sorted_AI_D\.pdf$')
          .hasMatch(source.artifactId)) {
    throw StateError('G0_SOURCE_NOT_APPROVED');
  }
  if (source.expectedBytes <= 0 || source.expectedBytes > 256 * 1024 * 1024) {
    throw StateError('G0_SOURCE_SIZE_PIN_INVALID');
  }
  await labDirectory.create(recursive: true);
  final partial = File.fromUri(
    labDirectory.uri.resolve(source.artifactId.replaceAll('.pdf', '.partial')),
  );
  final finalFile = File.fromUri(labDirectory.uri.resolve(source.artifactId));
  if (await finalFile.exists()) {
    throw StateError('G0_LAB_DESTINATION_EXISTS_NO_OVERWRITE');
  }

  final timer = Stopwatch()..start();
  final rssBefore = ProcessInfo.currentRss;
  var peakRss = rssBefore;
  final sampler = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final rss = ProcessInfo.currentRss;
    if (rss > peakRss) peakRss = rss;
  });
  try {
    final downloaded = await MinistryOfFinanceCloudAwardArtifactDownloader(
      client: client,
      maxArtifactBytes: 256 * 1024 * 1024,
    ).download(
      reference: source.reference,
      destinationTempFile: partial,
    );
    if (downloaded.sizeBytes != source.expectedBytes) {
      throw StateError('G0_SOURCE_BYTES_MISMATCH');
    }
    if (source.expectedSha256 != null &&
        downloaded.sha256 != source.expectedSha256) {
      throw StateError('G0_SOURCE_SHA256_MISMATCH');
    }
    final structure = await const CloudAwardPdfStructureProbe().inspect(
      file: partial,
    );
    if (structure.byteLength != downloaded.sizeBytes ||
        structure.sha256 != downloaded.sha256) {
      throw StateError('G0_DOWNLOAD_PROBE_IDENTITY_MISMATCH');
    }
    await partial.rename(finalFile.path);
    return <String, Object?>{
      'period': source.period,
      'source_uri': source.uri.toString(),
      'lab_file': finalFile.path,
      'bytes': downloaded.sizeBytes,
      'sha256': downloaded.sha256,
      'sha_pin': source.expectedSha256 == null
          ? 'UNPINNED_SYNTHETIC_OR_EXPERIMENTAL_SOURCE'
          : source.period == '115-05-06'
              ? 'MATCHED_G0B_OBSERVED_115_05_06_PIN'
              : 'MATCHED_ARCHIVED_115_07_08_PIN',
      'pdf_version': structure.pdfVersion,
      'xref_type': structure.xrefTopology.name,
      'startxref': structure.startXrefOffset,
      'object_stream_markers': structure.objectStreamCount,
      'stream_markers': structure.streamCount,
      'filters': structure.filterHistogram,
      'declared_page_count_markers': structure.declaredPageCounts,
      'encryption_marker': structure.hasEncryptionMarker,
      'incremental_prev_marker': structure.hasIncrementalPreviousRevision,
      'max_scan_window_bytes': structure.maxResidentScanWindowBytes,
      'rss_before_bytes': rssBefore,
      'rss_sampled_peak_bytes': peakRss,
      'elapsed_ms': timer.elapsedMilliseconds,
      'pdfbox_pdfium_pdfrenderer': 'NOT_RUN',
      'java_heap_native_heap_android_pss': 'NOT_MEASURED',
      'global_negative_proof': 'NOT_RUN',
      'award_authority': 'HOLD',
    };
  } catch (_) {
    if (await partial.exists()) await partial.delete();
    rethrow;
  } finally {
    sampler.cancel();
    timer.stop();
  }
}

/// No automatic redirect to a non-authoritative host. The production
/// downloader remains unchanged; this restriction applies to the lab only.
/// G0a laboratory-only network bounds: a stalled official source must not
/// consume the entire diagnostic run or prevent the other period's evidence.
/// Header and body-idle budgets are independent; neither proves PDF validity.
class C500G0PinnedNoRedirectClient extends http.BaseClient {
  C500G0PinnedNoRedirectClient(
    this._inner, {
    this.responseHeaderTimeout = const Duration(seconds: 30),
    this.bodyIdleTimeout = const Duration(seconds: 45),
  });

  final http.Client _inner;
  final Duration responseHeaderTimeout;
  final Duration bodyIdleTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!c500G0Sources.any((source) => source.uri == request.url)) {
      throw StateError('G0_NETWORK_URI_NOT_PINNED');
    }
    if (responseHeaderTimeout <= Duration.zero ||
        bodyIdleTimeout <= Duration.zero) {
      throw StateError('G0_LAB_TIMEOUT_POLICY_INVALID');
    }
    request.followRedirects = false;
    final response = await _inner.send(request).timeout(
      responseHeaderTimeout,
      onTimeout: () => throw TimeoutException('G0_LAB_RESPONSE_HEADER_TIMEOUT'),
    );
    return http.StreamedResponse(
      response.stream.timeout(
        bodyIdleTimeout,
        onTimeout: (sink) =>
            sink.addError(TimeoutException('G0_LAB_BODY_IDLE_TIMEOUT')),
      ),
      response.statusCode,
      contentLength: response.contentLength,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  @override
  void close() => _inner.close();
}

/// Attempt each pinned period independently. A failure in the older file
/// must not hide the newer file's exact source or parser failure. This is
/// laboratory evidence only: partial acquisition never becomes award authority.
Future<Map<String, Object?>> acquireC500G0SourcesIndependently({
  required List<C500G0Source> sources,
  required Directory labDirectory,
  required http.Client client,
}) async {
  if (sources.isEmpty) {
    throw ArgumentError('G0_SOURCES_EMPTY');
  }
  final acquired = <Map<String, Object?>>[];
  final failures = <Map<String, Object?>>[];
  for (final source in sources) {
    try {
      acquired.add(await acquireC500G0Source(
        source: source,
        labDirectory: labDirectory,
        client: client,
      ));
    } catch (error) {
      failures.add(<String, Object?>{
        'period': source.period,
        'source_uri': source.uri.toString(),
        'failure': error.toString(),
        'verified_official_binary': false,
      });
    }
  }
  final allVerified = failures.isEmpty && acquired.length == sources.length;
  return <String, Object?>{
    'gate': allVerified
        ? 'C500_G0A_SOURCE_ACQUIRED_STRUCTURE_ONLY'
        : 'C500_G0A_HOLD_SOURCE_BINARY_UNAVAILABLE_OR_PIN_MISMATCH',
    'lab_directory': labDirectory.path,
    'sources': acquired,
    'failures': failures,
    'g0_root_cause': 'NOT_PROVEN',
    'android_engine_evidence': 'NOT_RUN',
    'global_negative_proof': 'NOT_RUN',
    'owner_production_authority': 'HOLD',
  };
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('G0_USAGE: dart run tool/c500_g0_acquire.dart');
    exitCode = 64;
    return;
  }
  // Unique system-temp directory, never production application storage.
  final directory = await Directory.systemTemp.createTemp('c500_g0_lab_');
  final client = C500G0PinnedNoRedirectClient(http.Client());
  try {
    final report = await acquireC500G0SourcesIndependently(
      sources: c500G0Sources,
      labDirectory: directory,
      client: client,
    );
    stdout.writeln(jsonEncode(report));
    if (report['gate'] != 'C500_G0A_SOURCE_ACQUIRED_STRUCTURE_ONLY') {
      exitCode = 2;
    }
  } catch (error) {
    stdout.writeln(jsonEncode(<String, Object?>{
      'gate': 'C500_G0A_HOLD_SOURCE_BINARY_UNAVAILABLE_OR_PIN_MISMATCH',
      'lab_directory': directory.path,
      'failure': error.toString(),
      'g0_root_cause': 'NOT_PROVEN',
      'owner_production_authority': 'HOLD',
    }));
    exitCode = 2;
  } finally {
    client.close();
  }
}
