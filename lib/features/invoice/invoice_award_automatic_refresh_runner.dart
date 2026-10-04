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
import 'invoice_award_runtime_scheduler.dart';
import 'invoice_award_shared_preferences_lkg_repository.dart';

/// Process-wide guard shared by manual UI refresh and app-wide automatic
/// foreground catch-up. It prevents two official refresh pipelines from
/// mutating LKG/candidate authority concurrently.
class InvoiceAwardRefreshProcessGate {
  InvoiceAwardRefreshProcessGate._();

  static bool _active = false;

  static bool tryAcquire() {
    if (_active) return false;
    _active = true;
    return true;
  }

  static void release() {
    _active = false;
  }

  static bool get isActive => _active;
}

class InvoiceAwardAutomaticRefreshOutcome {
  const InvoiceAwardAutomaticRefreshOutcome({
    required this.started,
    required this.generalDatasetPromoted,
    required this.cloudExclusiveDatasetPromoted,
  });

  final bool started;
  final bool generalDatasetPromoted;
  final bool cloudExclusiveDatasetPromoted;

  bool get complete =>
      generalDatasetPromoted && cloudExclusiveDatasetPromoted;
}

/// Headless foreground runner for an already-authorized automatic refresh.
///
/// This is intentionally orchestration-only. It reuses the exact production
/// general-award controller and cloud-award acquisition service; it does not
/// contain an alternative MOF parser, URL scraper, candidate matcher, or
/// promotion implementation. No invoice/accounting data is uploaded.
class InvoiceAwardCanonicalAutomaticRefreshRunner {
  InvoiceAwardCanonicalAutomaticRefreshRunner({
    required this.scheduler,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final InvoiceAwardRuntimeScheduler scheduler;
  final DateTime Function() _clock;

  Future<InvoiceAwardAutomaticRefreshOutcome> refresh({
    required InvoiceAwardSelectablePeriod selectedPeriod,
  }) async {
    final now = _clock();
    if (!selectedPeriod.canCheckAt(now)) {
      return const InvoiceAwardAutomaticRefreshOutcome(
        started: false,
        generalDatasetPromoted: false,
        cloudExclusiveDatasetPromoted: false,
      );
    }
    if (!InvoiceAwardRefreshProcessGate.tryAcquire()) {
      return const InvoiceAwardAutomaticRefreshOutcome(
        started: false,
        generalDatasetPromoted: false,
        cloudExclusiveDatasetPromoted: false,
      );
    }

    var generalPromoted = false;
    var cloudPromoted = false;
    final client = http.Client();
    final cloudRepository = CloudAwardIndexLkgRepository();
    try {
      await scheduler.recordAttemptStarted(
        nowLocal: now,
        periodId: selectedPeriod.period.id,
      );
      final preferences = await SharedPreferences.getInstance();
      const validator = OfficialInvoiceAwardDatasetValidator();
      final volatileStore = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
      final generalCoordinator = OfficialInvoiceAwardAcquisitionCoordinator(
        parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
        validator: validator,
        store: volatileStore,
      );
      final usePreviousPublication =
          InvoiceAwardRecentPeriodCatalog.usesPreviousPublication(
        selectedPeriod,
        now,
      );
      final generalService = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
        client: client,
        coordinator: generalCoordinator,
        sourceUri: usePreviousPublication
            ? MinistryOfFinanceGeneralAwardHttpAcquisitionService.previousSourceUri
            : MinistryOfFinanceGeneralAwardHttpAcquisitionService.currentSourceUri,
      );
      final generalController = InvoiceAwardProductionRefreshController(
        service: generalService,
        volatileStore: volatileStore,
        durableRepository:
            SharedPreferencesOfficialInvoiceAwardLkgRepository(preferences),
        validator: validator,
      );

      final generalResult =
          await generalController.refresh(selectedPeriod.period);
      generalPromoted =
          generalResult.isSuccess && generalResult.dataset != null;

      final candidates =
          await ExistingInvoiceAwardCandidateRepository().listCandidates();
      final candidateNumbers = cloudCandidateNumbersForAwardPeriod(
        candidates: candidates,
        awardPeriod: selectedPeriod.candidateAwardPeriodLabel,
      );
      final cloudService =
          MinistryOfFinanceCloudAwardForegroundAcquisitionService(
        client: client,
        repository: cloudRepository,
        publicationUri: usePreviousPublication
            ? MinistryOfFinanceCloudAwardForegroundAcquisitionService
                .previousPublicationUri
            : MinistryOfFinanceCloudAwardForegroundAcquisitionService
                .currentPublicationUri,
      );
      final cloudResult = await cloudService.refresh(
        periodId: selectedPeriod.period.id,
        retentionUntil: selectedPeriod.redemptionEnd.toUtc(),
        candidateInvoiceNumbers: candidateNumbers,
      );
      cloudPromoted = cloudResult.isComplete;

      return InvoiceAwardAutomaticRefreshOutcome(
        started: true,
        generalDatasetPromoted: generalPromoted,
        cloudExclusiveDatasetPromoted: cloudPromoted,
      );
    } catch (_) {
      // Fail closed. Existing LKG/candidate authority is retained by the
      // canonical services and the scheduler records a partial attempt.
      return InvoiceAwardAutomaticRefreshOutcome(
        started: true,
        generalDatasetPromoted: generalPromoted,
        cloudExclusiveDatasetPromoted: cloudPromoted,
      );
    } finally {
      await scheduler.recordAttemptFinished(
        periodId: selectedPeriod.period.id,
        generalDatasetPromoted: generalPromoted,
        cloudExclusiveDatasetPromoted: cloudPromoted,
      );
      await scheduler.reconcile(
        nowLocal: _clock(),
        periodId: selectedPeriod.period.id,
      );
      client.close();
      InvoiceAwardRefreshProcessGate.release();
    }
  }
}
