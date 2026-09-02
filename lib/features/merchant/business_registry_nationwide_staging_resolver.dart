import 'business_registry_fia_tax_registration_adapter.dart';
import 'business_registry_pack.dart';

enum BusinessRegistryNationwideStagingStatus {
  branchReadyFromFiaParent,
  needsLegalTypeEnrichment,
  resolvedWithLegalEnrichment,
  holdConflict,
}

class BusinessRegistryNationwideStagingDecision {
  const BusinessRegistryNationwideStagingDecision({
    required this.status,
    required this.seed,
    this.entity,
    this.reason = '',
  });

  final BusinessRegistryNationwideStagingStatus status;
  final BusinessRegistryNationwideInvoiceSellerSeed seed;
  final BusinessRegistryEntity? entity;
  final String reason;

  bool get isReady => entity != null &&
      status != BusinessRegistryNationwideStagingStatus.holdConflict;
}

/// Converts the nationwide FIA coverage spine into fail-closed staging
/// decisions before canonical pack emission.
///
/// A non-empty FIA head-office identifier is strong parent-child evidence and
/// is sufficient to stage the seller as a branch/outlet. Parentless rows are
/// never guessed as company or business from display name / organization text;
/// they remain pending until a controlled legal-registration enrichment source
/// supplies one unambiguous canonical type.
class BusinessRegistryNationwideStagingResolver {
  const BusinessRegistryNationwideStagingResolver();

  BusinessRegistryNationwideStagingDecision stage(
    BusinessRegistryNationwideInvoiceSellerSeed seed,
  ) {
    if (seed.hasParent) {
      return BusinessRegistryNationwideStagingDecision(
        status:
            BusinessRegistryNationwideStagingStatus.branchReadyFromFiaParent,
        seed: seed,
        entity: BusinessRegistryEntity(
          sellerIdentifier: seed.sellerIdentifier,
          entityType: BusinessRegistryEntityType.branch,
          legalName: seed.legalName,
          registrationStatus: 'active_tax_registration',
          parentSellerIdentifier: seed.parentSellerIdentifier,
          sourceDataset: seed.sourceDataset,
        ),
        reason: 'fia_head_office_identifier_branch_evidence',
      );
    }
    return BusinessRegistryNationwideStagingDecision(
      status: BusinessRegistryNationwideStagingStatus.needsLegalTypeEnrichment,
      seed: seed,
      reason: 'parentless_fia_row_requires_company_or_business_authority',
    );
  }

  BusinessRegistryNationwideStagingDecision resolveWithLegalEnrichment({
    required BusinessRegistryNationwideInvoiceSellerSeed seed,
    required Iterable<BusinessRegistryEntity> candidates,
  }) {
    final relevant = candidates
        .where((candidate) => candidate.sellerIdentifier == seed.sellerIdentifier)
        .toList(growable: false);

    if (seed.hasParent) {
      final conflictingType = relevant.any(
        (candidate) => candidate.entityType != BusinessRegistryEntityType.branch,
      );
      final conflictingParent = relevant.any(
        (candidate) =>
            candidate.entityType == BusinessRegistryEntityType.branch &&
            candidate.parentSellerIdentifier.isNotEmpty &&
            candidate.parentSellerIdentifier != seed.parentSellerIdentifier,
      );
      if (conflictingType || conflictingParent || relevant.length > 1) {
        return BusinessRegistryNationwideStagingDecision(
          status: BusinessRegistryNationwideStagingStatus.holdConflict,
          seed: seed,
          reason: conflictingParent
              ? 'gcis_branch_parent_conflicts_with_fia_parent'
              : 'gcis_branch_identity_ambiguous',
        );
      }
      if (relevant.isEmpty) return stage(seed);
      final branch = relevant.single;
      return BusinessRegistryNationwideStagingDecision(
        status:
            BusinessRegistryNationwideStagingStatus.resolvedWithLegalEnrichment,
        seed: seed,
        entity: BusinessRegistryEntity(
          sellerIdentifier: seed.sellerIdentifier,
          entityType: BusinessRegistryEntityType.branch,
          legalName: branch.legalName.trim().isEmpty
              ? seed.legalName
              : branch.legalName.trim(),
          registrationStatus: branch.registrationStatus,
          parentSellerIdentifier: seed.parentSellerIdentifier,
          sourceDataset: _combinedSource(seed.sourceDataset, branch.sourceDataset),
        ),
        reason: 'fia_parent_and_gcis_branch_agree',
      );
    }

    final legal = relevant
        .where(
          (candidate) =>
              candidate.entityType == BusinessRegistryEntityType.company ||
              candidate.entityType == BusinessRegistryEntityType.business,
        )
        .toList(growable: false);
    final unexpectedBranch = relevant.any(
      (candidate) => candidate.entityType == BusinessRegistryEntityType.branch,
    );
    if (unexpectedBranch || legal.length > 1) {
      return BusinessRegistryNationwideStagingDecision(
        status: BusinessRegistryNationwideStagingStatus.holdConflict,
        seed: seed,
        reason: unexpectedBranch
            ? 'parentless_fia_row_conflicts_with_branch_enrichment'
            : 'company_business_enrichment_ambiguous',
      );
    }
    if (legal.isEmpty) return stage(seed);

    final resolved = legal.single;
    return BusinessRegistryNationwideStagingDecision(
      status:
          BusinessRegistryNationwideStagingStatus.resolvedWithLegalEnrichment,
      seed: seed,
      entity: BusinessRegistryEntity(
        sellerIdentifier: seed.sellerIdentifier,
        entityType: resolved.entityType,
        legalName: resolved.legalName.trim().isEmpty
            ? seed.legalName
            : resolved.legalName.trim(),
        registrationStatus: resolved.registrationStatus,
        sourceDataset: _combinedSource(seed.sourceDataset, resolved.sourceDataset),
      ),
      reason: 'parentless_fia_row_resolved_by_single_legal_authority',
    );
  }

  static String _combinedSource(String fia, String enrichment) {
    final left = fia.trim();
    final right = enrichment.trim();
    if (right.isEmpty || right == left) return left;
    return '$left+$right';
  }
}
