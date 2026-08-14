import 'dart:async';

import 'package:flutter/widgets.dart';

import 'authenticated_selector_capability_probe.dart';
import 'official_invoice_detail_enrichment.dart';
import 'official_query_page_preparation.dart';

enum DisposableWebViewSessionPhase {
  consent,
  starting,
  active,
  cleaning,
  completed,
  blocked,
  failed,
}

abstract interface class DisposableWebViewSessionRuntime {
  Future<void> open(Uri initialUri);
  Widget buildView();
  Future<void> clearSession();
  void dispose();
}

typedef DisposableWebViewSessionRuntimeFactory =
    DisposableWebViewSessionRuntime Function();

class DisposableWebViewSessionController extends ChangeNotifier {
  DisposableWebViewSessionController({
    required DisposableWebViewSessionRuntimeFactory runtimeFactory,
    Duration cleanupTimeout = const Duration(seconds: 20),
    Duration selectorProbeTimeout = const Duration(seconds: 8),
    Duration pagePreparationTimeout = const Duration(seconds: 15),
    Duration pagePreparationInitialReloadDelay =
        const Duration(milliseconds: 900),
    Duration pagePreparationPollInterval = const Duration(milliseconds: 250),
  })  : _runtimeFactory = runtimeFactory,
        _cleanupTimeout = cleanupTimeout,
        _selectorProbeTimeout = selectorProbeTimeout,
        _pagePreparationTimeout = pagePreparationTimeout,
        _pagePreparationInitialReloadDelay =
            pagePreparationInitialReloadDelay,
        _pagePreparationPollInterval = pagePreparationPollInterval;

  final DisposableWebViewSessionRuntimeFactory _runtimeFactory;
  final Duration _cleanupTimeout;
  final Duration _selectorProbeTimeout;
  final Duration _pagePreparationTimeout;
  final Duration _pagePreparationInitialReloadDelay;
  final Duration _pagePreparationPollInterval;
  DisposableWebViewSessionRuntime? _runtime;
  DisposableWebViewSessionPhase _phase =
      DisposableWebViewSessionPhase.consent;
  bool _consentAccepted = false;
  String? _errorMessage;

  DisposableWebViewSessionPhase get phase => _phase;
  bool get consentAccepted => _consentAccepted;
  String? get errorMessage => _errorMessage;
  bool get hasRuntime => _runtime != null;
  bool get canStart =>
      _phase == DisposableWebViewSessionPhase.consent && _consentAccepted;
  bool get canEnd => _phase == DisposableWebViewSessionPhase.active;
  bool get canProbeAuthenticatedSelectors =>
      _phase == DisposableWebViewSessionPhase.active &&
      _runtime is AuthenticatedSelectorCapabilityProbeRuntime;
  bool get canPrepareOfficialQueryPage =>
      _phase == DisposableWebViewSessionPhase.active &&
      _runtime is OfficialQueryPagePreparationRuntime;
  bool get canEnrichOfficialInvoiceDetails =>
      _phase == DisposableWebViewSessionPhase.active &&
      _runtime is OfficialInvoiceDetailEnrichmentRuntime;
  bool get isBlocked => _phase == DisposableWebViewSessionPhase.blocked;

  Widget? buildRuntimeView() => _runtime?.buildView();

  void setConsentAccepted(bool value) {
    if (_phase != DisposableWebViewSessionPhase.consent ||
        _consentAccepted == value) {
      return;
    }
    _consentAccepted = value;
    notifyListeners();
  }

  Future<void> start(Uri initialUri) async {
    if (!canStart) throw StateError('SESSION_CONSENT_REQUIRED');
    if (initialUri.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(
        initialUri,
        'initialUri',
        'Only HTTPS WebView sessions are allowed.',
      );
    }

    _phase = DisposableWebViewSessionPhase.starting;
    _errorMessage = null;
    notifyListeners();

    final runtime = _runtimeFactory();
    _runtime = runtime;
    try {
      await runtime.open(initialUri);
      _phase = DisposableWebViewSessionPhase.active;
      notifyListeners();
    } catch (error) {
      await _handleStartFailure(runtime, error);
    }
  }

  Future<AuthenticatedSelectorCapabilityReport>
      probeAuthenticatedSelectorCapabilities() async {
    if (_phase != DisposableWebViewSessionPhase.active) {
      throw StateError('SESSION_NOT_ACTIVE');
    }
    final runtime = _runtime;
    if (runtime == null) throw StateError('SESSION_RUNTIME_MISSING');
    if (runtime case AuthenticatedSelectorCapabilityProbeRuntime probeRuntime) {
      return probeRuntime.probeSelectorCapabilities().timeout(
        _selectorProbeTimeout,
        onTimeout: () => throw TimeoutException(
          'SESSION_SELECTOR_PROBE_TIMEOUT',
          _selectorProbeTimeout,
        ),
      );
    }
    throw StateError('SESSION_PROBE_UNSUPPORTED');
  }

