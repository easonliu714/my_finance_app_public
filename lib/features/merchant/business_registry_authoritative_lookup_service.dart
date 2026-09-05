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
///
/// P4.20.2 also guards the refresh surface at process/session scope. Repeated UI
/// resolves for the same seller, repository/refresh-port pair, and installed
/// snapshot reuse one in-flight/completed refresh result. A new installed
/// snapshot version naturally creates a new scope. This prevents merchant-text
/// edits or widget rebuilds from repeatedly probing the distribution endpoint.
class BusinessRegistryAuthoritativeLookupService {
  const BusinessRegistryAuthoritativeLookupService({
    required this.identityRepository,
    required this.registryRepository,
    required this.refreshPort,
  });

  final MerchantIdentityRepository identityRepository;
  final BusinessRegistryRepository registryRepository;
  final BusinessRegistryRefreshPort refreshPort;

  static final Map<String, Future<BusinessRegistryAuthoritativeLookupResult>>
      _inFlightRefreshes =
      <String, Future<BusinessRegistryAuthoritativeLookupResult>>{};
  static final Map<String, BusinessRegistryAuthoritativeLookupResult>
      _completedRefreshes = <String, BusinessRegistryAuthoritativeLookupResult>{};

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
    final scopeKey = _refreshScopeKey(seller, installed);
    final completed = _completedRefreshes[scopeKey];
    if (completed != null) {
      return _reuseNetworkDecisionWithLocalEvidence(completed, local);
    }

    final existing = _inFlightRefreshes[scopeKey];
    if (existing != null) {
      final shared = await existing;
      final currentLocal = await registryRepository.lookup(seller);
      return currentLocal.isHit
          ? BusinessRegistryAuthoritativeLookupResult(
              status: BusinessRegistryAuthoritativeLookupStatus.localRegistryHit,
              sellerIdentifier: seller,
              registryLookup: currentLocal,
            )
          : _reuseNetworkDecisionWithLocalEvidence(shared, currentLocal);
    }

    final future = _refreshAfterLocalMiss(
      seller: seller,
      local: local,
      installed: installed,
    );
    _inFlightRefreshes[scopeKey] = future;
    try {
      final result = await future;
      _completedRefreshes[scopeKey] = result;

      // A successful update may have advanced the installed registry version.
      // Seed that new version scope too, otherwise an immediate UI rebuild
      // would perform one redundant manifest probe against the just-installed
      // snapshot.
      if (result.refreshAttempted && result.refreshError.isEmpty) {
        final installedAfter = await registryRepository.installedSnapshot();
        final postUpdateKey = _refreshScopeKey(seller, installedAfter);
        _completedRefreshes[postUpdateKey] = result;
      }
      return result;
    } finally {
      if (identical(_inFlightRefreshes[scopeKey], future)) {
        _inFlightRefreshes.remove(scopeKey);
      }
    }
  }

  Future<BusinessRegistryAuthoritativeLookupResult> _refreshAfterLocalMiss({
    required String seller,
    required BusinessRegistryLookupResult local,
    required BusinessRegistrySnapshotInfo? installed,
  }) async {
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

  BusinessRegistryAuthoritativeLookupResult
      _reuseNetworkDecisionWithLocalEvidence(
    BusinessRegistryAuthoritativeLookupResult cached,
    BusinessRegistryLookupResult local,
  ) {
    return BusinessRegistryAuthoritativeLookupResult(
      status: cached.status,
      sellerIdentifier: cached.sellerIdentifier,
      confirmedIdentity: cached.confirmedIdentity,
      registryLookup: local,
      refreshAttempted: cached.refreshAttempted,
      refreshError: cached.refreshError,
    );
  }

  String _refreshScopeKey(
    String seller,
    BusinessRegistrySnapshotInfo? installed,
  ) {
    final version = installed?.version ?? '<none>';
    final contentSha = installed?.contentSha256 ?? '<none>';
    return '${identityHashCode(registryRepository)}|'
        '${identityHashCode(refreshPort)}|$seller|$version|$contentSha';
  }
}
