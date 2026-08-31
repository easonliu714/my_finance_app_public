import 'dart:convert';

import 'business_registry_pack.dart';

enum BusinessRegistryDistributionFormat {
  gzipNdjsonV1('gzip_ndjson_v1');

  const BusinessRegistryDistributionFormat(this.wireName);
  final String wireName;

  static BusinessRegistryDistributionFormat parse(String value) {
    return values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => throw FormatException(
        'Unsupported business registry distribution format: $value',
      ),
    );
  }
}

class BusinessRegistryDistributionManifest {
  const BusinessRegistryDistributionManifest({
    required this.schemaVersion,
    required this.registryVersion,
    required this.sourceAuthority,
    required this.sourceDataset,
    required this.sourceDataDate,
    required this.coverage,
    required this.format,
    required this.entityCount,
    required this.downloadUri,
    required this.downloadSha256,
    required this.registryContentSha256,
    required this.compressedSizeBytes,
    required this.uncompressedSizeBytes,
    required this.attribution,
    required this.licenseUri,
  });

  static const int currentSchemaVersion = 1;
  static const int maxCompressedSizeBytes = 256 * 1024 * 1024;
  static const int maxUncompressedSizeBytes = 1024 * 1024 * 1024;

  static const Set<String> allowedDistributionHosts = <String>{
    'github.com',
    'raw.githubusercontent.com',
  };

  final int schemaVersion;
  final String registryVersion;
  final String sourceAuthority;
  final String sourceDataset;
  final String sourceDataDate;
  final String coverage;
  final BusinessRegistryDistributionFormat format;
  final int entityCount;
  final Uri downloadUri;
  final String downloadSha256;
  final String registryContentSha256;
  final int compressedSizeBytes;
  final int uncompressedSizeBytes;
  final String attribution;
  final Uri licenseUri;

  factory BusinessRegistryDistributionManifest.fromJson(
    Map<String, Object?> json,
  ) {
    final downloadUrl = json['download_url']?.toString() ?? '';
    final licenseUrl = json['license_url']?.toString() ?? '';
    return BusinessRegistryDistributionManifest(
      schemaVersion: _asInt(json['schema_version']),
      registryVersion: json['registry_version']?.toString() ?? '',
      sourceAuthority: json['source_authority']?.toString() ?? '',
      sourceDataset: json['source_dataset']?.toString() ?? '',
      sourceDataDate: json['source_data_date']?.toString() ?? '',
      coverage: json['coverage']?.toString() ?? '',
      format: BusinessRegistryDistributionFormat.parse(
        json['format']?.toString() ?? '',
      ),
      entityCount: _asInt(json['entity_count']),
      downloadUri: Uri.tryParse(downloadUrl) ?? Uri(),
      downloadSha256:
          (json['download_sha256']?.toString() ?? '').toLowerCase(),
      registryContentSha256:
          (json['registry_content_sha256']?.toString() ?? '').toLowerCase(),
      compressedSizeBytes: _asInt(json['compressed_size_bytes']),
      uncompressedSizeBytes: _asInt(json['uncompressed_size_bytes']),
      attribution: json['attribution']?.toString() ?? '',
      licenseUri: Uri.tryParse(licenseUrl) ?? Uri(),
    );
  }

  factory BusinessRegistryDistributionManifest.fromJsonText(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException(
        'Business registry distribution manifest root must be an object',
      );
    }
    return BusinessRegistryDistributionManifest.fromJson(
      Map<String, Object?>.from(decoded),
    );
  }

  BusinessRegistryDistributionManifestValidation validate() {
    final errors = <String>[];
    if (schemaVersion != currentSchemaVersion) {
      errors.add('REGISTRY_DISTRIBUTION_SCHEMA_UNSUPPORTED');
    }
    if (registryVersion.trim().isEmpty) {
      errors.add('REGISTRY_DISTRIBUTION_VERSION_REQUIRED');
    }
    if (!BusinessRegistryPack.allowedSourceAuthorities
        .contains(sourceAuthority.trim())) {
      errors.add('REGISTRY_DISTRIBUTION_SOURCE_AUTHORITY_NOT_ALLOWED');
    }
    if (sourceDataset.trim().isEmpty) {
      errors.add('REGISTRY_DISTRIBUTION_SOURCE_DATASET_REQUIRED');
    }
    if (coverage != BusinessRegistryPack.nationwideCoverage) {
      errors.add('REGISTRY_DISTRIBUTION_MUST_BE_NATIONWIDE');
    }
    final parsedDataDate = DateTime.tryParse(sourceDataDate.trim());
    if (parsedDataDate == null) {
      errors.add('REGISTRY_DISTRIBUTION_SOURCE_DATA_DATE_INVALID');
    }
    if (entityCount <= 0) {
      errors.add('REGISTRY_DISTRIBUTION_ENTITY_COUNT_INVALID');
    }
    if (downloadUri.scheme != 'https' ||
        !allowedDistributionHosts.contains(downloadUri.host)) {
      errors.add('REGISTRY_DISTRIBUTION_DOWNLOAD_URL_NOT_ALLOWED');
    }
    if (downloadUri.host == 'github.com' &&
        !downloadUri.path.startsWith(
          '/easonliu714/my_finance_app_public/releases/download/',
        )) {
      errors.add('REGISTRY_DISTRIBUTION_GITHUB_PATH_NOT_ALLOWED');
    }
    if (downloadUri.host == 'raw.githubusercontent.com' &&
        !downloadUri.path.startsWith(
          '/easonliu714/my_finance_app_public/',
        )) {
      errors.add('REGISTRY_DISTRIBUTION_GITHUB_PATH_NOT_ALLOWED');
    }
    if (!_isSha256(downloadSha256)) {
      errors.add('REGISTRY_DISTRIBUTION_DOWNLOAD_SHA256_INVALID');
    }
    if (!_isSha256(registryContentSha256)) {
      errors.add('REGISTRY_DISTRIBUTION_CONTENT_SHA256_INVALID');
    }
    if (compressedSizeBytes <= 0 ||
        compressedSizeBytes > maxCompressedSizeBytes) {
      errors.add('REGISTRY_DISTRIBUTION_COMPRESSED_SIZE_INVALID');
    }
    if (uncompressedSizeBytes <= 0 ||
        uncompressedSizeBytes > maxUncompressedSizeBytes ||
        uncompressedSizeBytes < compressedSizeBytes) {
      errors.add('REGISTRY_DISTRIBUTION_UNCOMPRESSED_SIZE_INVALID');
    }
    if (attribution.trim().isEmpty) {
      errors.add('REGISTRY_DISTRIBUTION_ATTRIBUTION_REQUIRED');
    }
    if (licenseUri.scheme != 'https' || licenseUri.host != 'data.gov.tw') {
      errors.add('REGISTRY_DISTRIBUTION_LICENSE_URL_INVALID');
    }
    return BusinessRegistryDistributionManifestValidation(
      isValid: errors.isEmpty,
      errors: List<String>.unmodifiable(errors.toSet()),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  static bool _isSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

class BusinessRegistryDistributionManifestValidation {
  const BusinessRegistryDistributionManifestValidation({
    required this.isValid,
    required this.errors,
  });

  final bool isValid;
  final List<String> errors;
}
