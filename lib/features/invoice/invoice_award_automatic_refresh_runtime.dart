import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'invoice_award_cloud_candidate_scope.dart';
import 'invoice_award_cloud_foreground_acquisition.dart';
import 'invoice_award_cloud_index_lkg_repository.dart';
import 'invoice_award_official_acquisition.dart';
import 'invoice_award_official_dataset.dart';
import 'invoice_award_official_html_parser.dart';
import 'invoice_award_period_catalog.dart';
import 'invoice_award_production_refresh_controller.dart';
import 'invoice_award_refresh_policy.dart';
import 'invoice_award_shared_preferences_lkg_repository.dart';

enum InvoiceAwardAutomaticRefreshStatus {
  skippedOptOut,
  skippedNotDue,
  skippedNoSupportedPeriod,
  completed,
  incomplete,
  failed,
}

class InvoiceAwardAutomaticRefreshState {
  const InvoiceAwardAutomaticRefreshState({
    required this.automaticRefreshConsented,
    this.lastAttemptUtc,
    this.lastCompletedPeriodId,
    this.lastFailureCode,
  });

  const InvoiceAwardAutomaticRefreshState.initial()
      : automaticRefreshConsented = false,
        lastAttemptUtc = null,
        lastCompletedPeriodId = null,
        lastFailureCode = null;

  final bool automaticRefreshConsented;
  final DateTime? lastAttemptUtc;
  final String? lastCompletedPeriodId;
  final String? lastFailureCode;

  InvoiceAwardAutomaticRefreshState copyWith({
    bool? automaticRefreshConsented,
    DateTime? lastAttemptUtc,
    bool clearLastAttemptUtc = false,
    String? lastCompletedPeriodId,
    bool clearLastCompletedPeriodId = false,
    String? lastFailureCode,
    bool clearLastFailureCode = false,
  }) {
    return InvoiceAwardAutomaticRefreshState(
      automaticRefreshConsented:
          automaticRefreshConsented ?? this.automaticRefreshConsented,
      lastAttemptUtc:
          clearLastAttemptUtc ? null : lastAttemptUtc ?? this.lastAttemptUtc,
      lastCompletedPeriodId: clearLastCompletedPeriodId
          ? null
          : lastCompletedPeriodId ?? this.lastCompletedPeriodId,
      lastFailureCode: clearLastFailureCode
          ? null
          : lastFailureCode ?? this.lastFailureCode,
    );
  }
}

abstract class InvoiceAwardAutomaticRefreshStateRepository {
  Future<InvoiceAwardAutomaticRefreshState> read();

  Future<void> replace(InvoiceAwardAutomaticRefreshState state);
}

