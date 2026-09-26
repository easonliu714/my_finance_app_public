import 'invoice_award_match_projection.dart';

/// Read-only presentation contract for the Issue #13 Award Check surface.
///
/// It intentionally cannot redeem prizes, configure MOF remittance, perform
/// network acquisition, or create a formal accounting transaction.
class InvoiceAwardCheckPresentation {
  const InvoiceAwardCheckPresentation({
    required this.periodId,
    required this.tierLabel,
    required this.grossAmount,
    required this.redemptionStart,
    required this.redemptionEnd,
    required this.reviewRequired,
    required this.warnings,
    required this.officialDatasetFingerprint,
    required this.parserRuleVersion,
  });

  final String periodId;
  final String tierLabel;
  final int grossAmount;
  final DateTime redemptionStart;
  final DateTime redemptionEnd;
  final bool reviewRequired;
  final List<String> warnings;
  final String officialDatasetFingerprint;
  final String parserRuleVersion;

  static const String redemptionDisclosure =
      '本 App 僅提供中獎比對與記帳輔助，不是兌獎或領獎平台。';
  static const String remittanceDisclosure =
      '本 App 不會設定或執行財政部自動匯款；相關設定須於官方管道完成。';

  bool get canCreateFormalTransaction => false;
  bool get canRedeemOrClaim => false;
  bool get canConfigureAutomaticRemittance => false;
}

class InvoiceAwardCheckPresentationBuilder {
  const InvoiceAwardCheckPresentationBuilder();

  /// Builds only from a provenance-valid local match projection. Ambiguous or
  /// incomplete source evidence fails closed and is not renderable as a prize.
  InvoiceAwardCheckPresentation? build(InvoiceAwardMatchProjection projection) {
    if (!projection.hasValidProvenance) return null;

    final warnings = <String>[
      if (projection.eligibilityWarning?.trim().isNotEmpty ?? false)
        projection.eligibilityWarning!.trim(),
      ...projection.exclusionWarnings,
    ];

    return InvoiceAwardCheckPresentation(
      periodId: projection.periodId,
      tierLabel: projection.tierLabel,
      grossAmount: projection.grossAmount,
      redemptionStart: projection.redemptionStart,
      redemptionEnd: projection.redemptionEnd,
      reviewRequired: projection.requiresReview,
      warnings: List<String>.unmodifiable(warnings),
      officialDatasetFingerprint: projection.officialDatasetFingerprint,
      parserRuleVersion: projection.parserRuleVersion,
    );
  }
}
