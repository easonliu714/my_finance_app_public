import '../merchant/business_registry_repository.dart';
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
  });

  final MerchantIdentityResolutionDecision decision;
  final BusinessRegistryLookupStatus registryStatus;
  final String registryVersion;
  final String registryCoverage;
  final String registrySourceDataDate;

  bool get hasOfficialLegalName =>
      decision.officialLegalNameSuggestion.trim().isNotEmpty;
  bool get hasConfirmedBrand => decision.formalMerchantName.trim().isNotEmpty;
  bool get isValidationSubset =>
      registryCoverage == 'validation_subset';
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
  });

  final BusinessRegistryRepository registryRepository;
  final MerchantIdentityRepository identityRepository;
  final MerchantIdentityResolutionPolicy policy;
  final BusinessRegistryValidationBootstrap validationBootstrap;

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
    final registry = await registryRepository.lookup(seller);
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
