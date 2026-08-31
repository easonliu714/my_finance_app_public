import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'business_registry_distribution_manifest.dart';

/// Downloads one validated nationwide registry artifact to a task-owned temp
/// file without buffering the payload in memory.
///
/// The downloader fails closed on manifest errors, non-200 responses,
/// Content-Length mismatches, byte-limit violations, exact compressed-size
/// drift, or SHA-256 mismatch. Any failure removes the task-owned temp file so
/// a later install step can never mistake partial bytes for an accepted pack.
class BusinessRegistryBoundedDownloader {
  const BusinessRegistryBoundedDownloader({required this.client});

  final http.Client client;

  Future<BusinessRegistryDownloadedArtifact> download({
    required BusinessRegistryDistributionManifest manifest,
    required File destinationTempFile,
  }) async {
    final validation = manifest.validate();
    if (!validation.isValid) {
      throw FormatException(validation.errors.join(','));
    }

    await _deleteIfExists(destinationTempFile);
    await destinationTempFile.parent.create(recursive: true);

    final request = http.Request('GET', manifest.downloadUri);
    http.StreamedResponse? response;
    IOSink? output;
    final hashSink = Sha256().newHashSink();
    var bytesWritten = 0;

    try {
      response = await client.send(request);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'REGISTRY_DOWNLOAD_HTTP_STATUS_${response.statusCode}',
          uri: manifest.downloadUri,
        );
      }

      final declaredLength = response.contentLength;
      if (declaredLength != null &&
          declaredLength != manifest.compressedSizeBytes) {
        throw StateError('REGISTRY_DOWNLOAD_CONTENT_LENGTH_MISMATCH');
      }

      output = destinationTempFile.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in response.stream) {
        bytesWritten += chunk.length;
        if (bytesWritten > manifest.compressedSizeBytes ||
            bytesWritten >
                BusinessRegistryDistributionManifest.maxCompressedSizeBytes) {
          throw StateError('REGISTRY_DOWNLOAD_COMPRESSED_SIZE_EXCEEDED');
        }
        output.add(chunk);
        hashSink.add(chunk);
      }
      await output.flush();
      await output.close();
      output = null;

      if (bytesWritten != manifest.compressedSizeBytes) {
        throw StateError('REGISTRY_DOWNLOAD_COMPRESSED_SIZE_MISMATCH');
      }

      hashSink.close();
      final hash = await hashSink.hash();
      final actualSha256 = hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actualSha256 != manifest.downloadSha256) {
        throw StateError('REGISTRY_DOWNLOAD_SHA256_MISMATCH');
      }

      return BusinessRegistryDownloadedArtifact(
        file: destinationTempFile,
        sizeBytes: bytesWritten,
        sha256: actualSha256,
      );
    } catch (_) {
      try {
        await output?.close();
      } catch (_) {
        // Best-effort close; the authoritative failure remains the first one.
      }
      await _deleteIfExists(destinationTempFile);
      rethrow;
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class BusinessRegistryDownloadedArtifact {
  const BusinessRegistryDownloadedArtifact({
    required this.file,
    required this.sizeBytes,
    required this.sha256,
  });

  final File file;
  final int sizeBytes;
  final String sha256;
}
