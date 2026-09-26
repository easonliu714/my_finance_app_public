import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'invoice_award_cloud_pdf_index.dart';

enum CloudAwardIndexPromotionStatus {
  promoted,
  alreadyCurrent,
}

class CloudAwardValidatedIndexSnapshot {
  const CloudAwardValidatedIndexSnapshot({
    required this.indexFile,
    required this.manifestFile,
    required this.manifest,
  });

  final File indexFile;
  final File manifestFile;
  final CloudAwardLocalIndexManifest manifest;
}

class CloudAwardIndexPromotionResult {
  const CloudAwardIndexPromotionResult({
    required this.status,
    required this.snapshot,
  });

  final CloudAwardIndexPromotionStatus status;
  final CloudAwardValidatedIndexSnapshot snapshot;
}

typedef CloudAwardSupportDirectoryProvider = Future<Directory> Function();

/// File-backed Last-Known-Good repository for large cloud-exclusive award
/// indexes.
///
/// Promotion is content-addressed by the validated index SHA-256. The large
/// index is committed first under its immutable hash filename; the compact
/// manifest is committed last. Read authority only considers complete manifest
/// files, so a crash between those two renames can leave at most an unreferenced
/// immutable index while the previous LKG remains readable.
class CloudAwardIndexLkgRepository {
  CloudAwardIndexLkgRepository({
    CloudAwardSupportDirectoryProvider? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  final CloudAwardSupportDirectoryProvider _supportDirectoryProvider;

  static const String _rootName = 'invoice_award_cloud_lkg';
  static const Set<String> allowedTierCodes = <String>{
    'cloud-500',
    'cloud-800',
    'cloud-2000',
    'cloud-1000000',
  };

  Future<CloudAwardIndexPromotionResult> promoteValidated({
    required CloudAwardIndexBuildResult build,
  }) async {
    final manifest = build.manifest;
    _validateManifestAuthority(manifest);

    final candidateAudit = await _auditIndex(build.candidateIndexFile);
    if (candidateAudit.sha256 != manifest.indexSha256.toLowerCase() ||
        candidateAudit.rowCount != manifest.rowCount) {
      throw StateError('CLOUD_AWARD_LKG_CANDIDATE_AUDIT_MISMATCH');
    }

    final tierDirectory = await _tierDirectory(
      periodId: manifest.periodId,
      tierCode: manifest.tierCode,
    );
    await tierDirectory.create(recursive: true);

    final stem = manifest.indexSha256.toLowerCase();
    final finalIndex = File(
      '${tierDirectory.path}${Platform.pathSeparator}$stem.index',
    );
    final finalManifest = File(
      '${tierDirectory.path}${Platform.pathSeparator}$stem.json',
    );

    if (await finalIndex.exists() && await finalManifest.exists()) {
      final existing = await _readSnapshotFromManifest(finalManifest);
      if (_sameManifest(existing.manifest, manifest)) {
        return CloudAwardIndexPromotionResult(
          status: CloudAwardIndexPromotionStatus.alreadyCurrent,
          snapshot: existing,
        );
      }
      throw StateError('CLOUD_AWARD_LKG_CONTENT_ADDRESS_CONFLICT');
    }

    final tempIndex = File('${finalIndex.path}.partial');
    final tempManifest = File('${finalManifest.path}.partial');
    await _deleteIfExists(tempIndex);
    await _deleteIfExists(tempManifest);

    try {
      if (!await finalIndex.exists()) {
        await _copyStreaming(build.candidateIndexFile, tempIndex);
        final copiedAudit = await _auditIndex(tempIndex);
        if (copiedAudit.sha256 != manifest.indexSha256.toLowerCase() ||
            copiedAudit.rowCount != manifest.rowCount) {
          throw StateError('CLOUD_AWARD_LKG_STAGED_INDEX_AUDIT_MISMATCH');
        }
        await tempIndex.rename(finalIndex.path);
      } else {
        final existingIndexAudit = await _auditIndex(finalIndex);
        if (existingIndexAudit.sha256 != manifest.indexSha256.toLowerCase() ||
            existingIndexAudit.rowCount != manifest.rowCount) {
          throw StateError('CLOUD_AWARD_LKG_ORPHAN_INDEX_CONFLICT');
        }
      }

      final payload = <String, Object?>{
        'schema_version': 1,
        ...manifest.toJson(),
        'index_file': finalIndex.uri.pathSegments.last,
      };
      await tempManifest.writeAsString(
        jsonEncode(payload),
        encoding: utf8,
        flush: true,
      );
      await tempManifest.rename(finalManifest.path);

      final snapshot = await _readSnapshotFromManifest(finalManifest);
      if (!_sameManifest(snapshot.manifest, manifest)) {
        throw StateError('CLOUD_AWARD_LKG_POSTPROMOTION_READBACK_MISMATCH');
      }
      return CloudAwardIndexPromotionResult(
        status: CloudAwardIndexPromotionStatus.promoted,
        snapshot: snapshot,
      );
    } catch (_) {
      await _deleteIfExists(tempIndex);
      await _deleteIfExists(tempManifest);
      rethrow;
    }
  }

  Future<CloudAwardValidatedIndexSnapshot?> readLatest({
    required String periodId,
    required String tierCode,
  }) async {
    _validatePeriodTier(periodId, tierCode);
    final directory = await _tierDirectory(
      periodId: periodId,
      tierCode: tierCode,
    );
    if (!await directory.exists()) return null;

    final manifestFiles = await directory
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    CloudAwardValidatedIndexSnapshot? latest;
    for (final file in manifestFiles) {
      final snapshot = await _readSnapshotFromManifest(file);
      if (snapshot.manifest.periodId != periodId ||
          snapshot.manifest.tierCode != tierCode) {
        throw StateError('CLOUD_AWARD_LKG_MANIFEST_SCOPE_MISMATCH');
      }
      if (latest == null ||
          snapshot.manifest.builtAt.isAfter(latest.manifest.builtAt)) {
        latest = snapshot;
      }
    }
    return latest;
  }

  Future<CloudAwardValidatedIndexSnapshot> _readSnapshotFromManifest(
    File manifestFile,
  ) async {
    final decoded = jsonDecode(
      await manifestFile.readAsString(encoding: utf8),
    );
    if (decoded is! Map<String, dynamic> ||
        decoded['schema_version'] != 1) {
      throw const FormatException('invalid cloud award LKG manifest schema');
    }

    final periodId = _string(decoded['period_id'], 'period_id');
    final tierCode = _string(decoded['tier_code'], 'tier_code');
    final source = Uri.tryParse(
      _string(decoded['official_source_url'], 'official_source_url'),
    );
    if (source == null) {
      throw const FormatException('invalid cloud award source URI');
    }
    final builtAt = DateTime.tryParse(
      _string(decoded['built_at'], 'built_at'),
    );
    if (builtAt == null) {
      throw const FormatException('invalid cloud award built_at');
    }

    final manifest = CloudAwardLocalIndexManifest(
      periodId: periodId,
      tierCode: tierCode,
      officialSourceUri: source,
      pdfSha256: _string(decoded['pdf_sha256'], 'pdf_sha256'),
      indexSha256: _string(decoded['index_sha256'], 'index_sha256'),
      extractorVersion:
          _string(decoded['extractor_version'], 'extractor_version'),
      rowCount: _integer(decoded['row_count'], 'row_count'),
      builtAt: builtAt.toUtc(),
    );
    _validateManifestAuthority(manifest);

    final indexFileName = _string(decoded['index_file'], 'index_file');
    if (indexFileName != '${manifest.indexSha256.toLowerCase()}.index' ||
        indexFileName.contains('/') ||
        indexFileName.contains('\\')) {
      throw const FormatException('invalid cloud award index filename');
    }

    final indexFile = File(
      '${manifestFile.parent.path}${Platform.pathSeparator}$indexFileName',
    );
    if (!await indexFile.exists()) {
      throw StateError('CLOUD_AWARD_LKG_INDEX_MISSING');
    }
    final audit = await _auditIndex(indexFile);
    if (audit.sha256 != manifest.indexSha256.toLowerCase() ||
        audit.rowCount != manifest.rowCount) {
      throw StateError('CLOUD_AWARD_LKG_READBACK_AUDIT_MISMATCH');
    }

    return CloudAwardValidatedIndexSnapshot(
      indexFile: indexFile,
      manifestFile: manifestFile,
      manifest: manifest,
    );
  }

  Future<Directory> _tierDirectory({
    required String periodId,
    required String tierCode,
  }) async {
    _validatePeriodTier(periodId, tierCode);
    final root = await _supportDirectoryProvider();
    return Directory(
      '${root.path}${Platform.pathSeparator}$_rootName'
      '${Platform.pathSeparator}$periodId'
      '${Platform.pathSeparator}$tierCode',
    );
  }

  static void _validateManifestAuthority(
    CloudAwardLocalIndexManifest manifest,
  ) {
    _validatePeriodTier(manifest.periodId, manifest.tierCode);
    if (manifest.officialSourceUri.scheme != 'https' ||
        manifest.officialSourceUri.host != 'invoice.etax.nat.gov.tw' ||
        !manifest.officialSourceUri.path.startsWith('/pdf/') ||
        !manifest.officialSourceUri.path.endsWith('.pdf')) {
      throw StateError('CLOUD_AWARD_LKG_SOURCE_NOT_ALLOWED');
    }
    if (!_shaPattern.hasMatch(manifest.pdfSha256) ||
        !_shaPattern.hasMatch(manifest.indexSha256)) {
      throw StateError('CLOUD_AWARD_LKG_SHA_INVALID');
    }
    if (manifest.extractorVersion.trim().isEmpty || manifest.rowCount <= 0) {
      throw StateError('CLOUD_AWARD_LKG_MANIFEST_INVALID');
    }
  }

  static void _validatePeriodTier(String periodId, String tierCode) {
    if (!RegExp(r'^\d{3}-\d{2}-\d{2}$').hasMatch(periodId)) {
      throw FormatException('invalid cloud award period: $periodId');
    }
    if (!allowedTierCodes.contains(tierCode)) {
      throw FormatException('invalid cloud award tier: $tierCode');
    }
  }

  static final RegExp _shaPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  static Future<_CloudAwardIndexAudit> _auditIndex(File file) async {
    if (!await file.exists()) {
      throw StateError('CLOUD_AWARD_LKG_INDEX_MISSING');
    }

    final hashSink = Sha256().newHashSink();
    var rowCount = 0;
    var pending = <int>[];

    await for (final chunk in file.openRead()) {
      hashSink.add(chunk);
      pending.addAll(chunk);
      var start = 0;
      for (var index = 0; index < pending.length; index += 1) {
        if (pending[index] != 10) continue;
        final lineBytes = pending.sublist(start, index);
        final line = utf8.decode(lineBytes, allowMalformed: false).trim();
        _validateIndexLine(line);
        rowCount += 1;
        start = index + 1;
      }
      if (start > 0) {
        pending = pending.sublist(start);
      }
      if (pending.length > 64) {
        throw const FormatException('cloud award index line too long');
      }
    }

    if (pending.isNotEmpty) {
      final line = utf8.decode(pending, allowMalformed: false).trim();
      _validateIndexLine(line);
      rowCount += 1;
    }
    if (rowCount <= 0) {
      throw const FormatException('cloud award index is empty');
    }

    hashSink.close();
    final hash = await hashSink.hash();
    return _CloudAwardIndexAudit(
      sha256: hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      rowCount: rowCount,
    );
  }

  static void _validateIndexLine(String line) {
    if (!RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(line)) {
      throw const FormatException('malformed cloud award index line');
    }
  }

  static Future<void> _copyStreaming(File source, File target) async {
    IOSink? sink;
    try {
      sink = target.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } catch (_) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      rethrow;
    }
  }

  static bool _sameManifest(
    CloudAwardLocalIndexManifest left,
    CloudAwardLocalIndexManifest right,
  ) =>
      left.periodId == right.periodId &&
      left.tierCode == right.tierCode &&
      left.officialSourceUri == right.officialSourceUri &&
      left.pdfSha256.toLowerCase() == right.pdfSha256.toLowerCase() &&
      left.indexSha256.toLowerCase() == right.indexSha256.toLowerCase() &&
      left.extractorVersion == right.extractorVersion &&
      left.rowCount == right.rowCount;

  static String _string(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('invalid cloud award $field');
    }
    return value;
  }

  static int _integer(Object? value, String field) {
    if (value is! int) {
      throw FormatException('invalid cloud award $field');
    }
    return value;
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}

class _CloudAwardIndexAudit {
  const _CloudAwardIndexAudit({
    required this.sha256,
    required this.rowCount,
  });

  final String sha256;
  final int rowCount;
}
