import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'invoice_award_cloud_artifact_downloader.dart';
import 'invoice_award_cloud_publication_parser.dart';

typedef CloudAwardPdfCacheDirectoryProvider = Future<Directory> Function();

class CloudAwardCachedPdfManifest {
  const CloudAwardCachedPdfManifest({
    required this.periodId,
    required this.tierCode,
    required this.artifactId,
    required this.officialSourceUri,
    required this.pdfSha256,
    required this.sizeBytes,
    required this.downloadedAtUtc,
    required this.retentionUntilUtc,
    required this.fileName,
  });

  static const int schemaVersion = 1;

  final String periodId;
  final String tierCode;
  final String artifactId;
  final Uri officialSourceUri;
  final String pdfSha256;
  final int sizeBytes;
  final DateTime downloadedAtUtc;
  final DateTime? retentionUntilUtc;
  final String fileName;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'periodId': periodId,
        'tierCode': tierCode,
        'artifactId': artifactId,
        'officialSourceUri': officialSourceUri.toString(),
        'pdfSha256': pdfSha256,
        'sizeBytes': sizeBytes,
        'downloadedAtUtc': downloadedAtUtc.toIso8601String(),
        'retentionUntilUtc': retentionUntilUtc?.toIso8601String(),
        'fileName': fileName,
      };

  factory CloudAwardCachedPdfManifest.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('CLOUD_AWARD_PDF_CACHE_SCHEMA_INVALID');
    }
    final source = Uri.tryParse(json['officialSourceUri']?.toString() ?? '');
    final downloadedAt =
        DateTime.tryParse(json['downloadedAtUtc']?.toString() ?? '');
    final retentionRaw = json['retentionUntilUtc']?.toString();
    final retention = retentionRaw == null || retentionRaw.isEmpty
        ? null
        : DateTime.tryParse(retentionRaw);
    final manifest = CloudAwardCachedPdfManifest(
      periodId: json['periodId']?.toString() ?? '',
      tierCode: json['tierCode']?.toString() ?? '',
      artifactId: json['artifactId']?.toString() ?? '',
      officialSourceUri: source ?? Uri(),
      pdfSha256: json['pdfSha256']?.toString().toLowerCase() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? -1,
      downloadedAtUtc: downloadedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      retentionUntilUtc: retention,
      fileName: json['fileName']?.toString() ?? '',
    );
    if (!manifest._isStructurallyValid) {
      throw const FormatException('CLOUD_AWARD_PDF_CACHE_MANIFEST_INVALID');
    }
    return manifest;
  }

  bool get _isStructurallyValid {
    final ref = OfficialCloudAwardArtifactReference(
      artifactId: artifactId,
      sourceUri: officialSourceUri,
      periodId: periodId,
      tierCode: tierCode,
    );
    return periodId.isNotEmpty &&
        const <String>{
          'cloud-500',
          'cloud-800',
          'cloud-2000',
          'cloud-1000000',
        }.contains(tierCode) &&
        artifactId.isNotEmpty &&
        ref.isApprovedOfficialSource &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(pdfSha256) &&
        sizeBytes >= 64 &&
        downloadedAtUtc.isUtc &&
        (retentionUntilUtc == null || retentionUntilUtc!.isUtc) &&
        fileName == '$pdfSha256.pdf';
  }

  bool matches(OfficialCloudAwardArtifactReference reference) =>
      periodId == reference.periodId &&
      tierCode == reference.tierCode &&
      artifactId == reference.artifactId &&
      officialSourceUri == reference.sourceUri;
}

class CloudAwardCachedPdfSnapshot {
  const CloudAwardCachedPdfSnapshot({
    required this.manifest,
    required this.pdfFile,
  });

  final CloudAwardCachedPdfManifest manifest;
  final File pdfFile;

  OfficialCloudAwardDownloadedArtifact asDownloadedArtifact(
    OfficialCloudAwardArtifactReference reference,
  ) {
    if (!manifest.matches(reference)) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_REFERENCE_MISMATCH');
    }
    return OfficialCloudAwardDownloadedArtifact(
      reference: reference,
      file: pdfFile,
      sizeBytes: manifest.sizeBytes,
      sha256: manifest.pdfSha256,
    );
  }
}

