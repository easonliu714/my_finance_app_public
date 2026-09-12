import 'dart:convert';

import 'business_registry_distribution_manifest.dart';

/// Deterministic wire codec for nationwide registry distribution manifests.
///
/// Field order is intentionally fixed so identical authority inputs produce
/// byte-identical JSON suitable for release hashing and provenance evidence.
extension BusinessRegistryDistributionManifestCodec
    on BusinessRegistryDistributionManifest {
  Map<String, Object> toCanonicalJson() => <String, Object>{
        'schema_version': schemaVersion,
        'registry_version': registryVersion.trim(),
        'source_authority': sourceAuthority.trim(),
        'source_dataset': sourceDataset.trim(),
        'source_data_date': sourceDataDate.trim(),
        'coverage': coverage,
        'format': format.wireName,
        'entity_count': entityCount,
        'download_url': downloadUri.toString(),
        'download_sha256': downloadSha256.toLowerCase(),
        'registry_content_sha256': registryContentSha256.toLowerCase(),
        'compressed_size_bytes': compressedSizeBytes,
        'uncompressed_size_bytes': uncompressedSizeBytes,
        'attribution': attribution.trim(),
        'license_url': licenseUri.toString(),
      };

  String toCanonicalJsonText() => jsonEncode(toCanonicalJson());
}
