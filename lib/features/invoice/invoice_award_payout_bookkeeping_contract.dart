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

  // Owner option C: aliases and inconsistent cloud amounts must not bypass
  // the formal ledger's deferred 500-tier boundary. Preserve raw provenance
  // and historical idempotency keys; only new proposal/post authority is denied.
  bool get isDeferredCloud500Prize {
    final tier = prizeTier.trim().toLowerCase();
    return tier == 'cloud-500' ||
        (tier.startsWith('cloud') && grossAmount == 500);
  }

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
    // A valid old SHA/receipt does not re-enable cloud-500 under Owner C.
    if (candidate.isDeferredCloud500Prize ||
        !explicitUserAuthorization ||
        !externalMofRemittanceConfigured) {
      return null;
    }
    if (!candidate.isEligibleForBookkeepingProposalAt(now)) return null;
    return candidate;
  }
}