/// Durable, read-back validated cache for large official cloud-award PDFs.
///
/// A fully downloaded PDF is promoted before extraction starts. Therefore an
/// extraction crash never forces the same 100MB+ official artifact to be
/// downloaded again. Cache identity is exact publication artifact + source,
/// not merely period/tier.
class CloudAwardPdfCacheRepository {
  CloudAwardPdfCacheRepository({
    CloudAwardPdfCacheDirectoryProvider? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory;

  final CloudAwardPdfCacheDirectoryProvider _rootDirectoryProvider;

  Future<CloudAwardCachedPdfSnapshot?> readValidated({
    required OfficialCloudAwardArtifactReference reference,
  }) async {
    if (!reference.isApprovedOfficialSource) return null;
    final directory = await _tierDirectory(reference);
    if (!await directory.exists()) return null;

    final candidates = <CloudAwardCachedPdfSnapshot>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.manifest.json')) continue;
      try {
        final manifest = await _readManifest(entity);
        if (!manifest.matches(reference)) continue;
        final snapshot = CloudAwardCachedPdfSnapshot(
          manifest: manifest,
          pdfFile: File(
            '${directory.path}${Platform.pathSeparator}${manifest.fileName}',
          ),
        );
        await _validateSnapshot(snapshot);
        candidates.add(snapshot);
      } catch (_) {
        // Fail closed: corrupt/partial cache metadata is never reused.
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort(
      (left, right) =>
          right.manifest.downloadedAtUtc.compareTo(left.manifest.downloadedAtUtc),
    );
    return candidates.first;
  }

  Future<CloudAwardCachedPdfSnapshot> promoteValidated({
    required OfficialCloudAwardDownloadedArtifact artifact,
    required DateTime downloadedAtUtc,
    DateTime? retentionUntilUtc,
  }) async {
    if (!downloadedAtUtc.isUtc ||
        (retentionUntilUtc != null && !retentionUntilUtc.isUtc)) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_TIME_NOT_UTC');
    }
    if (!artifact.reference.isApprovedOfficialSource ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifact.sha256.toLowerCase()) ||
        artifact.sizeBytes < 64) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_ARTIFACT_INVALID');
    }
    await _validateDownloadedArtifact(artifact);

    final directory = await _tierDirectory(artifact.reference);
    await directory.create(recursive: true);
    final sha = artifact.sha256.toLowerCase();
    final finalPdf =
        File('${directory.path}${Platform.pathSeparator}$sha.pdf');

    if (!await finalPdf.exists()) {
      final candidate = File(
        '${finalPdf.path}.candidate-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        try {
          await artifact.file.rename(candidate.path);
        } catch (_) {
          final sink = candidate.openWrite(mode: FileMode.writeOnly);
          await artifact.file.openRead().pipe(sink);
        }
        final candidateSnapshot = CloudAwardCachedPdfSnapshot(
          manifest: CloudAwardCachedPdfManifest(
            periodId: artifact.reference.periodId,
            tierCode: artifact.reference.tierCode,
            artifactId: artifact.reference.artifactId,
            officialSourceUri: artifact.reference.sourceUri,
            pdfSha256: sha,
            sizeBytes: artifact.sizeBytes,
            downloadedAtUtc: downloadedAtUtc,
            retentionUntilUtc: retentionUntilUtc,
            fileName: '$sha.pdf',
          ),
          pdfFile: candidate,
        );
        await _validateSnapshot(candidateSnapshot);
        await candidate.rename(finalPdf.path);
      } catch (_) {
        if (await candidate.exists()) await candidate.delete();
        rethrow;
      }
    }

    final manifest = CloudAwardCachedPdfManifest(
      periodId: artifact.reference.periodId,
      tierCode: artifact.reference.tierCode,
      artifactId: artifact.reference.artifactId,
      officialSourceUri: artifact.reference.sourceUri,
      pdfSha256: sha,
      sizeBytes: artifact.sizeBytes,
      downloadedAtUtc: downloadedAtUtc,
      retentionUntilUtc: retentionUntilUtc,
      fileName: '$sha.pdf',
    );
    final snapshot =
        CloudAwardCachedPdfSnapshot(manifest: manifest, pdfFile: finalPdf);
    await _validateSnapshot(snapshot);

