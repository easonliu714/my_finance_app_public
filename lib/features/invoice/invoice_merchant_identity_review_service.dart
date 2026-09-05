import '../merchant/business_registry_authoritative_lookup_service.dart';
import '../merchant/business_registry_repository.dart';
import '../merchant/business_registry_update_service.dart';
import '../merchant/business_registry_validation_bootstrap.dart';
import '../merchant/merchant_identity_repository.dart';
import '../merchant/merchant_identity_resolution_policy.dart';
import '../merchant/merchant_record.dart';

class InvoiceMerchantIdentityReviewContext {
  const InvoiceMerchantIdentityReviewContext({
    required this.decision,
    required this.registryStatus,
    this.registryVersion = '',
    this.registryCoverage = '',
    this.registrySourceDataDate = '',
    this.registryRefreshAttempted = false,
    this.registryRefreshError = '',
  });

  final MerchantIdentityResolutionDecision decision;
  final BusinessRegistryLookupStatus registryStatus;
  final String registryVersion;
  final String registryCoverage;
  final String registrySourceDataDate;
  final bool registryRefreshAttempted;
  final String registryRefreshError;

  bool get hasOfficialLegalName =>
      decision.officialLegalNameSuggestion.trim().isNotEmpty;
  bool get hasConfirmedBrand => decision.formalMerchantName.trim().isNotEmpty;
  bool get isValidationSubset => registryCoverage == 'validation_subset';
}

abstract class InvoiceMerchantIdentityReviewPort {
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  });

  Future<InvoiceMerchantIdentityReviewContext> confirmBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
  });
}

class InvoiceMerchantIdentityReviewService
    implements InvoiceMerchantIdentityReviewPort {
  const InvoiceMerchantIdentityReviewService({
    this.registryRepository = const BusinessRegistryRepository(),
    this.identityRepository = const MerchantIdentityRepository(),
    this.policy = const MerchantIdentityResolutionPolicy(),
    this.validationBootstrap = const BusinessRegistryValidationBootstrap(),
    this.refreshPort = const BusinessRegistryUpdateRefreshPort(
      BusinessRegistryUpdateService(),
    ),
  });

  final BusinessRegistryRepository registryRepository;
  final MerchantIdentityRepository identityRepository;
  final MerchantIdentityResolutionPolicy policy;
  final BusinessRegistryValidationBootstrap validationBootstrap;
  final BusinessRegistryRefreshPort refreshPort;

  @override
  Future<InvoiceMerchantIdentityReviewContext> resolve({
    required String sellerIdentifier,
    required bool sellerIdentifierAuthoritative,
    required String literalMerchantText,
  }) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (!sellerIdentifierAuthoritative || seller.length != 8) {
      return InvoiceMerchantIdentityReviewContext(
        decision: policy.evaluate(
          sellerIdentifier: seller,
          sellerIdentifierAuthoritative: false,
          literalMerchantText: literalMerchantText,
        ),
        registryStatus: BusinessRegistryLookupStatus.invalidSellerIdentifier,
      );
    }

    await validationBootstrap.ensureInstalled();
    final confirmed =
        await identityRepository.findConfirmedBySellerIdentifier(seller);
    var registry = await registryRepository.lookup(seller);
    var refreshAttempted = false;
    var refreshError = '';

    // A known confirmed bookkeeping identity never needs network refresh. It
    // may still use an already-installed local registry row for legal-name
    // corroboration.
    if (confirmed == null && !registry.isHit) {
      final refreshed = await BusinessRegistryAuthoritativeLookupService(
        identityRepository: identityRepository,
        registryRepository: registryRepository,
        refreshPort: refreshPort,
      ).resolve(
        sellerIdentifier: seller,
        authoritative: true,
      );
      registry = refreshed.registryLookup ?? registry;
      refreshAttempted = refreshed.refreshAttempted;
      refreshError = refreshed.refreshError;
    }

    final officialName = registry.primaryEntity?.legalName ?? '';
    return InvoiceMerchantIdentityReviewContext(
      decision: policy.evaluate(
        sellerIdentifier: seller,
        sellerIdentifierAuthoritative: true,
        literalMerchantText: literalMerchantText,
        officialRegistryLegalName: officialName,
        existingConfirmedBrandName: confirmed?.displayName ?? '',
      ),
      registryStatus: registry.status,
      registryVersion: registry.snapshotVersion,
      registryCoverage: registry.coverage,
      registrySourceDataDate: registry.sourceDataDate,
      registryRefreshAttempted: refreshAttempted,
      registryRefreshError: refreshError,
    );
  }

  @override
  Future<InvoiceMerchantIdentityReviewContext> confirmBinding({
    required MerchantRecord merchant,
    required String sellerIdentifier,
    required String literalMerchantText,
    required String evidenceSource,
    required String sourceReference,
  }) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    await validationBootstrap.ensureInstalled();
    final registry = await registryRepository.lookup(seller);
    await identityRepository.recordConfirmedBinding(
      merchant: merchant,
      sellerIdentifier: seller,
      literalMerchantText: literalMerchantText,
      evidenceSource: evidenceSource,
      sourceReference: sourceReference,
      officialEntity: registry.primaryEntity,
      registryVersion: registry.snapshotVersion,
    );
    return resolve(
      sellerIdentifier: seller,
      sellerIdentifierAuthoritative: true,
      literalMerchantText: literalMerchantText,
    );
  }
}
