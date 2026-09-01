import 'business_registry_distribution_manifest.dart';
import 'business_registry_repository.dart';
import 'business_registry_update_service.dart';
import 'merchant_identity_repository.dart';

abstract interface class BusinessRegistryRefreshPort {
  Future<BusinessRegistryDistributionManifest?> fetchAvailableManifest();

  Future<BusinessRegistryUpdateResult> update({
    BusinessRegistryDistributionManifest? knownManifest,
  });
}

class BusinessRegistryUpdateRefreshPort implements BusinessRegistryRefreshPort {
  const BusinessRegistryUpdateRefreshPort(this.service);

  final BusinessRegistryUpdateService service;

  @override
  Future<BusinessRegistryDistributionManifest?> fetchAvailableManifest() =>
      service.fetchAvailableManifest();

  @override
  Future<BusinessRegistryUpdateResult> update({
    BusinessRegistryDistributionManifest? knownManifest,
  }) =>
      service.update(knownManifest: knownManifest);
}

enum BusinessRegistryAuthoritativeLookupStatus {
  ineligible,
  knownMerchantIdentity,
  localRegistryHit,
  notFoundCurrentRegistry,
  refreshedRegistryHit,
  refreshedRegistryNotFound,
  refreshUnavailable,
  refreshFailed,
}

class BusinessRegistryAuthoritativeLookupResult {
  const BusinessRegistryAuthoritativeLookupResult({
    required this.status,
    required this.sellerIdentifier,
    this.confirmedIdentity,
    this.registryLookup,
    this.refreshAttempted = false,
    this.refreshError = '',
  });

  final BusinessRegistryAuthoritativeLookupStatus status;
  final String sellerIdentifier;
  final ConfirmedMerchantIdentity? confirmedIdentity;
  final BusinessRegistryLookupResult? registryLookup;
  final bool refreshAttempted;
  final String refreshError;

  bool get canContinueInvoiceReview => true;
}

/// Implements the Roadmap #20 unseen authoritative seller-ID contract.
///
/// The caller must explicitly state that the seller identifier already passed
/// the invoice authority gate. Known merchant identities and local registry
/// hits never perform network work. A local miss checks distribution freshness
/// and may perform at most one controlled refresh, followed by exactly one local
/// retry. Every refresh failure is converted into a non-blocking result so the
/// invoice review remains usable.
class BusinessRegistryAuthoritativeLookupService {
  const BusinessRegistryAuthoritativeLookupService({
    required this.identityRepository,
    required this.registryRepository,
    required this.refreshPort,
  });

  final MerchantIdentityRepository identityRepository;
  final BusinessRegistryRepository registryRepository;
  final BusinessRegistryRefreshPort refreshPort;

  Future<BusinessRegistryAuthoritativeLookupResult> resolve({
    required String sellerIdentifier,
    required bool authoritative,
  }) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (!authoritative || !RegExp(r'^\d{8}$').hasMatch(seller)) {
      return BusinessRegistryAuthoritativeLookupResult(
        status: BusinessRegistryAuthoritativeLookupStatus.ineligible,
        sellerIdentifier: seller,
      );
    }

    final known =
        await identityRepository.findConfirmedBySellerIdentifier(seller);
    if (known != null) {
      return BusinessRegistryAuthoritativeLookupResult(
        status:
            BusinessRegistryAuthoritativeLookupStatus.knownMerchantIdentity,
        sellerIdentifier: seller,
        confirmedIdentity: known,
      );
    }

    final local = await registryRepository.lookup(seller);
    if (local.status == BusinessRegistryLookupStatus.hit) {
      return BusinessRegistryAuthoritativeLookupResult(
        status: BusinessRegistryAuthoritativeLookupStatus.localRegistryHit,
        sellerIdentifier: seller,
        registryLookup: local,
      );
    }
    if (local.status == BusinessRegistryLookupStatus.invalidSellerIdentifier) {
      return BusinessRegistryAuthoritativeLookupResult(
        status: BusinessRegistryAuthoritativeLookupStatus.ineligible,
        sellerIdentifier: seller,
        registryLookup: local,
      );
    }

    final installed = await registryRepository.installedSnapshot();
    BusinessRegistryDistributionManifest? available;
    try {
      available = await refreshPort.fetchAvailableManifest();
    } catch (error) {
      return BusinessRegistryAuthoritativeLookupResult(
        status: BusinessRegistryAuthoritativeLookupStatus.refreshFailed,
        sellerIdentifier: seller,
        registryLookup: local,
        refreshError: error.toString(),
      );
    }

    if (available == null) {
      return BusinessRegistryAuthoritativeLookupResult(
        status: installed == null
            ? BusinessRegistryAuthoritativeLookupStatus.refreshUnavailable
            : BusinessRegistryAuthoritativeLookupStatus.notFoundCurrentRegistry,
        sellerIdentifier: seller,
        registryLookup: local,
      );
    }

    if (installed != null && installed.version == available.registryVersion) {
      if (installed.contentSha256 != available.registryContentSha256) {
        return BusinessRegistryAuthoritativeLookupResult(
          status: BusinessRegistryAuthoritativeLookupStatus.refreshFailed,
          sellerIdentifier: seller,
          registryLookup: local,
          refreshError: 'REGISTRY_AVAILABLE_VERSION_CONTENT_CONFLICT',
        );
      }
      return BusinessRegistryAuthoritativeLookupResult(
        status:
            BusinessRegistryAuthoritativeLookupStatus.notFoundCurrentRegistry,
        sellerIdentifier: seller,
        registryLookup: local,
      );
    }

    try {
      await refreshPort.update(knownManifest: available);
      final retried = await registryRepository.lookup(seller);
      return BusinessRegistryAuthoritativeLookupResult(
        status: retried.status == BusinessRegistryLookupStatus.hit
            ? BusinessRegistryAuthoritativeLookupStatus.refreshedRegistryHit
            : BusinessRegistryAuthoritativeLookupStatus
                .refreshedRegistryNotFound,
        sellerIdentifier: seller,
        registryLookup: retried,
        refreshAttempted: true,
      );
    } catch (error) {
      return BusinessRegistryAuthoritativeLookupResult(
        status: BusinessRegistryAuthoritativeLookupStatus.refreshFailed,
        sellerIdentifier: seller,
        registryLookup: local,
        refreshAttempted: true,
        refreshError: error.toString(),
      );
    }
  }
}
