import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'business_registry_bounded_downloader.dart';
import 'business_registry_distribution_manifest.dart';
import 'business_registry_nationwide_builder.dart';
import 'business_registry_stream_pack.dart';

/// Validates one already-downloaded nationwide registry artifact without
/// loading the decompressed dataset into memory.
///
/// The validator binds the downloaded artifact back to the manifest, inflates
/// gzip bytes as a stream, enforces the exact uncompressed-size ceiling,
/// validates the single header against manifest authority, validates every
/// entity, requires canonical/sorted/unique entity lines, and recomputes the
/// registry-content SHA-256 over canonical entity payload bytes.
///
/// Any failure removes only [artifact.file]. The active installed registry and
/// user-owned merchant identity/history are intentionally outside this class.
class BusinessRegistryStreamValidator {
  const BusinessRegistryStreamValidator();

  Future<BusinessRegistryValidatedArtifact> validate({
    required BusinessRegistryDistributionManifest manifest,
    required BusinessRegistryDownloadedArtifact artifact,
  }) async {
    final manifestValidation = manifest.validate();
    if (!manifestValidation.isValid) {
      throw FormatException(manifestValidation.errors.join(','));
    }

    if (artifact.sizeBytes != manifest.compressedSizeBytes) {
      await _deleteIfExists(artifact.file);
      throw StateError('REGISTRY_VALIDATE_COMPRESSED_SIZE_MISMATCH');
    }
    if (artifact.sha256 != manifest.downloadSha256) {
      await _deleteIfExists(artifact.file);
      throw StateError('REGISTRY_VALIDATE_DOWNLOAD_SHA256_MISMATCH');
    }

    const parser = BusinessRegistryStreamPackParser();
    final contentHashSink = Sha256().newHashSink();
    var hashClosed = false;
    var uncompressedBytes = 0;
    var entityCount = 0;
    var sawHeader = false;
    String? lastEntityKey;

    try {
      final countedInflatedBytes = gzip.decoder
          .bind(artifact.file.openRead())
          .transform<List<int>>(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleData: (chunk, sink) {
                uncompressedBytes += chunk.length;
                if (uncompressedBytes > manifest.uncompressedSizeBytes ||
                    uncompressedBytes >
                        BusinessRegistryDistributionManifest
                            .maxUncompressedSizeBytes) {
                  sink.addError(
                    StateError('REGISTRY_VALIDATE_UNCOMPRESSED_SIZE_EXCEEDED'),
                  );
                  return;
                }
                sink.add(chunk);
              },
            ),
          );

      final lines = countedInflatedBytes
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        final record = parser.parseLine(line);
        switch (record) {
          case BusinessRegistryStreamHeaderRecord(:final header):
            if (sawHeader || entityCount != 0) {
              throw StateError('REGISTRY_VALIDATE_HEADER_POSITION_INVALID');
            }
            final headerErrors = header.validateAgainst(manifest);
            if (headerErrors.isNotEmpty) {
              throw FormatException(headerErrors.join(','));
            }
            sawHeader = true;

          case BusinessRegistryStreamEntityRecord(:final entity):
            if (!sawHeader) {
              throw StateError('REGISTRY_VALIDATE_HEADER_REQUIRED');
            }
            final entityErrors = parser.validateEntity(entity);
            if (entityErrors.isNotEmpty) {
              throw FormatException(entityErrors.join(','));
            }

            final canonicalLine =
                BusinessRegistryNationwideBuildPass.canonicalEntityLine(entity);
            if (canonicalLine != '$line\n') {
              throw StateError('REGISTRY_VALIDATE_ENTITY_NOT_CANONICAL');
            }

            final key =
                BusinessRegistryNationwideBuildPass.canonicalEntityKey(entity);
            final previous = lastEntityKey;
            if (previous != null) {
              final comparison = key.compareTo(previous);
              if (comparison < 0) {
                throw StateError('REGISTRY_VALIDATE_ENTITY_NOT_SORTED');
              }
              if (comparison == 0) {
                throw StateError('REGISTRY_VALIDATE_DUPLICATE_ENTITY_KEY');
              }
            }

            contentHashSink.add(utf8.encode(canonicalLine));
            lastEntityKey = key;
            entityCount += 1;
            if (entityCount > manifest.entityCount) {
              throw StateError('REGISTRY_VALIDATE_ENTITY_COUNT_EXCEEDED');
            }
        }
      }

      if (!sawHeader) {
        throw StateError('REGISTRY_VALIDATE_HEADER_REQUIRED');
      }
      if (uncompressedBytes != manifest.uncompressedSizeBytes) {
        throw StateError('REGISTRY_VALIDATE_UNCOMPRESSED_SIZE_MISMATCH');
      }
      if (entityCount != manifest.entityCount) {
        throw StateError('REGISTRY_VALIDATE_ENTITY_COUNT_MISMATCH');
      }

      contentHashSink.close();
      hashClosed = true;
      final hash = await contentHashSink.hash();
      final actualContentSha256 = hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actualContentSha256 != manifest.registryContentSha256) {
        throw StateError('REGISTRY_VALIDATE_CONTENT_SHA256_MISMATCH');
      }

      return BusinessRegistryValidatedArtifact(
        file: artifact.file,
        compressedSizeBytes: artifact.sizeBytes,
        uncompressedSizeBytes: uncompressedBytes,
        entityCount: entityCount,
        downloadSha256: artifact.sha256,
        registryContentSha256: actualContentSha256,
      );
    } catch (_) {
      if (!hashClosed) {
        contentHashSink.close();
      }
      await _deleteIfExists(artifact.file);
      rethrow;
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class BusinessRegistryValidatedArtifact {
  const BusinessRegistryValidatedArtifact({
    required this.file,
    required this.compressedSizeBytes,
    required this.uncompressedSizeBytes,
    required this.entityCount,
    required this.downloadSha256,
    required this.registryContentSha256,
  });

  final File file;
  final int compressedSizeBytes;
  final int uncompressedSizeBytes;
  final int entityCount;
  final String downloadSha256;
  final String registryContentSha256;
}
