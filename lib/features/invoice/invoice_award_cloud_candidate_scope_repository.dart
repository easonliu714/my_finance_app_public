import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'invoice_award_cloud_candidate_scope.dart';
import 'invoice_award_cloud_publication_parser.dart';

typedef CloudAwardCandidateScopeDirectoryProvider = Future<Directory> Function();

class CloudAwardCandidateScopeRepository {
  CloudAwardCandidateScopeRepository({
    CloudAwardCandidateScopeDirectoryProvider? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory;

  static const int schemaVersion = 1;

  final CloudAwardCandidateScopeDirectoryProvider _rootDirectoryProvider;

  Future<CloudAwardCandidateScopedAuthority?> readValidated({
    required OfficialCloudAwardArtifactReference reference,
    required String pdfSha256,
    required Iterable<String> candidateInvoiceNumbers,
    DateTime? nowUtc,
  }) async {
    if (!reference.isApprovedOfficialSource ||
        reference.tierCode != 'cloud-500') {
      return null;
    }
    final normalized = normalizeCloudCandidateNumbers(candidateInvoiceNumbers);
    if (normalized.isEmpty) return null;
    final universeSha = await cloudCandidateUniverseSha256(normalized);
    final pdfSha = pdfSha256.toLowerCase();
    if (!_shaPattern.hasMatch(pdfSha)) return null;

    final file = await _manifestFile(
      reference: reference,
      pdfSha256: pdfSha,
      candidateUniverseSha256: universeSha,
    );
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != schemaVersion) {
        return null;
      }
      final retentionRaw = decoded['retentionUntilUtc']?.toString();
      final retention = retentionRaw == null || retentionRaw.isEmpty
          ? null
          : DateTime.tryParse(retentionRaw)?.toUtc();
      final effectiveNow = nowUtc?.toUtc();
      if (retention != null &&
          effectiveNow != null &&
          effectiveNow.isAfter(retention)) {
        return null;
      }

      final source = Uri.tryParse(decoded['officialSourceUri']?.toString() ?? '');
      final storedMatches = (decoded['matchedInvoiceNumbers'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toSet() ??
          const <String>{};
      final normalizedMatches = normalizeCloudCandidateNumbers(storedMatches);
      if (decoded['periodId'] != reference.periodId ||
          decoded['tierCode'] != reference.tierCode ||
          decoded['artifactId'] != reference.artifactId ||
          source != reference.sourceUri ||
          decoded['pdfSha256']?.toString().toLowerCase() != pdfSha ||
          decoded['candidateUniverseSha256'] != universeSha ||
          normalizedMatches.length != storedMatches.length ||
          !normalized.containsAll(normalizedMatches)) {
        return null;
      }

      return CloudAwardCandidateScopedAuthority(
        periodId: reference.periodId,
        tierCode: reference.tierCode,
        officialSourceUri: reference.sourceUri,
        pdfSha256: pdfSha,
        candidateUniverseSha256: universeSha,
        candidateNumbers: normalized,
        matchedInvoiceNumbers: normalizedMatches,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CloudAwardCandidateScopedAuthority> promoteValidated({
    required OfficialCloudAwardArtifactReference reference,
    required String pdfSha256,
    required CloudAwardCandidateScopedAuthority authority,
    required DateTime verifiedAtUtc,
    DateTime? retentionUntilUtc,
  }) async {
    if (!verifiedAtUtc.isUtc ||
        (retentionUntilUtc != null && !retentionUntilUtc.isUtc) ||
        !reference.isApprovedOfficialSource ||
        reference.tierCode != 'cloud-500') {
      throw StateError('CLOUD_AWARD_CANDIDATE_AUTHORITY_INPUT_INVALID');
    }
    final normalized = normalizeCloudCandidateNumbers(authority.candidateNumbers);
    final universeSha = await cloudCandidateUniverseSha256(normalized);
    final pdfSha = pdfSha256.toLowerCase();
    if (authority.periodId != reference.periodId ||
        authority.tierCode != reference.tierCode ||
        authority.officialSourceUri != reference.sourceUri ||
        authority.pdfSha256.toLowerCase() != pdfSha ||
        authority.candidateUniverseSha256 != universeSha ||
        !_shaPattern.hasMatch(pdfSha) ||
        normalized.isEmpty ||
        !normalized.containsAll(authority.matchedInvoiceNumbers)) {
      throw StateError('CLOUD_AWARD_CANDIDATE_AUTHORITY_MISMATCH');
    }

    final file = await _manifestFile(
      reference: reference,
      pdfSha256: pdfSha,
      candidateUniverseSha256: universeSha,
    );
    await file.parent.create(recursive: true);
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'periodId': reference.periodId,
      'tierCode': reference.tierCode,
      'artifactId': reference.artifactId,
      'officialSourceUri': reference.sourceUri.toString(),
      'pdfSha256': pdfSha,
      'candidateUniverseSha256': universeSha,
      'matchedInvoiceNumbers': authority.matchedInvoiceNumbers.toList()..sort(),
      'verifiedAtUtc': verifiedAtUtc.toIso8601String(),
      'retentionUntilUtc': retentionUntilUtc?.toIso8601String(),
    };

    final temp = File(
      '${file.path}.candidate-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }

    final readBack = await readValidated(
      reference: reference,
      pdfSha256: pdfSha,
      candidateInvoiceNumbers: normalized,
      nowUtc: verifiedAtUtc,
    );
    if (readBack == null ||
        readBack.candidateUniverseSha256 != universeSha ||
        readBack.matchedInvoiceNumbers.length !=
            authority.matchedInvoiceNumbers.length ||
        !readBack.matchedInvoiceNumbers
            .containsAll(authority.matchedInvoiceNumbers)) {
      throw StateError('CLOUD_AWARD_CANDIDATE_AUTHORITY_READBACK_MISMATCH');
    }
    return readBack;
  }

  Future<int> pruneExpired({required DateTime nowUtc}) async {
    if (!nowUtc.isUtc) {
      throw StateError('CLOUD_AWARD_CANDIDATE_AUTHORITY_PRUNE_TIME_NOT_UTC');
    }
    final root = await _root();
    if (!await root.exists()) return 0;
    var removed = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final raw = decoded['retentionUntilUtc']?.toString();
        if (raw == null || raw.isEmpty) continue;
        final retention = DateTime.tryParse(raw)?.toUtc();
        if (retention != null && nowUtc.isAfter(retention)) {
          await entity.delete();
          removed += 1;
        }
      } catch (_) {
        // Corrupt records are ignored, never promoted as authority.
      }
    }
    return removed;
  }

  Future<File> _manifestFile({
    required OfficialCloudAwardArtifactReference reference,
    required String pdfSha256,
    required String candidateUniverseSha256,
  }) async {
    final root = await _root();
    final safePeriod = reference.periodId.replaceAll(RegExp(r'[^0-9-]'), '_');
    final safeTier = reference.tierCode.replaceAll(RegExp(r'[^a-z0-9-]'), '_');
    return File(
      '${root.path}${Platform.pathSeparator}$safePeriod'
      '${Platform.pathSeparator}$safeTier'
      '${Platform.pathSeparator}$pdfSha256-$candidateUniverseSha256.json',
    );
  }

  Future<Directory> _root() async {
    final support = await _rootDirectoryProvider();
    return Directory(
      '${support.path}${Platform.pathSeparator}invoice_award'
      '${Platform.pathSeparator}cloud_candidate_scope',
    );
  }

  static final RegExp _shaPattern = RegExp(r'^[0-9a-f]{64}$');
}
