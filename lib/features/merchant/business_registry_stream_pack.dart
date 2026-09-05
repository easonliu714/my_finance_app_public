import 'dart:convert';

import 'business_registry_distribution_manifest.dart';
import 'business_registry_pack.dart';

enum BusinessRegistryStreamRecordType { header, entity }

class BusinessRegistryStreamHeader {
  const BusinessRegistryStreamHeader({
    required this.registryVersion,
    required this.sourceAuthority,
    required this.sourceDataset,
    required this.sourceDataDate,
    required this.coverage,
    required this.entityCount,
    required this.registryContentSha256,
  });

  final String registryVersion;
  final String sourceAuthority;
  final String sourceDataset;
  final String sourceDataDate;
  final String coverage;
  final int entityCount;
  final String registryContentSha256;

  factory BusinessRegistryStreamHeader.fromJson(Map<String, Object?> json) {
    return BusinessRegistryStreamHeader(
      registryVersion: json['registry_version']?.toString() ?? '',
      sourceAuthority: json['source_authority']?.toString() ?? '',
      sourceDataset: json['source_dataset']?.toString() ?? '',
      sourceDataDate: json['source_data_date']?.toString() ?? '',
      coverage: json['coverage']?.toString() ?? '',
      entityCount: _asInt(json['entity_count']),
      registryContentSha256:
          (json['registry_content_sha256']?.toString() ?? '').toLowerCase(),
    );
  }

  List<String> validateAgainst(
    BusinessRegistryDistributionManifest manifest,
  ) {
    final errors = <String>[];
    if (registryVersion != manifest.registryVersion) {
      errors.add('REGISTRY_STREAM_VERSION_MISMATCH');
    }
    if (sourceAuthority != manifest.sourceAuthority) {
      errors.add('REGISTRY_STREAM_SOURCE_AUTHORITY_MISMATCH');
    }
    if (sourceDataset != manifest.sourceDataset) {
      errors.add('REGISTRY_STREAM_SOURCE_DATASET_MISMATCH');
    }
    if (sourceDataDate != manifest.sourceDataDate) {
      errors.add('REGISTRY_STREAM_SOURCE_DATA_DATE_MISMATCH');
    }
    if (coverage != manifest.coverage) {
      errors.add('REGISTRY_STREAM_COVERAGE_MISMATCH');
    }
    if (entityCount != manifest.entityCount) {
      errors.add('REGISTRY_STREAM_ENTITY_COUNT_MISMATCH');
    }
    if (registryContentSha256 != manifest.registryContentSha256) {
      errors.add('REGISTRY_STREAM_CONTENT_SHA256_MISMATCH');
    }
    return List<String>.unmodifiable(errors);
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }
}

sealed class BusinessRegistryStreamRecord {
  const BusinessRegistryStreamRecord();
  BusinessRegistryStreamRecordType get type;
}

class BusinessRegistryStreamHeaderRecord extends BusinessRegistryStreamRecord {
  const BusinessRegistryStreamHeaderRecord(this.header);

  final BusinessRegistryStreamHeader header;

  @override
  BusinessRegistryStreamRecordType get type =>
      BusinessRegistryStreamRecordType.header;
}

class BusinessRegistryStreamEntityRecord extends BusinessRegistryStreamRecord {
  const BusinessRegistryStreamEntityRecord(this.entity);

  final BusinessRegistryEntity entity;

  @override
  BusinessRegistryStreamRecordType get type =>
      BusinessRegistryStreamRecordType.entity;
}

class BusinessRegistryStreamPackParser {
  const BusinessRegistryStreamPackParser();

  BusinessRegistryStreamRecord parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Business registry stream line is empty');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException(
        'Business registry stream line must be a JSON object',
      );
    }
    final json = Map<String, Object?>.from(decoded);
    final recordType = json['record_type']?.toString() ?? '';
    switch (recordType) {
      case 'header':
        return BusinessRegistryStreamHeaderRecord(
          BusinessRegistryStreamHeader.fromJson(json),
        );
      case 'entity':
        return BusinessRegistryStreamEntityRecord(
          BusinessRegistryEntity.fromJson(json),
        );
      default:
        throw FormatException(
          'Unsupported business registry stream record_type: $recordType',
        );
    }
  }

  List<String> validateEntity(BusinessRegistryEntity entity) {
    final errors = <String>[];
    if (!RegExp(r'^\d{8}$').hasMatch(entity.sellerIdentifier)) {
      errors.add('REGISTRY_STREAM_SELLER_IDENTIFIER_INVALID');
    }
    if (entity.legalName.trim().isEmpty) {
      errors.add('REGISTRY_STREAM_LEGAL_NAME_REQUIRED');
    }
    if (entity.sourceDataset.trim().isEmpty) {
      errors.add('REGISTRY_STREAM_ENTITY_SOURCE_REQUIRED');
    }
    if (entity.parentSellerIdentifier.isNotEmpty &&
        !RegExp(r'^\d{8}$').hasMatch(entity.parentSellerIdentifier)) {
      errors.add('REGISTRY_STREAM_PARENT_IDENTIFIER_INVALID');
    }
    return List<String>.unmodifiable(errors);
  }
}