class SharedPreferencesInvoiceAwardAutomaticRefreshStateRepository
    implements InvoiceAwardAutomaticRefreshStateRepository {
  SharedPreferencesInvoiceAwardAutomaticRefreshStateRepository(
    this.preferences,
  );

  final SharedPreferences preferences;

  static const String _consentKey =
      'issue13.invoiceAward.autoRefresh.consent.v1';
  static const String _lastAttemptKey =
      'issue13.invoiceAward.autoRefresh.lastAttemptUtc.v1';
  static const String _lastCompletedPeriodKey =
      'issue13.invoiceAward.autoRefresh.lastCompletedPeriodId.v1';
  static const String _lastFailureKey =
      'issue13.invoiceAward.autoRefresh.lastFailureCode.v1';

  @override
  Future<InvoiceAwardAutomaticRefreshState> read() async {
    final lastAttemptRaw = preferences.getString(_lastAttemptKey);
    final parsedAttempt =
        lastAttemptRaw == null ? null : DateTime.tryParse(lastAttemptRaw);
    return InvoiceAwardAutomaticRefreshState(
      automaticRefreshConsented: preferences.getBool(_consentKey) ?? false,
      lastAttemptUtc: parsedAttempt?.toUtc(),
      lastCompletedPeriodId:
          _clean(preferences.getString(_lastCompletedPeriodKey)),
      lastFailureCode: _clean(preferences.getString(_lastFailureKey)),
    );
  }

  @override
  Future<void> replace(InvoiceAwardAutomaticRefreshState state) async {
    await preferences.setBool(
      _consentKey,
      state.automaticRefreshConsented,
    );
    await _writeNullable(
      _lastAttemptKey,
      state.lastAttemptUtc?.toUtc().toIso8601String(),
    );
    await _writeNullable(
      _lastCompletedPeriodKey,
      _clean(state.lastCompletedPeriodId),
    );
    await _writeNullable(
      _lastFailureKey,
      _clean(state.lastFailureCode),
    );
  }

  Future<void> _writeNullable(String key, String? value) async {
    if (value == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, value);
    }
  }

  static String? _clean(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class InvoiceAwardAutomaticRefreshExecutionResult {
  const InvoiceAwardAutomaticRefreshExecutionResult({
    required this.periodId,
    required this.generalAuthorityReady,
    required this.cloudAuthorityReady,
    this.failureCode,
  });

  final String periodId;
  final bool generalAuthorityReady;
  final bool cloudAuthorityReady;
  final String? failureCode;

  bool get isComplete => generalAuthorityReady && cloudAuthorityReady;
}

abstract class InvoiceAwardAutomaticRefreshExecutor {
  Future<InvoiceAwardAutomaticRefreshExecutionResult> execute({
    required InvoiceAwardSelectablePeriod period,
    required DateTime nowLocal,
  });
}

/// Reuses the same MOF-only production acquisition components as the manual
/// Award Check flow, but has no UI, prize-claim, remittance or accounting-write
/// authority. This executor is safe for foreground catch-up and is the common
/// execution seam for the later Android background-scheduler adapter.
class ProductionInvoiceAwardAutomaticRefreshExecutor
    implements InvoiceAwardAutomaticRefreshExecutor {
  const ProductionInvoiceAwardAutomaticRefreshExecutor();

  @override
  Future<InvoiceAwardAutomaticRefreshExecutionResult> execute({
    required InvoiceAwardSelectablePeriod period,
    required DateTime nowLocal,
  }) async {
    final client = http.Client();
    try {
      final preferences = await SharedPreferences.getInstance();
      const validator = OfficialInvoiceAwardDatasetValidator();
      final volatileStore = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
      final usePreviousPublication =
          InvoiceAwardRecentPeriodCatalog.usesPreviousPublication(
        period,
        nowLocal,
      );

      final generalCoordinator = OfficialInvoiceAwardAcquisitionCoordinator(
        parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
        validator: validator,
        store: volatileStore,
      );
      final generalService = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
        client: client,
        coordinator: generalCoordinator,
        sourceUri: usePreviousPublication
            ? MinistryOfFinanceGeneralAwardHttpAcquisitionService
                .previousSourceUri
            : MinistryOfFinanceGeneralAwardHttpAcquisitionService
                .currentSourceUri,
      );
      final generalController = InvoiceAwardProductionRefreshController(
        service: generalService,
        volatileStore: volatileStore,
        durableRepository:
            SharedPreferencesOfficialInvoiceAwardLkgRepository(preferences),
        validator: validator,
      );

      final general = await generalController.refresh(period.period);
      final generalReady =
          general.dataset?.period.id == period.period.id;

      final candidates =
          await ExistingInvoiceAwardCandidateRepository().listCandidates();
      final candidateNumbers = cloudCandidateNumbersForAwardPeriod(
        candidates: candidates,
        awardPeriod: period.candidateAwardPeriodLabel,
      );
      final cloud = await MinistryOfFinanceCloudAwardForegroundAcquisitionService(
        client: client,
        repository: CloudAwardIndexLkgRepository(),
        publicationUri: usePreviousPublication
            ? MinistryOfFinanceCloudAwardForegroundAcquisitionService
                .previousPublicationUri
            : MinistryOfFinanceCloudAwardForegroundAcquisitionService
                .currentPublicationUri,
      ).refresh(
        periodId: period.period.id,
        retentionUntil: period.redemptionEnd.toUtc(),
        candidateInvoiceNumbers: candidateNumbers,
      );

      return InvoiceAwardAutomaticRefreshExecutionResult(
        periodId: period.period.id,
        generalAuthorityReady: generalReady,
        cloudAuthorityReady: cloud.isComplete,
        failureCode: generalReady && cloud.isComplete
            ? null
            : !generalReady
                ? 'GENERAL_AUTHORITY_INCOMPLETE'
                : 'CLOUD_AUTHORITY_INCOMPLETE',
      );
    } catch (_) {
      return InvoiceAwardAutomaticRefreshExecutionResult(
        periodId: period.period.id,
        generalAuthorityReady: false,
        cloudAuthorityReady: false,
        failureCode: 'AUTOMATIC_REFRESH_EXECUTION_FAILED',
      );
    } finally {
      client.close();
    }
  }
}

class InvoiceAwardAutomaticRefreshResult {
  const InvoiceAwardAutomaticRefreshResult({
    required this.status,
    required this.state,
    this.periodId,
    this.failureCode,
  });

