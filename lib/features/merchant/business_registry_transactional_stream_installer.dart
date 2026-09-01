import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/production_database_coordinator.dart';
import '../../database/production_schema_v22.dart';
import 'business_registry_distribution_manifest.dart';
import 'business_registry_nationwide_builder.dart';
import 'business_registry_stream_pack.dart';
import 'business_registry_stream_validator.dart';

enum BusinessRegistryStreamInstallStatus { installed, alreadyInstalled }

class BusinessRegistryStreamInstallResult {
  const BusinessRegistryStreamInstallResult({
    required this.status,
    required this.version,
    required this.entityCount,
  });

  final BusinessRegistryStreamInstallStatus status;
  final String version;
  final int entityCount;
}

/// Consumes one already validated nationwide registry artifact using bounded
/// memory and one SQLite transaction.
///
/// This is deliberately a second pass over the gzip artifact. It rebinds the
/// compressed bytes, stream header, canonical entity order/count and content
/// hash to the manifest while inserting entities in bounded batches. Any
/// exception rolls the transaction back, so the previously installed registry
/// remains last-known-good. Only `business_registry_*` cache tables are
/// mutated; user-owned merchant identity/history is outside this installer.
class BusinessRegistryTransactionalStreamInstaller {
  const BusinessRegistryTransactionalStreamInstaller({
    this.database,
    this.batchSize = 500,
  });

  final Database? database;
  final int batchSize;

  Future<BusinessRegistryStreamInstallResult> install({
    required BusinessRegistryDistributionManifest manifest,
    required BusinessRegistryValidatedArtifact artifact,
  }) async {
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize');
    }

