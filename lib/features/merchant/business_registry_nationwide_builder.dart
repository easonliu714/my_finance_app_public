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
    await _hashSink.close();
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

class BusinessRegistryNationwideBuildSummary {
  const BusinessRegistryNationwideBuildSummary({
    required this.entityCount,
    required this.registryContentSha256,
  });

  final int entityCount;
  final String registryContentSha256;
}
