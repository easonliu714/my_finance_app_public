/// Issue #13 local bookkeeping proposal for an externally remitted invoice prize.
///
/// This contract deliberately has zero transaction-write authority. It only
/// carries enough provenance to build an idempotent, explicitly reviewable
/// bookkeeping proposal after a prize has been confirmed and the externally
/// configured MOF remittance date has been reached.
class InvoiceAwardPayoutBookkeepingProposal {
  const InvoiceAwardPayoutBookkeepingProposal({
    required this.invoiceIdentity,
    required this.awardPeriodId,
    required this.prizeTier,
    required this.grossAmount,
    required this.localAccountId,
    required this.externalRemittanceEligibleAt,
    required this.officialDatasetFingerprint,
    required this.parserRuleVersion,
  });

  final String invoiceIdentity;
  final String awardPeriodId;
  final String prizeTier;
  final int grossAmount;
  final String localAccountId;
  final DateTime externalRemittanceEligibleAt;
  final String officialDatasetFingerprint;
  final String parserRuleVersion;

  /// Stable source-domain key used to prevent duplicate proposal/posting work.
  ///
  /// A repository may persist this key only under a separately authorized
  /// transaction-write slice. This domain object itself never writes.
  String get idempotencyKey =>
      'invoice-award:$awardPeriodId:$invoiceIdentity:$prizeTier';

  bool get hasValidProvenance =>
      invoiceIdentity.trim().isNotEmpty &&
      awardPeriodId.trim().isNotEmpty &&
      prizeTier.trim().isNotEmpty &&
      grossAmount > 0 &&
      localAccountId.trim().isNotEmpty &&
      externalRemittanceEligibleAt.isUtc &&
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(officialDatasetFingerprint) &&
      parserRuleVersion.trim().isNotEmpty;

  bool isEligibleForBookkeepingProposalAt(DateTime now) =>
      hasValidProvenance &&
      now.isUtc &&
      !now.isBefore(externalRemittanceEligibleAt);

  bool get canCreateFormalTransaction => false;
  bool get canConfigureMofRemittance => false;
  bool get canClaimPrize => false;
}

/// Fail-closed builder for a local bookkeeping proposal.
///
/// `explicitUserAuthorization` represents a local user decision to prepare the
/// bookkeeping draft. It is not authority to claim a prize or configure MOF
/// remittance, and it never bypasses the normal editable-draft + explicit Save
/// transaction boundary.
class InvoiceAwardPayoutBookkeepingProposalBuilder {
  const InvoiceAwardPayoutBookkeepingProposalBuilder();

  InvoiceAwardPayoutBookkeepingProposal? build({
    required InvoiceAwardPayoutBookkeepingProposal candidate,
    required DateTime now,
    required bool explicitUserAuthorization,
    required bool externalMofRemittanceConfigured,
  }) {
    if (!explicitUserAuthorization || !externalMofRemittanceConfigured) {
      return null;
    }
    if (!candidate.isEligibleForBookkeepingProposalAt(now)) return null;
    return candidate;
  }
}
