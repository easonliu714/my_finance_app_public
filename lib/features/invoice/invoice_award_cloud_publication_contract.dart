/// Pure contract for Ministry-of-Finance cloud-exclusive award publication.
///
/// This slice deliberately performs no network I/O and stores no user invoice
/// data. It models the publication index separately from large award artifacts
/// so retries can poll lightweight publication state and fetch only missing or
/// changed authoritative artifacts.
class OfficialCloudAwardPublicationIndex {
  const OfficialCloudAwardPublicationIndex({
    required this.periodId,
    required this.sourceUri,
    required this.fetchedAt,
    required this.artifacts,
    required this.complete,
  });

  final String periodId;
  final Uri sourceUri;
  final DateTime fetchedAt;
  final List<OfficialCloudAwardArtifactDescriptor> artifacts;
  final bool complete;

  bool get isApprovedOfficialSource =>
      sourceUri.scheme == 'https' &&
      (sourceUri.host == 'invoice.etax.nat.gov.tw' ||
          sourceUri.host == 'www.etax.nat.gov.tw');
}

class OfficialCloudAwardArtifactDescriptor {
  const OfficialCloudAwardArtifactDescriptor({
    required this.artifactId,
    required this.sourceUri,
    required this.contentSha256,
    required this.tierCode,
  });

  final String artifactId;
  final Uri sourceUri;
  final String contentSha256;
  final String tierCode;

  bool get isApprovedOfficialSource =>
      sourceUri.scheme == 'https' &&
      (sourceUri.host == 'invoice.etax.nat.gov.tw' ||
          sourceUri.host == 'www.etax.nat.gov.tw');

  bool get hasValidFingerprint =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(contentSha256);
}

/// Fingerprint of a previously validated local artifact.
class ValidatedCloudAwardArtifactState {
  const ValidatedCloudAwardArtifactState({
    required this.artifactId,
    required this.contentSha256,
  });

  final String artifactId;
  final String contentSha256;
}

class OfficialCloudAwardArtifactFetchPlan {
  const OfficialCloudAwardArtifactFetchPlan._({
    required this.toFetch,
    required this.isPublicationReady,
  });

  final List<OfficialCloudAwardArtifactDescriptor> toFetch;
  final bool isPublicationReady;

  /// Fail closed unless the publication index itself is official, complete,
  /// internally unique, and every artifact has an official HTTPS source and
  /// SHA-256 fingerprint. Group counts are intentionally not encoded here:
  /// they are source data and must never become hard-coded product constants.
  factory OfficialCloudAwardArtifactFetchPlan.build({
    required OfficialCloudAwardPublicationIndex index,
    required Iterable<ValidatedCloudAwardArtifactState> localValidated,
  }) {
    final seenIds = <String>{};
    final descriptorsValid = index.artifacts.every((artifact) =>
        artifact.artifactId.isNotEmpty &&
        artifact.tierCode.isNotEmpty &&
        artifact.isApprovedOfficialSource &&
        artifact.hasValidFingerprint &&
        seenIds.add(artifact.artifactId));

    if (!index.isApprovedOfficialSource || !index.complete || !descriptorsValid) {
      return const OfficialCloudAwardArtifactFetchPlan._(
        toFetch: <OfficialCloudAwardArtifactDescriptor>[],
        isPublicationReady: false,
      );
    }

    final localById = <String, String>{
      for (final artifact in localValidated)
        artifact.artifactId: artifact.contentSha256.toLowerCase(),
    };
    final missingOrChanged = index.artifacts
        .where((artifact) =>
            localById[artifact.artifactId] !=
            artifact.contentSha256.toLowerCase())
        .toList(growable: false);

    return OfficialCloudAwardArtifactFetchPlan._(
      toFetch: missingOrChanged,
      isPublicationReady: true,
    );
  }
}