import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'business_registry_distribution_manifest.dart';

typedef BusinessRegistryDownloadProgressCallback = void Function(
  BusinessRegistryDownloadProgress progress,
);

class BusinessRegistryDownloadProgress {
  const BusinessRegistryDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.attempt,
    required this.resumedFromBytes,
    required this.bytesPerSecond,
    required this.eta,
  });

  final int downloadedBytes;
  final int totalBytes;
  final int attempt;
  final int resumedFromBytes;
  final double bytesPerSecond;
  final Duration? eta;

  double get fraction => totalBytes <= 0
      ? 0
      : (downloadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
}

/// Downloads one validated nationwide registry artifact to a stable task-owned
/// partial file without buffering the payload in memory.
///
/// Transient transport failures retain already-flushed bytes and retry with a
/// validated HTTP Range request. Integrity/protocol failures remain fail-closed
/// and delete the partial file so unverified bytes can never reach install.
class BusinessRegistryBoundedDownloader {
  const BusinessRegistryBoundedDownloader({
    required this.client,
    this.maxAttempts = 3,
    this.retryBackoff = const Duration(seconds: 2),
    this.delay = Future<void>.delayed,
  });

  final http.Client client;
  final int maxAttempts;
  final Duration retryBackoff;
  final Future<void> Function(Duration) delay;

  Future<BusinessRegistryDownloadedArtifact> download({
    required BusinessRegistryDistributionManifest manifest,
    required File destinationTempFile,
    BusinessRegistryDownloadProgressCallback? onProgress,
  }) async {
    final validation = manifest.validate();
    if (!validation.isValid) {
      await _deleteIfExists(destinationTempFile);
      throw FormatException(validation.errors.join(','));
    }
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be >= 1');
    }

    await destinationTempFile.parent.create(recursive: true);
    var existing = await _existingPartialSize(destinationTempFile);
    if (existing < 0 || existing > manifest.compressedSizeBytes) {
      await _deleteIfExists(destinationTempFile);
      throw StateError('REGISTRY_DOWNLOAD_PARTIAL_SIZE_INVALID');
    }
    if (existing == manifest.compressedSizeBytes && existing > 0) {
      return _verifyCompletedArtifact(
        manifest: manifest,
        destinationTempFile: destinationTempFile,
        onProgress: onProgress,
        attempt: 0,
        resumedFromBytes: existing,
      );
    }