    final manifestFile = File(
      '${directory.path}${Platform.pathSeparator}$sha.manifest.json',
    );
    if (!await manifestFile.exists()) {
      final candidate = File(
        '${manifestFile.path}.candidate-${DateTime.now().microsecondsSinceEpoch}',
      );
      await candidate.writeAsString(jsonEncode(manifest.toJson()), flush: true);
      await candidate.rename(manifestFile.path);
    }
    final readBack = await _readManifest(manifestFile);
    final readBackSnapshot =
        CloudAwardCachedPdfSnapshot(manifest: readBack, pdfFile: finalPdf);
    await _validateSnapshot(readBackSnapshot);
    if (!readBack.matches(artifact.reference)) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_READBACK_MISMATCH');
    }
    return readBackSnapshot;
  }

  Future<int> pruneExpired({required DateTime nowUtc}) async {
    if (!nowUtc.isUtc) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_PRUNE_TIME_NOT_UTC');
    }
    final root = await _cacheRoot();
    if (!await root.exists()) return 0;
    var removed = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.manifest.json')) continue;
      try {
        final manifest = await _readManifest(entity);
        final retention = manifest.retentionUntilUtc;
        if (retention == null || !nowUtc.isAfter(retention)) continue;
        final pdf = File(
          '${entity.parent.path}${Platform.pathSeparator}${manifest.fileName}',
        );
        if (await entity.exists()) await entity.delete();
        if (await pdf.exists()) await pdf.delete();
        removed++;
      } catch (_) {
        // Corrupt entries are not interpreted as expired authority.
      }
    }
    return removed;
  }

  Future<Directory> _cacheRoot() async {
    final support = await _rootDirectoryProvider();
    return Directory(
      '${support.path}${Platform.pathSeparator}invoice_award'
      '${Platform.pathSeparator}cloud_pdf_cache',
    );
  }

  Future<Directory> _tierDirectory(
    OfficialCloudAwardArtifactReference reference,
  ) async {
    final root = await _cacheRoot();
    final safePeriod = reference.periodId.replaceAll(RegExp(r'[^0-9-]'), '_');
    final safeTier = reference.tierCode.replaceAll(RegExp(r'[^a-z0-9-]'), '_');
    return Directory(
      '${root.path}${Platform.pathSeparator}$safePeriod'
      '${Platform.pathSeparator}$safeTier',
    );
  }

  Future<CloudAwardCachedPdfManifest> _readManifest(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('CLOUD_AWARD_PDF_CACHE_JSON_INVALID');
    }
    return CloudAwardCachedPdfManifest.fromJson(decoded);
  }

  Future<void> _validateDownloadedArtifact(
    OfficialCloudAwardDownloadedArtifact artifact,
  ) async {
    final sha = artifact.sha256.toLowerCase();
    final manifest = CloudAwardCachedPdfManifest(
      periodId: artifact.reference.periodId,
      tierCode: artifact.reference.tierCode,
      artifactId: artifact.reference.artifactId,
      officialSourceUri: artifact.reference.sourceUri,
      pdfSha256: sha,
      sizeBytes: artifact.sizeBytes,
      downloadedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      retentionUntilUtc: null,
      fileName: '$sha.pdf',
    );
    await _validateSnapshot(
      CloudAwardCachedPdfSnapshot(manifest: manifest, pdfFile: artifact.file),
    );
  }

  Future<void> _validateSnapshot(CloudAwardCachedPdfSnapshot snapshot) async {
    final file = snapshot.pdfFile;
    if (!await file.exists()) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_FILE_MISSING');
    }
    final length = await file.length();
    if (length != snapshot.manifest.sizeBytes) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_SIZE_MISMATCH');
    }
    final handle = await file.open();
    try {
      final prefix = await handle.read(5);
      if (prefix.length != 5 || String.fromCharCodes(prefix) != '%PDF-') {
        throw StateError('CLOUD_AWARD_PDF_CACHE_MAGIC_INVALID');
      }
    } finally {
      await handle.close();
    }
    final hash = await Sha256().hashStream(file.openRead());
    final sha = hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    if (sha != snapshot.manifest.pdfSha256) {
      throw StateError('CLOUD_AWARD_PDF_CACHE_SHA_MISMATCH');
    }
  }
}
