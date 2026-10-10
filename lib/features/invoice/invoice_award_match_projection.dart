enum InvoiceAwardProjectionDomain {
  general,
  cloudExclusive,
}

/// Read-only local projection for an already validated official award match.
///
/// This object deliberately has no persistence, network, payout, or formal
/// accounting write capability. It is safe to render on the Award Check page.
class InvoiceAwardMatchProjection {
  const InvoiceAwardMatchProjection({
    required this.periodId,
    required this.domain,
    required this.tierLabel,
    required this.grossAmount,
    required this.redemptionStart,
    required this.redemptionEnd,
    required this.officialDatasetFingerprint,
    required this.parserRuleVersion,
    required this.eligibilityWarning,
    required this.exclusionWarnings,
  });

  final String periodId;
  final InvoiceAwardProjectionDomain domain;
  final String tierLabel;
  final int grossAmount;
  final DateTime redemptionStart;
  final DateTime redemptionEnd;
  final String officialDatasetFingerprint;
  final String parserRuleVersion;
  final String? eligibilityWarning;
  final List<String> exclusionWarnings;

  bool get hasValidProvenance =>
      periodId.trim().isNotEmpty &&
      tierLabel.trim().isNotEmpty &&
      grossAmount > 0 &&
      redemptionStart.isUtc &&
      redemptionEnd.isUtc &&
      !redemptionEnd.isBefore(redemptionStart) &&
      officialDatasetFingerprint.trim().isNotEmpty &&
      parserRuleVersion.trim().isNotEmpty;

  bool get requiresReview =>
      !hasValidProvenance ||
      (eligibilityWarning?.trim().isNotEmpty ?? false) ||
      exclusionWarnings.isNotEmpty;

  bool get canCreateFormalTransaction => false;
  bool get canRedeemOrClaim => false;
  bool get canConfigureAutomaticRemittance => false;
}

/// Fail-closed builder used after local matching against validated datasets.
class InvoiceAwardMatchProjectionBuilder {
  const InvoiceAwardMatchProjectionBuilder();

  InvoiceAwardMatchProjection? build({
    required String periodId,
    required InvoiceAwardProjectionDomain domain,
    required String tierLabel,
    required int grossAmount,
    required DateTime redemptionStart,
    required DateTime redemptionEnd,
    required String officialDatasetFingerprint,
    required String parserRuleVersion,
    String? eligibilityWarning,
    Iterable<String> exclusionWarnings = const <String>[],
  }) {
    final projection = InvoiceAwardMatchProjection(
      periodId: periodId.trim(),
      domain: domain,
      tierLabel: tierLabel.trim(),
      grossAmount: grossAmount,
      redemptionStart: redemptionStart,
      redemptionEnd: redemptionEnd,
      officialDatasetFingerprint: officialDatasetFingerprint.trim(),
      parserRuleVersion: parserRuleVersion.trim(),
      eligibilityWarning: eligibilityWarning?.trim(),
      exclusionWarnings: List<String>.unmodifiable(
        exclusionWarnings.map((item) => item.trim()).where((item) => item.isNotEmpty),
      ),
    );
    return projection.hasValidProvenance ? projection : null;
  }
}
