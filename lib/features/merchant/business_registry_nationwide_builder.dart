import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'business_registry_pack.dart';

/// Streaming first-pass builder for the nationwide registry distribution pack.
///
/// Production input must already be externally sorted by [compareEntities].
/// This keeps the builder O(1) with respect to nationwide entity count and
/// avoids reviving the validation-subset in-memory list path. The first pass
/// validates canonical records and computes the exact entity-payload SHA-256;
/// a second pass can then emit the stream header followed by the same canonical
/// entity lines.
class BusinessRegistryNationwideBuildPass {
  BusinessRegistryNationwideBuildPass() : _hashSink = Sha256().newHashSink();

  final HashSink _hashSink;
  String? _lastKey;
  int _entityCount = 0;
  bool _closed = false;

  int get entityCount => _entityCount;

  String add(BusinessRegistryEntity source) {
    if (_closed) {
      throw StateError('REGISTRY_BUILDER_ALREADY_CLOSED');
    }
    final entity = normalizeEntity(source);
    final errors = validateEntity(entity);
    if (errors.isNotEmpty) {
      throw FormatException(errors.join(','));
    }

    final key = canonicalEntityKey(entity);
    final previous = _lastKey;
    if (previous != null) {
      final comparison = key.compareTo(previous);
      if (comparison < 0) {
        throw StateError('REGISTRY_BUILDER_INPUT_NOT_SORTED');
      }
      if (comparison == 0) {
        throw StateError('REGISTRY_BUILDER_DUPLICATE_ENTITY_KEY');
      }
    }

    final line = canonicalEntityLine(entity);
    _hashSink.add(utf8.encode(line));
    _lastKey = key;
    _entityCount += 1;
    return line;
  }

  Future<BusinessRegistryNationwideBuildSummary> close() async {
    if (_closed) {
      throw StateError('REGISTRY_BUILDER_ALREADY_CLOSED');
    }
    _closed = true;
    // HashSink.close() is synchronous in package:cryptography; the digest is
    // retrieved asynchronously via hash(). Awaiting close() breaks analyzer
    // because close() returns void.
    _hashSink.close();
    final hash = await _hashSink.hash();
    return BusinessRegistryNationwideBuildSummary(
      entityCount: _entityCount,
      registryContentSha256: hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  }

  static BusinessRegistryEntity normalizeEntity(
    BusinessRegistryEntity source,
  ) {
    return BusinessRegistryEntity(
      sellerIdentifier: source.sellerIdentifier.trim(),
      entityType: source.entityType,
      legalName: source.legalName.trim(),
      registrationStatus: source.registrationStatus.trim(),
      parentSellerIdentifier: source.parentSellerIdentifier.trim(),
      sourceDataset: source.sourceDataset.trim(),
    );
  }

  static List<String> validateEntity(BusinessRegistryEntity entity) {
    final errors = <String>[];
    if (!RegExp(r'^\d{8}$').hasMatch(entity.sellerIdentifier)) {
      errors.add('REGISTRY_BUILDER_SELLER_IDENTIFIER_INVALID');
    }
    if (entity.legalName.isEmpty) {
      errors.add('REGISTRY_BUILDER_LEGAL_NAME_REQUIRED');
    }
    if (entity.sourceDataset.isEmpty) {
      errors.add('REGISTRY_BUILDER_SOURCE_DATASET_REQUIRED');
    }
    if (entity.parentSellerIdentifier.isNotEmpty &&
        !RegExp(r'^\d{8}$').hasMatch(entity.parentSellerIdentifier)) {
      errors.add('REGISTRY_BUILDER_PARENT_IDENTIFIER_INVALID');
    }
    return List<String>.unmodifiable(errors);
  }

  static int compareEntities(
    BusinessRegistryEntity left,
    BusinessRegistryEntity right,
  ) {
    return canonicalEntityKey(left).compareTo(canonicalEntityKey(right));
  }

  static String canonicalEntityKey(BusinessRegistryEntity entity) {
    final normalized = normalizeEntity(entity);
    return '${normalized.sellerIdentifier}|${normalized.entityType.name}';
  }

  static String canonicalEntityLine(BusinessRegistryEntity entity) {
    final normalized = normalizeEntity(entity);
    return '${jsonEncode(<String, Object?>{
      'record_type': 'entity',
      ...normalized.toCanonicalJson(),
    })}\n';
  }
}