  final InvoiceAwardAutomaticRefreshStatus status;
  final InvoiceAwardAutomaticRefreshState state;
  final String? periodId;
  final String? failureCode;
}

/// Durable, fail-closed foreground catch-up coordinator.
///
/// This slice intentionally does not claim an Android scheduled-background
/// worker yet. It closes the shared execution/state/idempotency boundary first,
/// so the subsequent WorkManager adapter can invoke exactly the same executor
/// without creating a second award-data authority path.
class InvoiceAwardAutomaticRefreshCoordinator {
  InvoiceAwardAutomaticRefreshCoordinator({
    required this.stateRepository,
    required this.executor,
    this.policyFactory = _defaultPolicyFactory,
  });

  final InvoiceAwardAutomaticRefreshStateRepository stateRepository;
  final InvoiceAwardAutomaticRefreshExecutor executor;
  final InvoiceAwardRefreshPolicy Function(bool consent) policyFactory;

  static bool _processActive = false;

  Future<InvoiceAwardAutomaticRefreshResult> runForegroundCatchUp({
    required DateTime nowLocal,
  }) async {
    var state = await stateRepository.read();
    if (!state.automaticRefreshConsented) {
      return InvoiceAwardAutomaticRefreshResult(
        status: InvoiceAwardAutomaticRefreshStatus.skippedOptOut,
        state: state,
      );
    }

    InvoiceAwardSelectablePeriod period;
    try {
      period = InvoiceAwardRecentPeriodCatalog.defaultAt(nowLocal);
    } catch (_) {
      return InvoiceAwardAutomaticRefreshResult(
        status: InvoiceAwardAutomaticRefreshStatus.skippedNoSupportedPeriod,
        state: state,
      );
    }

    final currentComplete = state.lastCompletedPeriodId == period.period.id;
    final lastAttemptLocal = state.lastAttemptUtc?.toLocal();
    final policy = policyFactory(true);
    final due = policy.foregroundCatchUpDue(
      nowLocal: nowLocal,
      lastAttemptLocal: lastAttemptLocal,
      generalDatasetPromoted: currentComplete,
      cloudExclusiveDatasetPromoted: currentComplete,
    );
    if (!due || _processActive) {
      return InvoiceAwardAutomaticRefreshResult(
        status: InvoiceAwardAutomaticRefreshStatus.skippedNotDue,
        state: state,
        periodId: period.period.id,
      );
    }

    _processActive = true;
    state = state.copyWith(
      lastAttemptUtc: nowLocal.toUtc(),
      clearLastFailureCode: true,
    );
    await stateRepository.replace(state);

    try {
      final execution = await executor.execute(
        period: period,
        nowLocal: nowLocal,
      );
      if (execution.periodId != period.period.id) {
        final failed = state.copyWith(
          lastFailureCode: 'AUTOMATIC_REFRESH_PERIOD_MISMATCH',
        );
        await stateRepository.replace(failed);
        return InvoiceAwardAutomaticRefreshResult(
          status: InvoiceAwardAutomaticRefreshStatus.failed,
          state: failed,
          periodId: period.period.id,
          failureCode: failed.lastFailureCode,
        );
      }

      if (execution.isComplete) {
        final completed = state.copyWith(
          lastCompletedPeriodId: period.period.id,
          clearLastFailureCode: true,
        );
        await stateRepository.replace(completed);
        return InvoiceAwardAutomaticRefreshResult(
          status: InvoiceAwardAutomaticRefreshStatus.completed,
          state: completed,
          periodId: period.period.id,
        );
      }

      final incomplete = state.copyWith(
        lastFailureCode:
            execution.failureCode ?? 'AUTOMATIC_REFRESH_INCOMPLETE',
      );
      await stateRepository.replace(incomplete);
      return InvoiceAwardAutomaticRefreshResult(
        status: InvoiceAwardAutomaticRefreshStatus.incomplete,
        state: incomplete,
        periodId: period.period.id,
        failureCode: incomplete.lastFailureCode,
      );
    } catch (_) {
      final failed = state.copyWith(
        lastFailureCode: 'AUTOMATIC_REFRESH_EXECUTION_FAILED',
      );
      await stateRepository.replace(failed);
      return InvoiceAwardAutomaticRefreshResult(
        status: InvoiceAwardAutomaticRefreshStatus.failed,
        state: failed,
        periodId: period.period.id,
        failureCode: failed.lastFailureCode,
      );
    } finally {
      _processActive = false;
    }
  }

  static InvoiceAwardRefreshPolicy _defaultPolicyFactory(bool consent) =>
      InvoiceAwardRefreshPolicy(automaticRefreshConsented: consent);
}