    Object? lastTransientError;
    StackTrace? lastTransientStack;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      existing = await _existingPartialSize(destinationTempFile);
      if (existing < 0 || existing >= manifest.compressedSizeBytes) {
        await _deleteIfExists(destinationTempFile);
        throw StateError('REGISTRY_DOWNLOAD_PARTIAL_SIZE_INVALID');
      }
      try {
        await _downloadAttempt(
          manifest: manifest,
          destinationTempFile: destinationTempFile,
          existingBytes: existing,
          attempt: attempt,
          onProgress: onProgress,
        );
        return await _verifyCompletedArtifact(
          manifest: manifest,
          destinationTempFile: destinationTempFile,
          onProgress: onProgress,
          attempt: attempt,
          resumedFromBytes: existing,
        );
      } catch (error, stackTrace) {
        if (!_isTransientTransportError(error)) {
          await _deleteIfExists(destinationTempFile);
          rethrow;
        }
        lastTransientError = error;
        lastTransientStack = stackTrace;
        final retained = await _existingPartialSize(destinationTempFile);
        if (retained < 0 || retained > manifest.compressedSizeBytes) {
          await _deleteIfExists(destinationTempFile);
          throw StateError('REGISTRY_DOWNLOAD_PARTIAL_SIZE_INVALID');
        }
        if (attempt >= maxAttempts) break;
        if (retryBackoff > Duration.zero) {
          await delay(retryBackoff * attempt);
        }
      }
    }

    Error.throwWithStackTrace(
      BusinessRegistryTransientDownloadException(
        retainedBytes: await _existingPartialSize(destinationTempFile),
        cause: lastTransientError,
      ),
      lastTransientStack ?? StackTrace.current,
    );
  }

  Future<void> _downloadAttempt({
    required BusinessRegistryDistributionManifest manifest,
    required File destinationTempFile,
    required int existingBytes,
    required int attempt,
    required BusinessRegistryDownloadProgressCallback? onProgress,
  }) async {
    final request = http.Request('GET', manifest.downloadUri);
    if (existingBytes > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$existingBytes-';
    }

    final response = await client.send(request);
    var writeOffset = existingBytes;
    var append = existingBytes > 0;

    if (existingBytes == 0) {
      if (response.statusCode != HttpStatus.ok) {
        throw _HttpStatusFailure(response.statusCode, manifest.downloadUri);
      }
      _validateFullResponseLength(response, manifest);
    } else if (response.statusCode == HttpStatus.partialContent) {
      _validateContentRange(
        response: response,
        expectedStart: existingBytes,
        expectedTotal: manifest.compressedSizeBytes,
      );
      final expectedRemaining = manifest.compressedSizeBytes - existingBytes;
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength != expectedRemaining) {
        throw StateError('REGISTRY_DOWNLOAD_RANGE_LENGTH_MISMATCH');
      }
    } else if (response.statusCode == HttpStatus.ok) {
      // Range ignored: restart safely from zero rather than appending a full
      // response to the retained prefix.
      append = false;
      writeOffset = 0;
      _validateFullResponseLength(response, manifest);
    } else {
      throw _HttpStatusFailure(response.statusCode, manifest.downloadUri);
    }

    IOSink? output;
    final startedAt = DateTime.now();
    var lastProgressAt = startedAt;
    var lastProgressBytes = writeOffset;
    try {
      output = destinationTempFile.openWrite(
        mode: append ? FileMode.append : FileMode.writeOnly,
      );
      var bytesWritten = writeOffset;
      onProgress?.call(
        BusinessRegistryDownloadProgress(
          downloadedBytes: bytesWritten,
          totalBytes: manifest.compressedSizeBytes,
          attempt: attempt,
          resumedFromBytes: existingBytes,
          bytesPerSecond: 0,
          eta: null,
        ),
      );

      await for (final chunk in response.stream) {
        bytesWritten += chunk.length;
        if (bytesWritten > manifest.compressedSizeBytes ||
            bytesWritten >
                BusinessRegistryDistributionManifest.maxCompressedSizeBytes) {
          throw StateError('REGISTRY_DOWNLOAD_COMPRESSED_SIZE_EXCEEDED');
        }
        output.add(chunk);

        final now = DateTime.now();
        final elapsed = now.difference(lastProgressAt);
        if (elapsed >= const Duration(milliseconds: 250) ||
            bytesWritten == manifest.compressedSizeBytes) {
          final deltaBytes = bytesWritten - lastProgressBytes;
          final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
          final speed = seconds > 0 ? deltaBytes / seconds : 0.0;
          final remaining = manifest.compressedSizeBytes - bytesWritten;
          final eta = speed > 0
              ? Duration(milliseconds: ((remaining / speed) * 1000).ceil())
              : null;
          onProgress?.call(
            BusinessRegistryDownloadProgress(
              downloadedBytes: bytesWritten,
              totalBytes: manifest.compressedSizeBytes,
              attempt: attempt,
              resumedFromBytes: existingBytes,
              bytesPerSecond: speed < 0 ? 0 : speed,
              eta: eta != null && eta.isNegative ? Duration.zero : eta,
            ),
          );
          lastProgressAt = now;
          lastProgressBytes = bytesWritten;
        }
      }
      await output.flush();
      await output.close();
      output = null;
    } catch (_) {
      try {
        await output?.flush();
        await output?.close();
      } catch (_) {
        // Preserve the original failure. Best-effort flush still maximizes the
        // amount available to resume after a transient disconnect.
      }
      rethrow;
    }
  }

  static void _validateFullResponseLength(
    http.StreamedResponse response,
    BusinessRegistryDistributionManifest manifest,
  ) {
    final declaredLength = response.contentLength;
    if (declaredLength != null &&
        declaredLength != manifest.compressedSizeBytes) {
      throw StateError('REGISTRY_DOWNLOAD_CONTENT_LENGTH_MISMATCH');
    }
  }

  static void _validateContentRange({
    required http.StreamedResponse response,
    required int expectedStart,
    required int expectedTotal,
  }) {
    final value = response.headers[HttpHeaders.contentRangeHeader];
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) {
      throw StateError('REGISTRY_DOWNLOAD_CONTENT_RANGE_INVALID');
    }
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    final total = int.parse(match.group(3)!);
    if (start != expectedStart || total != expectedTotal || end < start) {
      throw StateError('REGISTRY_DOWNLOAD_CONTENT_RANGE_MISMATCH');
    }
  }

  Future<BusinessRegistryDownloadedArtifact> _verifyCompletedArtifact({
    required BusinessRegistryDistributionManifest manifest,
    required File destinationTempFile,
    required BusinessRegistryDownloadProgressCallback? onProgress,
    required int attempt,
    required int resumedFromBytes,
  }) async {
    final size = await _existingPartialSize(destinationTempFile);
    if (size != manifest.compressedSizeBytes) {
      throw StateError('REGISTRY_DOWNLOAD_COMPRESSED_SIZE_MISMATCH');
    }
    final actualSha256 = await _sha256File(destinationTempFile);
    if (actualSha256 != manifest.downloadSha256) {
      await _deleteIfExists(destinationTempFile);
      throw StateError('REGISTRY_DOWNLOAD_SHA256_MISMATCH');
    }
    onProgress?.call(
      BusinessRegistryDownloadProgress(
        downloadedBytes: size,
        totalBytes: manifest.compressedSizeBytes,
        attempt: attempt,
        resumedFromBytes: resumedFromBytes,
        bytesPerSecond: 0,
        eta: Duration.zero,
      ),
    );
    return BusinessRegistryDownloadedArtifact(
      file: destinationTempFile,
      sizeBytes: size,
      sha256: actualSha256,
    );
  }

  static Future<String> _sha256File(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static bool _isTransientTransportError(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;

  static Future<int> _existingPartialSize(File file) async {
    if (!await file.exists()) return 0;
    return file.length();
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _HttpStatusFailure extends HttpException {
  _HttpStatusFailure(int statusCode, Uri uri)
      : super('REGISTRY_DOWNLOAD_HTTP_STATUS_$statusCode', uri: uri);
}

class BusinessRegistryTransientDownloadException implements Exception {
  const BusinessRegistryTransientDownloadException({
    required this.retainedBytes,
    this.cause,
  });

  final int retainedBytes;
  final Object? cause;

  @override
  String toString() =>
      'REGISTRY_DOWNLOAD_TRANSIENT_FAILURE(retainedBytes=$retainedBytes)';
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