  Future<OfficialQueryPagePreparationResult>
      prepareOfficialQueryPageForExport() async {
    if (_phase != DisposableWebViewSessionPhase.active) {
      throw StateError('SESSION_NOT_ACTIVE');
    }
    final runtime = _runtime;
    if (runtime == null) throw StateError('SESSION_RUNTIME_MISSING');
    if (runtime is! OfficialQueryPagePreparationRuntime) {
      throw StateError('SESSION_PAGE_PREPARATION_UNSUPPORTED');
    }
    final preparationRuntime = runtime as OfficialQueryPagePreparationRuntime;

    var result = await preparationRuntime.prepareCurrentPageForExport();
    if (result.exportReady || !_shouldRetryPagePreparation(result)) {
      return result;
    }

    if (result.pageSizeApplyTriggered &&
        _pagePreparationInitialReloadDelay > Duration.zero) {
      await Future<void>.delayed(_pagePreparationInitialReloadDelay);
    }

    final deadline = DateTime.now().add(_pagePreparationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_phase != DisposableWebViewSessionPhase.active ||
          !identical(_runtime, runtime)) {
        return result;
      }
      if (_pagePreparationPollInterval > Duration.zero) {
        await Future<void>.delayed(_pagePreparationPollInterval);
      }
      if (_phase != DisposableWebViewSessionPhase.active ||
          !identical(_runtime, runtime)) {
        return result;
      }

      result = await preparationRuntime.prepareCurrentPageForExport();
      if (result.exportReady || !_shouldRetryPagePreparation(result)) {
        return result;
      }
    }
    return result;
  }

  bool _shouldRetryPagePreparation(
    OfficialQueryPagePreparationResult result,
  ) {
    return switch (result.code) {
      'PAGE_SIZE_APPLY_TRIGGERED' ||
      'PAGE_SIZE_ALREADY_APPLIED' ||
      'PAGE_SIZE_APPLY_CONTROL_NOT_FOUND' ||
      'DESKTOP_RESULT_LAYOUT_NOT_READY' ||
      'RESULT_TABLE_RELOADING' ||
      'PAGE_PREPARATION_EXECUTION_FAILED' ||
      'CSV_EXPORT_CHECKBOX_NOT_FOUND' ||
      'CSV_EXPORT_CHECKBOX_ROLE_AMBIGUOUS' ||
      'CSV_EXPORT_SELECTION_INCOMPLETE' ||
      'CSV_EXPORT_BUTTON_NOT_FOUND' ||
      'CSV_EXPORT_BUTTON_ROLE_AMBIGUOUS' ||
      'CSV_EXPORT_BUTTON_STILL_DISABLED' =>
        true,
      _ => false,
    };
  }

  Future<OfficialQueryPagePreparationResult?>
      _prepareOfficialDetailPageIfSupported() async {
    final runtime = _runtime;
    if (runtime == null || runtime is! OfficialDetailPagePreparationRuntime) {
      return null;
    }
    final preparationRuntime = runtime as OfficialDetailPagePreparationRuntime;

    var result = await preparationRuntime.prepareCurrentPageForOfficialDetail();
    if (result.detailReady || !_shouldRetryPagePreparation(result)) {
      return result;
    }
    if (result.pageSizeApplyTriggered &&
        _pagePreparationInitialReloadDelay > Duration.zero) {
      await Future<void>.delayed(_pagePreparationInitialReloadDelay);
    }

    final deadline = DateTime.now().add(_pagePreparationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_phase != DisposableWebViewSessionPhase.active ||
          !identical(_runtime, runtime)) {
        return result;
      }
      if (_pagePreparationPollInterval > Duration.zero) {
        await Future<void>.delayed(_pagePreparationPollInterval);
      }
      result = await preparationRuntime.prepareCurrentPageForOfficialDetail();
      if (result.detailReady || !_shouldRetryPagePreparation(result)) {
        return result;
      }
    }
    return result;
  }

  Future<OfficialInvoiceDetailTargetReport> inspectOfficialDetailTargets() async {
    if (_phase != DisposableWebViewSessionPhase.active) {
      throw StateError('SESSION_NOT_ACTIVE');
    }
    final runtime = _runtime;
    if (runtime == null) throw StateError('SESSION_RUNTIME_MISSING');
    if (runtime is! OfficialInvoiceDetailEnrichmentRuntime) {
      throw StateError('SESSION_OFFICIAL_DETAIL_UNSUPPORTED');
    }
    // Selection inspection must be read-only. Preparing the query page
    // changes the page size and rerenders the official table, which clears
    // the user's first checkbox selection.
    final detailRuntime =
        runtime as OfficialInvoiceDetailEnrichmentRuntime;
    return detailRuntime.inspectOfficialDetailTargets().timeout(
      _selectorProbeTimeout,
      onTimeout: () => throw TimeoutException(
        'SESSION_OFFICIAL_DETAIL_INSPECTION_TIMEOUT',
        _selectorProbeTimeout,
      ),
    );
  }

  Future<OfficialInvoiceDetailBatchResult> enrichOfficialInvoiceDetails({
    required OfficialInvoiceDetailSelectionScope scope,
    String? singleInvoiceNumber,
    required void Function(OfficialInvoiceDetailProgress progress) onProgress,
  }) async {
    if (_phase != DisposableWebViewSessionPhase.active) {
      throw StateError('SESSION_NOT_ACTIVE');
    }
    final runtime = _runtime;
    if (runtime == null) throw StateError('SESSION_RUNTIME_MISSING');
    if (runtime is! OfficialInvoiceDetailEnrichmentRuntime) {
      throw StateError('SESSION_OFFICIAL_DETAIL_UNSUPPORTED');
    }
    // Only the explicit all-results scope requires the destructive
    // 10-to-100 row transition. Selected and single-invoice scopes must
    // preserve the current DOM checkbox state.
    if (scope == OfficialInvoiceDetailSelectionScope.currentPage) {
      final preparation = await _prepareOfficialDetailPageIfSupported();
      if (preparation != null && !preparation.detailReady) {
        throw StateError(
          'DETAIL_PAGE_SIZE_100_NOT_READY:${preparation.code}',
        );
      }
    }
    final detailRuntime =
        runtime as OfficialInvoiceDetailEnrichmentRuntime;
    return detailRuntime.enrichOfficialInvoiceDetails(
      scope: scope,
      singleInvoiceNumber: singleInvoiceNumber,
      onProgress: onProgress,
    );
  }

  Future<void> cancelOfficialInvoiceDetailEnrichment() async {
    final runtime = _runtime;
    if (_phase != DisposableWebViewSessionPhase.active ||
        runtime is! OfficialInvoiceDetailEnrichmentRuntime) {
      return;
    }
    final detailRuntime =
        runtime as OfficialInvoiceDetailEnrichmentRuntime;
    await detailRuntime.cancelOfficialInvoiceDetailEnrichment();
  }

  Future<void> finish() => _endSession();

  /// Lifecycle policy belongs to the page that observes Android state changes.
  Future<void> cancel() => _endSession();

  Future<void> _endSession() async {
    if (!canEnd) throw StateError('SESSION_NOT_ACTIVE');
    final runtime = _runtime;
    if (runtime == null) {
      _block('SESSION_RUNTIME_MISSING');
      return;
    }

    _phase = DisposableWebViewSessionPhase.cleaning;
    _errorMessage = null;
    notifyListeners();

    try {
      await _clearRuntime(runtime);
      runtime.dispose();
      _runtime = null;
      _consentAccepted = false;
      _phase = DisposableWebViewSessionPhase.completed;
      notifyListeners();
    } catch (error) {
      runtime.dispose();
      _runtime = null;
      _block('SESSION_CLEANUP_FAILED: $error');
    }
  }

  Future<void> _clearRuntime(DisposableWebViewSessionRuntime runtime) {
    return runtime.clearSession().timeout(
      _cleanupTimeout,
      onTimeout: () => throw TimeoutException(
        'SESSION_CLEANUP_TIMEOUT',
        _cleanupTimeout,
      ),
    );
  }

  void resetAfterCompletion() {
    if (_phase == DisposableWebViewSessionPhase.completed) _resetToConsent();
  }

  void resetAfterStartFailure() {
    if (_phase == DisposableWebViewSessionPhase.failed) _resetToConsent();
  }

  void _resetToConsent() {
    _phase = DisposableWebViewSessionPhase.consent;
    _consentAccepted = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _handleStartFailure(
    DisposableWebViewSessionRuntime runtime,
    Object startError,
  ) async {
    try {
      await _clearRuntime(runtime);
      runtime.dispose();
      _runtime = null;
      _consentAccepted = false;
      _phase = DisposableWebViewSessionPhase.failed;
      _errorMessage = 'SESSION_START_FAILED: $startError';
      notifyListeners();
    } catch (cleanupError) {
      runtime.dispose();
      _runtime = null;
      _block(
        'SESSION_START_AND_CLEANUP_FAILED: $startError | $cleanupError',
      );
    }
  }

  void _block(String message) {
    _consentAccepted = false;
    _phase = DisposableWebViewSessionPhase.blocked;
    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    super.dispose();
  }
}
