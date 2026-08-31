import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'business_registry_distribution_manifest.dart';
import 'business_registry_nationwide_builder.dart';
import 'business_registry_pack.dart';

/// Opens a fresh externally-sorted source stream for each nationwide build pass.
///
/// The builder intentionally requires a replayable stream factory instead of an
/// in-memory Iterable so million-row production data is never retained solely
/// to support the mandatory two-pass authority check.
typedef BusinessRegistryNationwideSourceFactory =
    Stream<BusinessRegistryEntity> Function();

class BusinessRegistryNationwideArtifactResult {
  const BusinessRegistryNationwideArtifactResult({
    required this.outputFile,
    required this.manifest,
    required this.summary,
  });

  final File outputFile;
  final BusinessRegistryDistributionManifest manifest;
  final BusinessRegistryNationwideBuildSummary summary;
}

/// Produces the deterministic `gzip_ndjson_v1` nationwide distribution artifact.
///
/// Contract:
/// 1. First pass validates ordering/content and freezes entity count + content SHA.
/// 2. Second pass emits header + canonical entities while revalidating the frozen
///    summary, so source drift fails closed.
/// 3. The uncompressed NDJSON is compressed as a stream; neither pass buffers the
///    nationwide pack in memory.
/// 4. Compressed/uncompressed byte counts and compressed download SHA are measured
///    from the exact files and bound into a validated distribution manifest.
/// 5. Any failure removes task-owned temporary/partial files and preserves no
///    ambiguous artifact.
class BusinessRegistryNationwideArtifactBuilder {
  const BusinessRegistryNationwideArtifactBuilder();

  Future<BusinessRegistryNationwideArtifactResult> build({
    required BusinessRegistryNationwideSourceFactory openSource,
    required BusinessRegistryNationwideBuildMetadata metadata,
    required File outputFile,
    required Uri downloadUri,
    required String attribution,
    required Uri licenseUri,
  }) async {
    final metadataErrors = metadata.validate();
    if (metadataErrors.isNotEmpty) {
      throw FormatException(metadataErrors.join(','));
    }

    final outputParent = outputFile.parent;
    if (!await outputParent.exists()) {
      await outputParent.create(recursive: true);
    }

    final uncompressed = File('${outputFile.path}.ndjson.partial');
    final compressedPartial = File('${outputFile.path}.partial');

    await _deleteIfExists(uncompressed);
    await _deleteIfExists(compressedPartial);

    try {
      final first = BusinessRegistryNationwideBuildPass();
      await for (final entity in openSource()) {
        first.add(entity);
      }
      final summary = await first.close();

      final emitter = BusinessRegistryNationwideEmitPass(
        metadata: metadata,
        expectedSummary: summary,
      );
      final sink = uncompressed.openWrite(mode: FileMode.writeOnly);
      try {
        sink.write(emitter.headerLine);
        await for (final entity in openSource()) {
          sink.write(emitter.add(entity));
        }
        await emitter.close();
      } finally {
        await sink.flush();
        await sink.close();
      }

      final uncompressedSize = await uncompressed.length();
      if (uncompressedSize <= 0 ||
          uncompressedSize >
              BusinessRegistryDistributionManifest.maxUncompressedSizeBytes) {
        throw StateError('REGISTRY_BUILDER_UNCOMPRESSED_SIZE_INVALID');
      }

      final compressedSink = compressedPartial.openWrite(mode: FileMode.writeOnly);
      try {
        await gzip.encoder.bind(uncompressed.openRead()).pipe(compressedSink);
      } finally {
        await compressedSink.close();
      }

      final compressedSize = await compressedPartial.length();
      if (compressedSize <= 0 ||
          compressedSize >
              BusinessRegistryDistributionManifest.maxCompressedSizeBytes) {
        throw StateError('REGISTRY_BUILDER_COMPRESSED_SIZE_INVALID');
      }
      if (uncompressedSize < compressedSize) {
        throw StateError('REGISTRY_BUILDER_COMPRESSION_NOT_BOUNDED');
      }

      final downloadSha256 = await _sha256File(compressedPartial);
      final manifest = BusinessRegistryDistributionManifest(
        schemaVersion:
            BusinessRegistryDistributionManifest.currentSchemaVersion,
        registryVersion: metadata.registryVersion.trim(),
        sourceAuthority: metadata.sourceAuthority.trim(),
        sourceDataset: metadata.sourceDataset.trim(),
        sourceDataDate: metadata.sourceDataDate.trim(),
        coverage: BusinessRegistryPack.nationwideCoverage,
        format: BusinessRegistryDistributionFormat.gzipNdjsonV1,
        entityCount: summary.entityCount,
        downloadUri: downloadUri,
        downloadSha256: downloadSha256,
        registryContentSha256: summary.registryContentSha256,
        compressedSizeBytes: compressedSize,
        uncompressedSizeBytes: uncompressedSize,
        attribution: attribution.trim(),
        licenseUri: licenseUri,
      );
      final validation = manifest.validate();
      if (!validation.isValid) {
        throw FormatException(validation.errors.join(','));
      }

      await _deleteIfExists(outputFile);
      await compressedPartial.rename(outputFile.path);
      return BusinessRegistryNationwideArtifactResult(
        outputFile: outputFile,
        manifest: manifest,
        summary: summary,
      );
    } catch (_) {
      await _deleteIfExists(compressedPartial);
      await _deleteIfExists(outputFile);
      rethrow;
    } finally {
      await _deleteIfExists(uncompressed);
    }
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

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
