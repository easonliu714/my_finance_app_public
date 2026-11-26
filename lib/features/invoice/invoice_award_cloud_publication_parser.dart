class OfficialCloudAwardArtifactReference {
  const OfficialCloudAwardArtifactReference({
    required this.artifactId,
    required this.sourceUri,
    required this.periodId,
    required this.tierCode,
  });

  final String artifactId;
  final Uri sourceUri;
  final String periodId;
  final String tierCode;

  bool get isApprovedOfficialSource =>
      sourceUri.scheme == 'https' &&
      sourceUri.host == 'invoice.etax.nat.gov.tw' &&
      sourceUri.path.startsWith('/pdf/') &&
      sourceUri.path.endsWith('.pdf');
}

class OfficialCloudAwardPublicationReferenceIndex {
  const OfficialCloudAwardPublicationReferenceIndex({
    required this.periodId,
    required this.sourceUri,
    required this.fetchedAt,
    required this.artifacts,
  });

  final String periodId;
  final Uri sourceUri;
  final DateTime fetchedAt;
  final List<OfficialCloudAwardArtifactReference> artifacts;

  bool get isComplete {
    if (sourceUri.scheme != 'https' ||
        sourceUri.host != 'invoice.etax.nat.gov.tw') {
      return false;
    }
    const required = <String>{
      'cloud-500',
      'cloud-800',
      'cloud-2000',
      'cloud-1000000',
    };
    final tiers = artifacts.map((item) => item.tierCode).toSet();
    return artifacts.length == required.length &&
        tiers.length == required.length &&
        tiers.containsAll(required) &&
        artifacts.every(
          (item) =>
              item.periodId == periodId &&
              item.isApprovedOfficialSource &&
              item.artifactId.isNotEmpty,
        );
  }
}

/// Strict parser for the credential-free public MOF cloud-exclusive award page.
///
/// Only the four *sorted* official PDF links are accepted. The alternative
/// draw-order PDFs are intentionally ignored so each tier has exactly one
/// canonical public artifact for local matching.
class MinistryOfFinanceCloudAwardPublicationHtmlParser {
  const MinistryOfFinanceCloudAwardPublicationHtmlParser();

  static final RegExp _anchorPattern = RegExp(
    r'''<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  OfficialCloudAwardPublicationReferenceIndex parse({
    required Uri sourceUri,
    required String html,
    required String expectedPeriodId,
    required DateTime fetchedAt,
  }) {
    if (sourceUri.scheme != 'https' ||
        sourceUri.host != 'invoice.etax.nat.gov.tw' ||
        !const <String>{
          '/cloudNowNumber.html',
          '/cloudLastNumber.html',
        }.contains(sourceUri.path)) {
      throw const FormatException(
        'unsupported Ministry of Finance cloud-award publication surface',
      );
    }

    final marker = _periodMarker(expectedPeriodId);
    final visible = _plainText(html);
    if (!visible.contains(marker)) {
      throw FormatException('expected cloud award period not found: $marker');
    }

    final artifacts = <OfficialCloudAwardArtifactReference>[];
    final seenTiers = <String>{};

    for (final match in _anchorPattern.allMatches(html)) {
      final rawHref = _decodeBasicEntities(match.group(1) ?? '').trim();
      final label = _plainText(match.group(2) ?? '');
      if (!label.contains('PDF') || !label.contains('已排序')) continue;

      final tier = _tierCodeForLabel(label);
      if (tier == null) continue;
      if (!seenTiers.add(tier)) {
        throw FormatException('duplicate sorted cloud artifact tier: $tier');
      }

      final uri = sourceUri.resolve(rawHref);
      if (uri.scheme != 'https' ||
          uri.host != 'invoice.etax.nat.gov.tw' ||
          !uri.path.startsWith('/pdf/') ||
          !uri.path.endsWith('.pdf')) {
        throw FormatException('unapproved cloud award artifact URI: $uri');
      }

      final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      if (!_looksLikeSortedOfficialArtifact(name)) {
        throw FormatException('unexpected sorted cloud artifact name: $name');
      }

      artifacts.add(
        OfficialCloudAwardArtifactReference(
          artifactId: name,
          sourceUri: uri,
          periodId: expectedPeriodId,
          tierCode: tier,
        ),
      );
    }

    final index = OfficialCloudAwardPublicationReferenceIndex(
      periodId: expectedPeriodId,
      sourceUri: sourceUri,
      fetchedAt: fetchedAt,
      artifacts: List<OfficialCloudAwardArtifactReference>.unmodifiable(
        artifacts,
      ),
    );
    if (!index.isComplete) {
      throw const FormatException(
        'cloud award publication must contain exactly four sorted tiers',
      );
    }
    return index;
  }

  String _periodMarker(String periodId) {
    final match = RegExp(r'^(\d{3})-(\d{2})-(\d{2})$').firstMatch(periodId);
    if (match == null) {
      throw FormatException('invalid award period id: $periodId');
    }
    return '${match.group(1)}年${match.group(2)}-${match.group(3)}月';
  }

  String? _tierCodeForLabel(String label) {
    if (label.contains('五百元獎')) return 'cloud-500';
    if (label.contains('八百元獎')) return 'cloud-800';
    if (label.contains('兩千元獎')) return 'cloud-2000';
    if (label.contains('百萬元獎')) return 'cloud-1000000';
    return null;
  }

  bool _looksLikeSortedOfficialArtifact(String name) {
    return RegExp(
      r'^\d{8}_\d{14}_sorted_AI_[A-Z]\.pdf$',
      caseSensitive: false,
    ).hasMatch(name);
  }

  String _plainText(String html) {
    final withoutTags = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeBasicEntities(withoutTags)
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  String _decodeBasicEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}