/// Immutable provenance required before a nationwide second pass can emit a
/// stream header. This deliberately contains no download URL or compressed
/// size fields: those belong to the distribution manifest after the emitted
/// NDJSON has been compressed and hashed.
class BusinessRegistryNationwideBuildMetadata {
  const BusinessRegistryNationwideBuildMetadata({
    required this.registryVersion,
    required this.sourceAuthority,
    required this.sourceDataset,
    required this.sourceDataDate,
    this.coverage = BusinessRegistryPack.nationwideCoverage,
  });

  final String registryVersion;
  final String sourceAuthority;
  final String sourceDataset;
  final String sourceDataDate;
  final String coverage;

  List<String> validate() {
    final errors = <String>[];
    if (registryVersion.trim().isEmpty) {
      errors.add('REGISTRY_BUILDER_VERSION_REQUIRED');
    }
    if (!BusinessRegistryPack.allowedSourceAuthorities
        .contains(sourceAuthority.trim())) {
      errors.add('REGISTRY_BUILDER_SOURCE_AUTHORITY_NOT_ALLOWED');
    }
    if (sourceDataset.trim().isEmpty) {
      errors.add('REGISTRY_BUILDER_SOURCE_DATASET_REQUIRED');
    }
    if (DateTime.tryParse(sourceDataDate.trim()) == null) {
      errors.add('REGISTRY_BUILDER_SOURCE_DATA_DATE_INVALID');
    }
    if (coverage != BusinessRegistryPack.nationwideCoverage) {
      errors.add('REGISTRY_BUILDER_MUST_BE_NATIONWIDE');
    }
    return List<String>.unmodifiable(errors);
  }
}

/// O(1)-memory second pass that emits the canonical stream header and verifies
/// that the source has not changed since the first pass.
///
/// The caller writes [headerLine] once, then writes every line returned by
/// [add]. [close] must succeed before the uncompressed NDJSON is accepted for
/// compression/distribution. Any entity-count or payload-hash drift fails
/// closed, preventing a manifest from describing different bytes than the
/// registry content that was actually emitted.
class BusinessRegistryNationwideEmitPass {
  BusinessRegistryNationwideEmitPass({
    required this.metadata,
    required this.expectedSummary,
  }) : _verificationPass = BusinessRegistryNationwideBuildPass() {
    final errors = metadata.validate();
    if (errors.isNotEmpty) {
      throw FormatException(errors.join(','));
    }
    if (expectedSummary.entityCount <= 0) {
      throw const FormatException('REGISTRY_BUILDER_ENTITY_COUNT_INVALID');
    }
    if (!RegExp(r'^[0-9a-f]{64}$')
        .hasMatch(expectedSummary.registryContentSha256)) {
      throw const FormatException('REGISTRY_BUILDER_CONTENT_SHA256_INVALID');
    }
  }

  final BusinessRegistryNationwideBuildMetadata metadata;
  final BusinessRegistryNationwideBuildSummary expectedSummary;
  final BusinessRegistryNationwideBuildPass _verificationPass;
  bool _closed = false;

  String get headerLine => '${jsonEncode(<String, Object?>{
        'record_type': 'header',
        'registry_version': metadata.registryVersion.trim(),
        'source_authority': metadata.sourceAuthority.trim(),
        'source_dataset': metadata.sourceDataset.trim(),
        'source_data_date': metadata.sourceDataDate.trim(),
        'coverage': metadata.coverage,
        'entity_count': expectedSummary.entityCount,
        'registry_content_sha256': expectedSummary.registryContentSha256,
      })}\n';

  String add(BusinessRegistryEntity source) {
    if (_closed) {
      throw StateError('REGISTRY_BUILDER_ALREADY_CLOSED');
    }
    return _verificationPass.add(source);
  }

  Future<BusinessRegistryNationwideBuildSummary> close() async {
    if (_closed) {
      throw StateError('REGISTRY_BUILDER_ALREADY_CLOSED');
    }
    _closed = true;
    final actual = await _verificationPass.close();
    if (actual.entityCount != expectedSummary.entityCount) {
      throw StateError(
        'REGISTRY_BUILDER_SECOND_PASS_ENTITY_COUNT_MISMATCH',
      );
    }
    if (actual.registryContentSha256 !=
        expectedSummary.registryContentSha256) {
      throw StateError('REGISTRY_BUILDER_SECOND_PASS_SHA256_MISMATCH');
    }
    return actual;
  }
}

class BusinessRegistryNationwideBuildSummary {
  const BusinessRegistryNationwideBuildSummary({
    required this.entityCount,
    required this.registryContentSha256,
  });

  final int entityCount;
  final String registryContentSha256;
}
