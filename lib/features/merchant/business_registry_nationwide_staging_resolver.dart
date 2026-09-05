import 'business_registry_fia_tax_registration_adapter.dart';
import 'business_registry_pack.dart';

enum BusinessRegistryNationwideStagingStatus {
  branchReadyFromFiaParent,
  legalTypeReadyFromFiaOrganization,
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
/// is sufficient to stage the seller as a branch/outlet. For parentless rows,
/// only exact FIA organization labels that directly encode a Taiwan legal form
/// are allowed to classify company/business. Residual labels such as `其他`,
/// cooperatives, limited partnerships, offices, or empty values remain pending
/// for controlled GCIS legal enrichment; display-name heuristics are forbidden.
class BusinessRegistryNationwideStagingResolver {
  const BusinessRegistryNationwideStagingResolver();

  static const Set<String> _fiaCompanyLegalForms = <String>{
    '有限公司',
    '股份有限公司',
    '無限公司',
    '兩合公司',
  };

  static const Set<String> _fiaBusinessLegalForms = <String>{
    '獨資',
    '合夥',
  };

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

    final fiaType = _directFiaEntityType(seed.organizationType);
    if (fiaType != null) {
      return BusinessRegistryNationwideStagingDecision(
        status: BusinessRegistryNationwideStagingStatus
            .legalTypeReadyFromFiaOrganization,
        seed: seed,
        entity: BusinessRegistryEntity(
          sellerIdentifier: seed.sellerIdentifier,
          entityType: fiaType,
          legalName: seed.legalName,
          registrationStatus: 'active_tax_registration',
          sourceDataset: seed.sourceDataset,
        ),
        reason: 'fia_organization_type_exact_legal_form',
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
    // GCIS exports can contain byte-for-byte-equivalent duplicate rows across
    // controlled acquisition pages. Collapse only identical canonical facts;
    // any type/name/parent/status disagreement remains visible and fails closed.
    final relevant = _dedupeIdentical(
      candidates.where(
        (candidate) => candidate.sellerIdentifier == seed.sellerIdentifier,
      ),
    );

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
    final fiaType = _directFiaEntityType(seed.organizationType);
    if (fiaType != null && fiaType != resolved.entityType) {
      return BusinessRegistryNationwideStagingDecision(
        status: BusinessRegistryNationwideStagingStatus.holdConflict,
        seed: seed,
        reason: 'gcis_legal_type_conflicts_with_fia_organization_type',
      );
    }

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
      reason: fiaType == null
          ? 'parentless_fia_row_resolved_by_single_legal_authority'
          : 'fia_organization_and_gcis_legal_type_agree',
    );
  }

  static BusinessRegistryEntityType? _directFiaEntityType(
    String organizationType,
  ) {
    final normalized = organizationType.trim();
    if (_fiaCompanyLegalForms.contains(normalized)) {
      return BusinessRegistryEntityType.company;
    }
    if (_fiaBusinessLegalForms.contains(normalized)) {
      return BusinessRegistryEntityType.business;
    }
    return null;
  }

  static List<BusinessRegistryEntity> _dedupeIdentical(
    Iterable<BusinessRegistryEntity> candidates,
  ) {
    final unique = <String, BusinessRegistryEntity>{};
    for (final candidate in candidates) {
      final key = <String>[
        candidate.sellerIdentifier,
        candidate.entityType.name,
        candidate.legalName.trim(),
        candidate.registrationStatus.trim(),
        candidate.parentSellerIdentifier.trim(),
        candidate.sourceDataset.trim(),
      ].join('\u001f');
      unique.putIfAbsent(key, () => candidate);
    }
    return unique.values.toList(growable: false);
  }

  static String _combinedSource(String fia, String enrichment) {
    final left = fia.trim();
    final right = enrichment.trim();
    if (right.isEmpty || right == left) return left;
    return '$left+$right';
  }
}