    try {
      final manifestValidation = manifest.validate();
      if (!manifestValidation.isValid) {
        throw FormatException(manifestValidation.errors.join(','));
      }
      _assertValidatedArtifactAuthority(manifest, artifact);
      if (!await artifact.file.exists()) {
        throw StateError('REGISTRY_INSTALL_ARTIFACT_MISSING');
      }

      final db =
          database ?? await ProductionDatabaseCoordinator.instance.database;
      await createCanonicalProductionV22Tables(db);

      final existing = await db.query(
        'business_registry_snapshots',
        where: 'version = ?',
        whereArgs: <Object?>[manifest.registryVersion],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final sameContent = existing.first['content_sha256']?.toString() ==
            manifest.registryContentSha256;
        final status = existing.first['status']?.toString() ?? '';
        if (sameContent && status == 'installed') {
          return BusinessRegistryStreamInstallResult(
            status: BusinessRegistryStreamInstallStatus.alreadyInstalled,
            version: manifest.registryVersion,
            entityCount: manifest.entityCount,
          );
        }
        throw StateError('BUSINESS_REGISTRY_VERSION_CONFLICT');
      }

      final now = DateTime.now().toUtc().toIso8601String();
      return await db.transaction<BusinessRegistryStreamInstallResult>(
        (txn) async {
          await txn.insert('business_registry_snapshots', <String, Object?>{
            'version': manifest.registryVersion,
            'source_dataset': _snapshotSourceDataset(manifest),
            'source_data_date': manifest.sourceDataDate,
            'content_sha256': manifest.registryContentSha256,
            'status': 'staged',
            'installed_at': null,
            'created_at': now,
          });

          const parser = BusinessRegistryStreamPackParser();
          final compressedHashSink = Sha256().newHashSink();
          final contentHashSink = Sha256().newHashSink();
          var compressedHashClosed = false;
          var contentHashClosed = false;
          var compressedBytes = 0;
          var uncompressedBytes = 0;
          var entityCount = 0;
          var sawHeader = false;
          String? lastEntityKey;
          var batch = txn.batch();
          var batchCount = 0;

          try {
            final countedCompressedBytes =
                artifact.file.openRead().transform<List<int>>(
                      StreamTransformer<List<int>, List<int>>.fromHandlers(
                        handleData: (chunk, sink) {
                          compressedBytes += chunk.length;
                          if (compressedBytes > manifest.compressedSizeBytes ||
                              compressedBytes >
                                  BusinessRegistryDistributionManifest
                                      .maxCompressedSizeBytes) {
                            sink.addError(
                              StateError(
                                'REGISTRY_INSTALL_COMPRESSED_SIZE_EXCEEDED',
                              ),
                            );
                            return;
                          }
                          compressedHashSink.add(chunk);
                          sink.add(chunk);
                        },
                      ),
                    );
            final countedInflatedBytes = gzip.decoder
                .bind(countedCompressedBytes)
                .transform<List<int>>(
                  StreamTransformer<List<int>, List<int>>.fromHandlers(
                    handleData: (chunk, sink) {
                      uncompressedBytes += chunk.length;
                      if (uncompressedBytes > manifest.uncompressedSizeBytes ||
                          uncompressedBytes >
                              BusinessRegistryDistributionManifest
                                  .maxUncompressedSizeBytes) {
                        sink.addError(
                          StateError(
                            'REGISTRY_INSTALL_UNCOMPRESSED_SIZE_EXCEEDED',
                          ),
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
                    throw StateError(
                      'REGISTRY_INSTALL_HEADER_POSITION_INVALID',
                    );
                  }
                  final errors = header.validateAgainst(manifest);
                  if (errors.isNotEmpty) {
                    throw FormatException(errors.join(','));
                  }
                  sawHeader = true;

                case BusinessRegistryStreamEntityRecord(:final entity):
                  if (!sawHeader) {
                    throw StateError('REGISTRY_INSTALL_HEADER_REQUIRED');
                  }
                  final errors = parser.validateEntity(entity);
                  if (errors.isNotEmpty) {
                    throw FormatException(errors.join(','));
                  }
                  final canonicalLine = BusinessRegistryNationwideBuildPass
                      .canonicalEntityLine(entity);
                  if (canonicalLine != '$line\n') {
                    throw StateError('REGISTRY_INSTALL_ENTITY_NOT_CANONICAL');
                  }

                  final key = BusinessRegistryNationwideBuildPass
                      .canonicalEntityKey(entity);
                  final previous = lastEntityKey;
                  if (previous != null) {
                    final comparison = key.compareTo(previous);
                    if (comparison < 0) {
                      throw StateError('REGISTRY_INSTALL_ENTITY_NOT_SORTED');
                    }
                    if (comparison == 0) {
                      throw StateError(
                        'REGISTRY_INSTALL_DUPLICATE_ENTITY_KEY',
                      );
                    }
                  }

                  contentHashSink.add(utf8.encode(canonicalLine));
                  batch.insert(
                    'business_registry_entities',
                    <String, Object?>{
                      'snapshot_version': manifest.registryVersion,
                      'jurisdiction': 'TW',
                      'seller_identifier': entity.sellerIdentifier,
                      'entity_type': entity.entityType.name,
                      'legal_name': entity.legalName.trim(),
                      'registration_status': entity.registrationStatus.trim(),
                      'parent_seller_identifier':
                          entity.parentSellerIdentifier.trim(),
                      'source_dataset': entity.sourceDataset.trim(),
                    },
                  );
                  lastEntityKey = key;
                  entityCount += 1;
                  batchCount += 1;
                  if (entityCount > manifest.entityCount) {
                    throw StateError(
                      'REGISTRY_INSTALL_ENTITY_COUNT_EXCEEDED',
                    );
                  }
                  if (batchCount >= batchSize) {
                    await batch.commit(noResult: true);
                    batch = txn.batch();
                    batchCount = 0;
                  }
              }
            }

            if (batchCount > 0) {
              await batch.commit(noResult: true);
            }
            if (!sawHeader) {
              throw StateError('REGISTRY_INSTALL_HEADER_REQUIRED');
            }
            if (compressedBytes != manifest.compressedSizeBytes) {
              throw StateError('REGISTRY_INSTALL_COMPRESSED_SIZE_MISMATCH');
            }
            if (uncompressedBytes != manifest.uncompressedSizeBytes) {
              throw StateError('REGISTRY_INSTALL_UNCOMPRESSED_SIZE_MISMATCH');
            }
            if (entityCount != manifest.entityCount) {
              throw StateError('REGISTRY_INSTALL_ENTITY_COUNT_MISMATCH');
            }

            compressedHashSink.close();
            compressedHashClosed = true;
            contentHashSink.close();
            contentHashClosed = true;
            final compressedHash = await compressedHashSink.hash();
            final contentHash = await contentHashSink.hash();
            final actualDownloadSha256 = _hex(compressedHash.bytes);
            final actualContentSha256 = _hex(contentHash.bytes);
            if (actualDownloadSha256 != manifest.downloadSha256) {
              throw StateError('REGISTRY_INSTALL_DOWNLOAD_SHA256_MISMATCH');
            }
            if (actualContentSha256 != manifest.registryContentSha256) {
              throw StateError('REGISTRY_INSTALL_CONTENT_SHA256_MISMATCH');
            }

            await txn.update(
              'business_registry_snapshots',
              <String, Object?>{'status': 'superseded'},
              where: "status = 'installed' AND version <> ?",
              whereArgs: <Object?>[manifest.registryVersion],
            );
            await txn.update(
              'business_registry_snapshots',
              <String, Object?>{
                'status': 'installed',
                'installed_at': now,
              },
              where: 'version = ?',
              whereArgs: <Object?>[manifest.registryVersion],
            );

            return BusinessRegistryStreamInstallResult(
              status: BusinessRegistryStreamInstallStatus.installed,
              version: manifest.registryVersion,
              entityCount: entityCount,
            );
          } finally {
            if (!compressedHashClosed) {
              compressedHashSink.close();
            }
            if (!contentHashClosed) {
              contentHashSink.close();
            }
          }
        },
      );
    } finally {
      await _deleteIfExists(artifact.file);
    }
  }

  static void _assertValidatedArtifactAuthority(
    BusinessRegistryDistributionManifest manifest,
    BusinessRegistryValidatedArtifact artifact,
  ) {
    if (artifact.compressedSizeBytes != manifest.compressedSizeBytes ||
        artifact.uncompressedSizeBytes != manifest.uncompressedSizeBytes ||
        artifact.entityCount != manifest.entityCount ||
        artifact.downloadSha256 != manifest.downloadSha256 ||
        artifact.registryContentSha256 != manifest.registryContentSha256) {
      throw StateError('REGISTRY_INSTALL_VALIDATED_ARTIFACT_AUTHORITY_MISMATCH');
    }
  }

  static String _snapshotSourceDataset(
    BusinessRegistryDistributionManifest manifest,
  ) =>
      '${manifest.sourceAuthority}|${manifest.coverage}|${manifest.sourceDataset}';

  static String _hex(List<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
