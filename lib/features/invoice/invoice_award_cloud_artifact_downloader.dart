import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'invoice_award_cloud_publication_parser.dart';

typedef CloudAwardArtifactDownloadProgressCallback = void Function(
  CloudAwardArtifactDownloadProgress progress,
);

class CloudAwardArtifactDownloadProgress {
  const CloudAwardArtifactDownloadProgress({
    required this.downloadedBytes,
    required this.declaredBytes,
    required this.bytesPerSecond,
  });

  final int downloadedBytes;
  final int? declaredBytes;
  final double bytesPerSecond;

  double? get fraction => declaredBytes == null || declaredBytes! <= 0
      ? null
      : (downloadedBytes / declaredBytes!).clamp(0.0, 1.0).toDouble();
}

class OfficialCloudAwardDownloadedArtifact {
  const OfficialCloudAwardDownloadedArtifact({
    required this.reference,
    required this.file,
    required this.sizeBytes,
    required this.sha256,
  });

  final OfficialCloudAwardArtifactReference reference;
  final File file;
  final int sizeBytes;
  final String sha256;
}

/// Bounded streaming download for public MOF cloud-exclusive sorted PDFs.
///
/// The publication page does not publish an independent SHA-256 before
/// download. Therefore this gate verifies exact source authority, HTTP/PDF
/// shape and size while streaming, then records the exact downloaded-byte
/// SHA-256 for LKG provenance and future unchanged-artifact reuse.
class MinistryOfFinanceCloudAwardArtifactDownloader {
  const MinistryOfFinanceCloudAwardArtifactDownloader({
    required this.client,
    this.maxArtifactBytes = 256 * 1024 * 1024,
    this.minArtifactBytes = 64,
  });

  final http.Client client;
  final int maxArtifactBytes;
  final int minArtifactBytes;

  Future<OfficialCloudAwardDownloadedArtifact> download({
    required OfficialCloudAwardArtifactReference reference,
    required File destinationTempFile,
    Object? cancellation,
    CloudAwardArtifactDownloadProgressCallback? onProgress,
  }) async {
    // The foreground lifecycle cancellation token is accepted here so the
    // acquisition boundary remains compatible with lifecycle-governed callers.
    // Native PDFium cancellation is enforced separately by the candidate lookup;
    // an interrupted HTTP stream is never promoted until the full PDF gates pass.
    if (!reference.isApprovedOfficialSource) {
      await _deleteIfExists(destinationTempFile);
      throw StateError('CLOUD_AWARD_ARTIFACT_SOURCE_NOT_ALLOWED');
    }
    if (maxArtifactBytes < minArtifactBytes || minArtifactBytes < 5) {
      throw StateError('CLOUD_AWARD_ARTIFACT_SIZE_POLICY_INVALID');
    }

    await destinationTempFile.parent.create(recursive: true);
    await _deleteIfExists(destinationTempFile);

    final request = http.Request('GET', reference.sourceUri);
    request.headers[HttpHeaders.acceptHeader] = 'application/pdf';
    final response = await client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'CLOUD_AWARD_ARTIFACT_HTTP_STATUS_${response.statusCode}',
        uri: reference.sourceUri,
      );
    }

    final declared = response.contentLength;
    if (declared != null &&
        (declared < minArtifactBytes || declared > maxArtifactBytes)) {
      throw StateError('CLOUD_AWARD_ARTIFACT_CONTENT_LENGTH_INVALID');
    }

    final contentType = response.headers[HttpHeaders.contentTypeHeader];
    if (contentType != null &&
        !contentType.toLowerCase().contains('application/pdf')) {
      throw StateError('CLOUD_AWARD_ARTIFACT_CONTENT_TYPE_INVALID');
    }

    final sink = Sha256().newHashSink();
    IOSink? output;
    var downloaded = 0;
    final prefix = <int>[];
    final startedAt = DateTime.now();
    var lastProgressAt = startedAt;
    var lastProgressBytes = 0;

    try {
      output = destinationTempFile.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in response.stream) {
        if (prefix.length < 5) {
          final take = (5 - prefix.length).clamp(0, chunk.length);
          prefix.addAll(chunk.take(take));
        }

        downloaded += chunk.length;
        if (downloaded > maxArtifactBytes) {
          throw StateError('CLOUD_AWARD_ARTIFACT_SIZE_EXCEEDED');
        }

        sink.add(chunk);
        output.add(chunk);

        final now = DateTime.now();
        final elapsed = now.difference(lastProgressAt);
        if (elapsed >= const Duration(milliseconds: 250)) {
          final seconds =
              elapsed.inMicroseconds / Duration.microsecondsPerSecond;
          final delta = downloaded - lastProgressBytes;
          onProgress?.call(
            CloudAwardArtifactDownloadProgress(
              downloadedBytes: downloaded,
              declaredBytes: declared,
              bytesPerSecond: seconds > 0 ? delta / seconds : 0,
            ),
          );
          lastProgressAt = now;
          lastProgressBytes = downloaded;
        }
      }

      await output.flush();
      await output.close();
      output = null;
      sink.close();

      if (downloaded < minArtifactBytes) {
        throw StateError('CLOUD_AWARD_ARTIFACT_TOO_SMALL');
      }
      if (declared != null && downloaded != declared) {
        throw StateError('CLOUD_AWARD_ARTIFACT_LENGTH_MISMATCH');
      }
      if (prefix.length < 5 ||
          String.fromCharCodes(prefix.take(5)) != '%PDF-') {
        throw StateError('CLOUD_AWARD_ARTIFACT_PDF_MAGIC_INVALID');
      }

      final hash = await sink.hash();
      final sha256 = hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      onProgress?.call(
        CloudAwardArtifactDownloadProgress(
          downloadedBytes: downloaded,
          declaredBytes: declared,
          bytesPerSecond: 0,
        ),
      );

      return OfficialCloudAwardDownloadedArtifact(
        reference: reference,
        file: destinationTempFile,
        sizeBytes: downloaded,
        sha256: sha256,
      );
    } catch (_) {
      try {
        await output?.flush();
        await output?.close();
      } catch (_) {}
      sink.close();
      await _deleteIfExists(destinationTempFile);
      rethrow;
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}
