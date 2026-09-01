import 'dart:convert';

import 'package:cryptography/cryptography.dart';

enum BusinessRegistryEntityType { company, business, branch }

class BusinessRegistryEntity {
  const BusinessRegistryEntity({
    required this.sellerIdentifier,
    required this.entityType,
    required this.legalName,
    required this.sourceDataset,
    this.registrationStatus = '',
    this.parentSellerIdentifier = '',
  });

  final String sellerIdentifier;
  final BusinessRegistryEntityType entityType;
  final String legalName;
  final String registrationStatus;
  final String parentSellerIdentifier;
  final String sourceDataset;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
        'seller_identifier': sellerIdentifier,
        'entity_type': entityType.name,
        'legal_name': legalName,
        'registration_status': registrationStatus,
        'parent_seller_identifier': parentSellerIdentifier,
        'source_dataset': sourceDataset,
      };

  factory BusinessRegistryEntity.fromJson(Map<String, Object?> json) {
    final typeName = json['entity_type']?.toString() ?? '';
    return BusinessRegistryEntity(
      sellerIdentifier: json['seller_identifier']?.toString() ?? '',
      entityType: BusinessRegistryEntityType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => throw FormatException(
          'Unsupported business registry entity_type: $typeName',
        ),
      ),
      legalName: json['legal_name']?.toString() ?? '',
      registrationStatus: json['registration_status']?.toString() ?? '',
      parentSellerIdentifier:
          json['parent_seller_identifier']?.toString() ?? '',
      sourceDataset: json['source_dataset']?.toString() ?? '',
    );
  }
}

class BusinessRegistryPack {
  const BusinessRegistryPack({
    required this.version,
    required this.sourceAuthority,
    required this.sourceDataset,
    required this.sourceDataDate,
    required this.coverage,
    required this.contentSha256,
    required this.entities,
  });

  static const Set<String> allowedSourceAuthorities = <String>{
    'MOEA_BUSINESS_ADMINISTRATION_GCIS',
    'MOEA_BUSINESS_ADMINISTRATION_GCIS_PUBLIC_REPORT',
  };

  static const String nationwideCoverage = 'taiwan_nationwide';
  static const String validationSubsetCoverage = 'validation_subset';

  final String version;
  final String sourceAuthority;
  final String sourceDataset;
  final String sourceDataDate;
  final String coverage;
  final String contentSha256;
  final List<BusinessRegistryEntity> entities;

  bool get isValidationSubset => coverage == validationSubsetCoverage;
  bool get isNationwide => coverage == nationwideCoverage;

  factory BusinessRegistryPack.fromJson(Map<String, Object?> json) {
    final rawEntities = json['entities'];
    if (rawEntities is! List) {
      throw const FormatException('Business registry pack entities must be a list');
    }
    return BusinessRegistryPack(
      version: json['version']?.toString() ?? '',
      sourceAuthority: json['source_authority']?.toString() ?? '',
      sourceDataset: json['source_dataset']?.toString() ?? '',
      sourceDataDate: json['source_data_date']?.toString() ?? '',
      coverage: json['coverage']?.toString() ?? '',
      contentSha256: json['content_sha256']?.toString().toLowerCase() ?? '',
      entities: List<BusinessRegistryEntity>.unmodifiable(
        rawEntities.map((raw) {
          if (raw is! Map) {
            throw const FormatException(
              'Business registry entity must be an object',
            );
          }
          return BusinessRegistryEntity.fromJson(
            Map<String, Object?>.from(raw),
          );
        }),
      ),
    );
  }

  factory BusinessRegistryPack.fromJsonText(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Business registry pack root must be an object');
    }
    return BusinessRegistryPack.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<BusinessRegistryPackValidation> validate() async {
    final errors = <String>[];
    if (version.trim().isEmpty) errors.add('REGISTRY_VERSION_REQUIRED');
    if (!allowedSourceAuthorities.contains(sourceAuthority.trim())) {
      errors.add('REGISTRY_SOURCE_AUTHORITY_NOT_ALLOWED');
    }
    if (sourceDataset.trim().isEmpty) {
      errors.add('REGISTRY_SOURCE_DATASET_REQUIRED');
    }
    if (coverage != nationwideCoverage && coverage != validationSubsetCoverage) {
      errors.add('REGISTRY_COVERAGE_INVALID');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contentSha256)) {
      errors.add('REGISTRY_SHA256_FORMAT_INVALID');
    }
    if (entities.isEmpty) errors.add('REGISTRY_ENTITIES_REQUIRED');

    final keys = <String>{};
    for (final entity in entities) {
      if (!RegExp(r'^\d{8}$').hasMatch(entity.sellerIdentifier)) {
        errors.add('REGISTRY_SELLER_IDENTIFIER_INVALID');
      }
      if (entity.legalName.trim().isEmpty) {
        errors.add('REGISTRY_LEGAL_NAME_REQUIRED');
      }
      if (entity.sourceDataset.trim().isEmpty) {
        errors.add('REGISTRY_ENTITY_SOURCE_REQUIRED');
      }
      if (entity.parentSellerIdentifier.isNotEmpty &&
          !RegExp(r'^\d{8}$').hasMatch(entity.parentSellerIdentifier)) {
        errors.add('REGISTRY_PARENT_IDENTIFIER_INVALID');
      }
      final key =
          '${entity.sellerIdentifier}|${entity.entityType.name}';
      if (!keys.add(key)) errors.add('REGISTRY_DUPLICATE_ENTITY_KEY');
    }

    final actualSha = await computeBusinessRegistryPayloadSha256(entities);
    if (contentSha256.isNotEmpty && actualSha != contentSha256) {
      errors.add('REGISTRY_SHA256_MISMATCH');
    }
    return BusinessRegistryPackValidation(
      isValid: errors.isEmpty,
      errors: List<String>.unmodifiable(errors.toSet()),
      actualContentSha256: actualSha,
    );
  }
}

class BusinessRegistryPackValidation {
  const BusinessRegistryPackValidation({
    required this.isValid,
    required this.errors,
    required this.actualContentSha256,
  });

  final bool isValid;
  final List<String> errors;
  final String actualContentSha256;
}

Future<String> computeBusinessRegistryPayloadSha256(
  Iterable<BusinessRegistryEntity> source,
) async {
  final entities = source.toList(growable: false)
    ..sort((left, right) {
      final seller = left.sellerIdentifier.compareTo(right.sellerIdentifier);
      if (seller != 0) return seller;
      final type = left.entityType.name.compareTo(right.entityType.name);
      if (type != 0) return type;
      return left.legalName.compareTo(right.legalName);
    });
  final canonicalJson = jsonEncode(
    entities.map((item) => item.toCanonicalJson()).toList(growable: false),
  );
  final digest = await Sha256().hash(utf8.encode(canonicalJson));
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
