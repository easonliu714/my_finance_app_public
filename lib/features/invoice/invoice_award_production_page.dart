import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
import 'invoice_award_cloud_candidate_scope.dart';
import 'invoice_award_cloud_eligibility_confirmation.dart';
import 'invoice_award_cloud_foreground_acquisition.dart';
import 'invoice_award_cloud_pdf_index.dart';
import 'invoice_award_cloud_index_lkg_repository.dart';
import 'invoice_award_official_acquisition.dart';
import 'invoice_award_official_dataset.dart';
import 'invoice_award_official_html_parser.dart';
import 'invoice_award_notification_runtime.dart';
import 'invoice_award_period_catalog.dart';
import 'invoice_award_production_refresh_controller.dart';
import 'invoice_award_runtime_scheduler.dart';
import 'invoice_award_automatic_refresh_runner.dart';
import 'invoice_award_shared_preferences_lkg_repository.dart';

/// Production foreground award-check surface for recent still-actionable periods.
///
/// A single explicit user action refreshes both public MOF award domains, then
/// scans governed invoice identities already attached to formal transactions.
/// No invoice/accounting identifiers leave the device and this surface has no
/// formal-transaction, redemption, claim, or remittance authority.
class InvoiceAwardProductionPage extends StatefulWidget {
  const InvoiceAwardProductionPage({super.key, this.clock});

  final DateTime Function()? clock;

  @override
  State<InvoiceAwardProductionPage> createState() =>
      _InvoiceAwardProductionPageState();
}

class _InvoiceAwardProductionPageState extends State<InvoiceAwardProductionPage>
    with WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final CloudAwardIndexLkgRepository _cloudRepository = CloudAwardIndexLkgRepository();
  bool _ownsProcessRefresh = false;
  bool _disposed = false;

  late final List<InvoiceAwardSelectablePeriod> _periodOptions;
  late InvoiceAwardSelectablePeriod _selectedPeriod;

  bool _refreshing = false;
  bool _cloudCurrentAuthorityComplete = false;
  InvoiceAwardRuntimeScheduler? _automaticScheduler;
  bool _automaticRefreshConsented = false;
  String _automaticScheduleStatus = '自動更新排程初始化中…';
  bool _automaticCatchUpRunning = false;
  bool _winningNotificationsEnabled = false;
  String _winningNotificationStatus = '中獎通知初始化中…';
  String _status = '';
  String _cloudStatus = '';
  String _cloudDiagnosticStatus = '';
  String _scanStatus = '';
  final Map<String, String> _cloudTierSummaries = <String, String>{};
  String? _activeCloudTierCode;

  List<ExistingInvoiceAwardCandidate> _candidates = const [];
  List<ExistingInvoiceAwardGeneralEvaluation> _generalEvaluations = const [];
  List<ExistingInvoiceAwardCloudEvaluation> _cloudEvaluations = const [];
  Map<String, InvoiceAwardCloudEligibilityConfirmation>
      _cloudEligibilityConfirmations =
      const <String, InvoiceAwardCloudEligibilityConfirmation>{};
  final Map<String, GlobalKey> _candidateTileKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = _now();
    _periodOptions = InvoiceAwardRecentPeriodCatalog.visibleAt(now);
    _selectedPeriod = InvoiceAwardRecentPeriodCatalog.defaultAt(now);
    _resetSelectedPeriodState(now);
    _loadLastPdfDiagnostic();
    unawaited(_initializeAutomaticRefreshRuntime());
    unawaited(_initializeWinningNotifications());
  }

  @override
  void dispose() {
    _disposed = true;
    // Large cloud-500 verification is owned by a native foreground service.
    // Navigating away or backgrounding the Activity must not revoke an
    // already-authorized local lookup.
    WidgetsBinding.instance.removeObserver(this);
    if (!_ownsProcessRefresh) _httpClient.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAutomaticForegroundResume());
    }
    if (!_ownsProcessRefresh || !mounted) return;

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      setState(() {
        _cloudStatus = 'App 已進入背景；大型雲端獎 PDF 仍由系統背景服務持續比對，'
            '回到 App 後會接續顯示進度與結果。';
      });
      return;
    }
    if (state == AppLifecycleState.resumed && _refreshing) {
      setState(() {
        _cloudStatus = '已回到 App；正在同步背景雲端獎比對進度與結果。';
      });
    }
  }

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  Future<void> _initializeWinningNotifications() async {
    final preferences = await SharedPreferences.getInstance();
    final repository = InvoiceAwardNotificationSettingsRepository(preferences);
    final enabled = repository.load().winningNotificationsEnabled;
    if (!mounted) return;
    setState(() {
      _winningNotificationsEnabled = enabled;
      _winningNotificationStatus = enabled
          ? '中獎通知已開啟；已確認中獎會通知，雲端獎資格待確認時會提醒你回 App 核對。'
          : '中獎通知已關閉。';
    });
  }

  Future<void> _setWinningNotificationsEnabled(bool value) async {
    if (_refreshing) return;
    final preferences = await SharedPreferences.getInstance();
    final repository = InvoiceAwardNotificationSettingsRepository(preferences);

    if (!value) {
      await repository.setWinningNotificationsEnabled(false);
      if (!mounted) return;
      setState(() {
        _winningNotificationsEnabled = false;
        _winningNotificationStatus = '中獎通知已關閉。';
      });
      return;
    }

    final granted = await FlutterInvoiceAwardNotificationPort().requestPermission();
    if (!granted) {
      await repository.setWinningNotificationsEnabled(false);
      if (!mounted) return;
      setState(() {
        _winningNotificationsEnabled = false;
        _winningNotificationStatus =
            '系統未授予通知權限；未啟用中獎通知。可從 Android 設定重新允許後再開啟。';
      });
      return;
    }

    await repository.setWinningNotificationsEnabled(true);
    if (!mounted) return;
    setState(() {
      _winningNotificationsEnabled = true;
      _winningNotificationStatus =
          '中獎通知已開啟；已確認中獎與雲端獎資格待確認提醒都只顯示期別、獎別與金額。';
    });
  }

  Future<void> _initializeAutomaticRefreshRuntime() async {
    final preferences = await SharedPreferences.getInstance();
    final scheduler = InvoiceAwardRuntimeScheduler(
      repository: InvoiceAwardRuntimeStateRepository(preferences),
    );
    final state = scheduler.repository.load();
    final wake = await scheduler.consumeNativeWake();
    _automaticScheduler = scheduler;
    if (!mounted) return;
    setState(() {
      _automaticRefreshConsented = state.automaticRefreshConsented;
      _automaticScheduleStatus = wake == null
          ? '自動更新尚未觸發'
          : '系統排程已觸發；回到前景後會沿用同一條官方更新流程補抓。';
    });
    await _reconcileAutomaticSchedule();
    await _runAutomaticCatchUpIfDue();
  }

  Future<void> _handleAutomaticForegroundResume() async {
    final scheduler = _automaticScheduler;
    if (scheduler == null || !mounted) return;
    final wake = await scheduler.consumeNativeWake();
    if (wake != null && mounted) {
      setState(() {
        _automaticScheduleStatus =
            '系統排程已於背景觸發；正在檢查是否需要前景補抓。';
      });
    }
    await _runAutomaticCatchUpIfDue();
  }

  Future<void> _setAutomaticRefreshConsent(bool value) async {
    final scheduler = _automaticScheduler;
    if (scheduler == null || _refreshing) return;
    await scheduler.setConsent(value);
    if (!mounted) return;
    setState(() {
      _automaticRefreshConsented = value;
      _automaticScheduleStatus = value
          ? '已允許自動更新；正在安排下一次官方獎號檢查。'
          : '自動更新已關閉；背景不會觸發官方獎號網路更新。';
    });
    await _reconcileAutomaticSchedule();
    if (value) await _runAutomaticCatchUpIfDue();
  }

  Future<void> _reconcileAutomaticSchedule() async {
    final scheduler = _automaticScheduler;
    if (scheduler == null) return;
    final result = await scheduler.reconcile(
      nowLocal: _now(),
      periodId: _selectedPeriod.period.id,
    );
    if (!mounted) return;
    setState(() {
      _automaticRefreshConsented = result.consent;
      if (!result.consent) {
        _automaticScheduleStatus =
            '自動更新已關閉；背景不會觸發官方獎號網路更新。';
      } else if (result.currentPeriodComplete) {
        _automaticScheduleStatus = '本期一般獎與雲端專屬獎皆已驗證；不需再排程。';
      } else if (result.nextTargetLocal != null) {
        final target = result.nextTargetLocal!;
        String two(int value) => value.toString().padLeft(2, '0');
        _automaticScheduleStatus =
            '下一次 best-effort 檢查：${target.year}-${two(target.month)}-'
            '${two(target.day)} ${two(target.hour)}:${two(target.minute)}；'
            '若 Android 延後執行，回到 App 會自動補抓。';
      }
    });
  }

  Future<void> _runAutomaticCatchUpIfDue() async {
    final scheduler = _automaticScheduler;
    if (scheduler == null ||
        !_automaticRefreshConsented ||
        _automaticCatchUpRunning ||
        _refreshing ||
        !mounted) {
      return;
    }
    final due = await scheduler.foregroundCatchUpDue(
      nowLocal: _now(),
      periodId: _selectedPeriod.period.id,
    );
    if (!due || !mounted) return;
    _automaticCatchUpRunning = true;
    setState(() {
      _automaticScheduleStatus =
          '偵測到錯過的自動更新時點；正在沿用手動更新相同的官方驗證流程補抓。';
    });
    try {
      await _refresh(automatic: true);
    } finally {
      _automaticCatchUpRunning = false;
    }
  }

  Future<void> _loadLastPdfDiagnostic() async {
    const extractor = FlutterPdfTextCloudAwardExtractor();
    final text = FlutterPdfTextCloudAwardExtractor.diagnosticText(
      await extractor.readLastNativeDiagnostic(),
    );
    if (!mounted || text == null) return;
    setState(() {
      _cloudDiagnosticStatus = '上次 PDF 解析最後紀錄：$text';
    });
  }

  void _resetSelectedPeriodState(DateTime now) {
    _cloudCurrentAuthorityComplete = false;
    _cloudDiagnosticStatus = '';
    _cloudTierSummaries.clear();
    _activeCloudTierCode = null;
    _candidates = const [];
    _generalEvaluations = const [];
    _cloudEvaluations = const [];
    _cloudEligibilityConfirmations =
        const <String, InvoiceAwardCloudEligibilityConfirmation>{};
    if (_selectedPeriod.canCheckAt(now)) {
      _status = '尚未更新官方 ${_selectedPeriod.periodLabel} 中獎資料';
      _cloudStatus = '雲端專屬獎尚未更新';
      _scanStatus = '尚未掃描既有正式交易';
    } else {
      _status = '${_selectedPeriod.periodLabel} 尚未開獎，暫不可下載獎號。';
      _cloudStatus = '雲端專屬獎等待開獎後才可更新';
      _scanStatus = '尚未開獎，不執行既有交易對獎';
    }
  }

  void _selectPeriod(String? periodId) {
    if (periodId == null || _refreshing) return;
    final selected = _periodOptions.firstWhere((item) => item.period.id == periodId);
    setState(() {
      _selectedPeriod = selected;
      _resetSelectedPeriodState(_now());
    });
    unawaited(_reconcileAutomaticSchedule());
  }

  Future<void> _refresh({bool automatic = false}) async {
    if (_refreshing) return;
    final now = _now();
    final selectedPeriod = _selectedPeriod;
    if (!selectedPeriod.canCheckAt(now)) {
      setState(() => _resetSelectedPeriodState(now));
      return;
    }
    if (!InvoiceAwardRefreshProcessGate.tryAcquire()) {
      setState(() {
        _cloudStatus = '前一次中獎資料更新仍在安全收尾，請稍候再重試。';
      });
      return;
    }
    _ownsProcessRefresh = true;
    var schedulerGeneralPromoted = false;
    var schedulerCloudPromoted = false;
    final scheduler = _automaticScheduler;
    if (_automaticRefreshConsented && scheduler != null) {
      await scheduler.recordAttemptStarted(
        nowLocal: now,
        periodId: selectedPeriod.period.id,
      );
    }
    final cancellation = CloudAwardCandidateLookupCancellation();

    final usePreviousPublication =
        InvoiceAwardRecentPeriodCatalog.usesPreviousPublication(selectedPeriod, now);
    setState(() {
      _refreshing = true;
      _cloudCurrentAuthorityComplete = false;
      _cloudDiagnosticStatus = '';
      _cloudTierSummaries.clear();
      _activeCloudTierCode = null;
      _status = '正在更新財政部一般獎資料…';
      _cloudStatus = '等待一般獎完成後更新雲端專屬獎…';
      _scanStatus = '等待官方資料驗證後掃描既有交易…';
    });

    var generalStageCompleted = false;
    try {
      final preferences = await SharedPreferences.getInstance();
      const validator = OfficialInvoiceAwardDatasetValidator();
      final volatileStore = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
      final generalCoordinator = OfficialInvoiceAwardAcquisitionCoordinator(
        parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
        validator: validator,
        store: volatileStore,
      );
      final generalService = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
        client: _httpClient,
        coordinator: generalCoordinator,
        sourceUri: usePreviousPublication
            ? MinistryOfFinanceGeneralAwardHttpAcquisitionService.previousSourceUri
            : MinistryOfFinanceGeneralAwardHttpAcquisitionService.currentSourceUri,
      );
      final generalController = InvoiceAwardProductionRefreshController(
        service: generalService,
        volatileStore: volatileStore,
        durableRepository: SharedPreferencesOfficialInvoiceAwardLkgRepository(preferences),
        validator: validator,
      );

      final generalResult = await generalController.refresh(selectedPeriod.period);
      cancellation.throwIfCancelled();
      final dataset = generalResult.dataset;
      final candidates =
          await ExistingInvoiceAwardCandidateRepository().listCandidates();
      final generalEvaluations = dataset == null
          ? const <ExistingInvoiceAwardGeneralEvaluation>[]
          : const ExistingInvoiceAwardGeneralBatchMatcher().evaluate(
              dataset: dataset,
              candidates: candidates,
            );
      final currentCandidates = candidates
          .where(
            (candidate) =>
                candidate.awardPeriod ==
                selectedPeriod.candidateAwardPeriodLabel,
          )
          .toList(growable: false);
      final currentKeys = currentCandidates.map(_candidateKey).toSet();
      final generalWinners = generalEvaluations
          .where(
            (item) =>
                currentKeys.contains(_candidateKey(item.candidate)) &&
                item.isWinner,
          )
          .length;

      // General awards and cloud-exclusive awards are independent authority
      // domains. Publish the validated general result before any large native
      // cloud-PDF work so a cloud failure cannot suppress a general match.
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _generalEvaluations = generalEvaluations;
        _cloudEvaluations = const <ExistingInvoiceAwardCloudEvaluation>[];
        _scanStatus = '一般獎對獎已完成：本期候選 '
            '${currentCandidates.length} 筆；中獎 $generalWinners 筆。'
            ' 雲端專屬獎另行更新中。';
        if (generalResult.isSuccess && dataset != null) {
          final fetched = dataset.provenance.fetchedAt.toLocal();
          _status = '一般獎官方資料已驗證：${dataset.period.id} · '
              '更新 ${fetched.year}-'
              '${fetched.month.toString().padLeft(2, '0')}-'
              '${fetched.day.toString().padLeft(2, '0')} '
              '${fetched.hour.toString().padLeft(2, '0')}:'
              '${fetched.minute.toString().padLeft(2, '0')}';
        } else if (dataset != null) {
          _status = '一般獎更新失敗；已保留並使用 '
              '${dataset.period.id} 的最後已驗證資料。';
        } else {
          _status = '一般獎更新失敗，且目前沒有可用的已驗證官方資料。';
        }
      });
      generalStageCompleted = true;
      schedulerGeneralPromoted = generalResult.isSuccess && dataset != null;

      final currentCloudCandidateNumbers =
          cloudCandidateNumbersForAwardPeriod(
        candidates: candidates,
        awardPeriod: selectedPeriod.candidateAwardPeriodLabel,
      );

      CloudAwardForegroundRefreshResult? cloudRefresh;
      try {
        final cloudService = MinistryOfFinanceCloudAwardForegroundAcquisitionService(
          client: _httpClient,
          repository: _cloudRepository,
          publicationUri: usePreviousPublication
              ? MinistryOfFinanceCloudAwardForegroundAcquisitionService.previousPublicationUri
              : MinistryOfFinanceCloudAwardForegroundAcquisitionService.currentPublicationUri,
        );
        cloudRefresh = await cloudService.refresh(
          periodId: selectedPeriod.period.id,
          retentionUntil: selectedPeriod.redemptionEnd.toUtc(),
          candidateInvoiceNumbers: currentCloudCandidateNumbers,
          onProgress: _handleCloudProgress,
          cancellation: cancellation,
        );
      } catch (error) {
        final failureCode = _safeCloudFailureCode(error);
        if (mounted) {
          setState(() {
            final activeTier = _activeCloudTierCode;
            if (activeTier != null) {
              _cloudTierSummaries[activeTier] = '失敗：$failureCode';
            }
            _cloudStatus = '雲端專屬獎本次更新失敗：$failureCode；'
                '保留既有已驗證資料，結果不會宣稱完整未中獎。';
          });
        }
      }

      final cloudEvaluations = await ExistingInvoiceAwardCloudBatchMatcher(
        readLatest: ({required String periodId, required String tierCode}) =>
            _cloudRepository.readLatest(periodId: periodId, tierCode: tierCode),
      ).evaluate(
        candidates: candidates,
        candidateScopedAuthorities:
            cloudRefresh?.candidateScopedAuthorities ??
                const <CloudAwardCandidateScopedAuthority>[],
      );

      final cloudComplete = cloudRefresh?.isComplete ?? false;
      final eligibilityConfirmationRepository =
          InvoiceAwardCloudEligibilityConfirmationRepository(preferences);
      final cloudEligibilityConfirmations =
          <String, InvoiceAwardCloudEligibilityConfirmation>{};
      for (final evaluation in cloudEvaluations) {
        final confirmation = eligibilityConfirmationRepository.readForEvaluation(
          periodId: selectedPeriod.period.id,
          evaluation: evaluation,
        );
        if (confirmation != null) {
          cloudEligibilityConfirmations[
              _cloudEligibilityConfirmationKey(evaluation)] = confirmation;
        }
      }
      schedulerCloudPromoted = cloudComplete;
      final cloudNumberMatches = cloudEvaluations
          .where((item) =>
              currentKeys.contains(_candidateKey(item.candidate)) && item.hasCloudNumberMatch)
          .length;

      await InvoiceAwardWinningNotificationService(
        repository: InvoiceAwardNotificationSettingsRepository(preferences),
        port: FlutterInvoiceAwardNotificationPort(),
        eligibilityConfirmationRepository:
            eligibilityConfirmationRepository,
      ).deliverAwardNotifications(
        periodId: selectedPeriod.period.id,
        periodLabel: selectedPeriod.periodLabel,
        generalDatasetValidated: schedulerGeneralPromoted,
        cloudDatasetValidated: cloudComplete,
        generalEvaluations: generalEvaluations,
        cloudEvaluations: cloudEvaluations,
      );

      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _cloudCurrentAuthorityComplete = cloudComplete;
        _candidates = candidates;
        _generalEvaluations = generalEvaluations;
        _cloudEvaluations = cloudEvaluations;
        _cloudEligibilityConfirmations = cloudEligibilityConfirmations;
        _scanStatus = '本期既有交易候選 ${currentCandidates.length} 筆；'
            '一般獎中獎 $generalWinners 筆；雲端專屬獎號碼吻合 $cloudNumberMatches 筆。';
        if (cloudRefresh != null) {
          for (final tierResult in cloudRefresh.tiers) {
            _cloudTierSummaries[tierResult.tierCode] =
                _terminalCloudTierSummary(
              tierResult,
              _cloudTierSummaries[tierResult.tierCode],
            );
          }
          _cloudStatus = cloudComplete
              ? '雲端專屬獎四個獎別 authority 已驗證完成。'
              : '雲端專屬獎本次更新不完整：'
                  '${cloudRefresh.failureSummary}; '
                  '保留既有 LKG，無法宣稱完整未中獎。';
        }
      });
    } on CloudAwardCandidateLookupCancelled {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _cloudCurrentAuthorityComplete = false;
          _cloudStatus = '本次雲端獎查找因 App 已離開前景而安全中止；未保存部分結果，可直接重新執行。';
          _scanStatus = generalStageCompleted
              ? '一般獎對獎結果已保留；雲端專屬獎查找因 App 已離開前景而中止，可直接重試雲端更新。'
              : '既有交易掃描未完成；重新執行時會從一般獎 authority Gate 重新確認。';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _cloudCurrentAuthorityComplete = false;
        if (!generalStageCompleted) {
          _status = '更新失敗；未變更任何既有已驗證資料。';
          _scanStatus = '一般獎對獎未完成；請稍後重新執行授權更新。';
        } else {
          _scanStatus = '一般獎對獎結果已保留；雲端專屬獎未完成。';
        }
        _cloudStatus = '雲端專屬獎結果未完成；不會宣稱完整未中獎。';
      });
    } finally {
      _ownsProcessRefresh = false;
      InvoiceAwardRefreshProcessGate.release();
      if (_automaticRefreshConsented && scheduler != null) {
        await scheduler.recordAttemptFinished(
          periodId: selectedPeriod.period.id,
          generalDatasetPromoted: schedulerGeneralPromoted,
          cloudExclusiveDatasetPromoted: schedulerCloudPromoted,
        );
        await _reconcileAutomaticSchedule();
      }
      if (mounted && _refreshing) {
        setState(() => _refreshing = false);
      }
      if (_disposed) _httpClient.close();
    }
  }

  void _handleCloudProgress(CloudAwardForegroundProgress progress) {
    if (!mounted) return;
    setState(() {
      final tierCode = progress.tierCode;
      if (tierCode != null) {
        _activeCloudTierCode = tierCode;
        _cloudTierSummaries[tierCode] = _cloudTierProgressSummary(progress);
      }
      _cloudStatus = _cloudProgressText(progress);
      final diagnostic = progress.diagnosticMessage;
      if (diagnostic != null &&
          diagnostic.isNotEmpty &&
          !_cloudDiagnosticStatus.split('\n').contains(diagnostic)) {
        _cloudDiagnosticStatus = _cloudDiagnosticStatus.isEmpty
            ? diagnostic
            : '$_cloudDiagnosticStatus\n$diagnostic';
      }
    });
  }

  GlobalKey _tileKeyFor(ExistingInvoiceAwardCandidate candidate) =>
      _candidateTileKeys.putIfAbsent(_candidateKey(candidate), GlobalKey.new);

  void _scrollToCandidate(ExistingInvoiceAwardCandidate candidate) {
    final targetContext = _tileKeyFor(candidate).currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  Future<void> _setCloudEligibilityDecision(
    ExistingInvoiceAwardCloudEvaluation evaluation,
    InvoiceAwardCloudEligibilityUserDecision decision,
  ) async {
    if (_refreshing ||
        evaluation.status !=
            ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired ||
        !_cloudCurrentAuthorityComplete) return;
    final isEligible =
        decision == InvoiceAwardCloudEligibilityUserDecision.eligible;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEligible ? '確認符合雲端獎資格' : '確認不符合雲端獎資格'),
        content: Text(isEligible
            ? '請確認你已依財政部兌獎規則核對這張發票，包含開獎前未列印電子發票證明聯等資格條件。'
                '這項確認只會記錄在本機，供後續兌獎／記帳流程判斷；本版不會建立交易或代為兌獎。'
            : '請確認你已核對這張發票不符合本次雲端專屬獎兌獎資格。'
                '這項決定只會記錄在本機，不會更改官方獎號資料或既有交易。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isEligible ? '確認符合資格' : '確認不符合資格'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final preferences = await SharedPreferences.getInstance();
    final repository =
        InvoiceAwardCloudEligibilityConfirmationRepository(preferences);
    final record = await repository.saveDecision(
      periodId: _selectedPeriod.period.id,
      evaluation: evaluation,
      decision: decision,
      confirmedAtUtc: _now().toUtc(),
    );
    if (!mounted) return;
    setState(() {
      _cloudEligibilityConfirmations =
          <String, InvoiceAwardCloudEligibilityConfirmation>{
        ..._cloudEligibilityConfirmations,
        _cloudEligibilityConfirmationKey(evaluation): record,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final generalByKey = <String, ExistingInvoiceAwardGeneralEvaluation>{
      for (final evaluation in _generalEvaluations) _candidateKey(evaluation.candidate): evaluation,
    };
    final cloudByKey = <String, ExistingInvoiceAwardCloudEvaluation>{
      for (final evaluation in _cloudEvaluations) _candidateKey(evaluation.candidate): evaluation,
    };
    final visibleCandidates = _candidates
        .where((candidate) => candidate.awardPeriod == _selectedPeriod.candidateAwardPeriodLabel)
        .toList(growable: false);
    final winningCandidates = visibleCandidates.where((candidate) {
      final key = _candidateKey(candidate);
      return (generalByKey[key]?.isWinner ?? false) ||
          (cloudByKey[key]?.hasCloudNumberMatch ?? false);
    }).toList(growable: false);
    final hasCloudReviewWinner = winningCandidates.any((candidate) {
      final evaluation = cloudByKey[_candidateKey(candidate)];
      return evaluation?.hasCloudNumberMatch == true &&
          (evaluation!.requiresReview || !_cloudCurrentAuthorityComplete);
    });
    final now = _now();
    final canCheckSelectedPeriod = _selectedPeriod.canCheckAt(now);

    return Scaffold(
      appBar: AppBar(title: const Text('統一發票中獎檢查')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            const Text('只向財政部官方來源取得中獎資料，不上傳發票或記帳內容。'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('invoice_award_period_selector'),
              initialValue: _selectedPeriod.period.id,
              decoration: const InputDecoration(labelText: '開獎期別', border: OutlineInputBorder()),
              items: [
                for (final option in _periodOptions)
                  DropdownMenuItem<String>(
                    value: option.period.id,
                    enabled: option.canCheckAt(now),
                    child: Text(option.menuLabel(now)),
                  ),
              ],
              onChanged: _refreshing ? null : _selectPeriod,
            ),
            const SizedBox(height: 8),
            Text('${_selectedPeriod.periodLabel} · ${_selectedPeriod.statusLabel(now)}'),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('雲端專屬獎官方資料包含大型 PDF。首次更新可能需要較多網路流量與處理時間；'
                    '大型 500 元獎候選比對會交由系統背景服務執行，可暫時切換到其他 App；'
                    '四個獎別會依序驗證，已驗證且來源相同的資料會直接重用。'),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('invoice_award_automatic_refresh_switch'),
                    title: const Text('自動更新官方獎號'),
                    subtitle: const Text(
                      '開啟後於開獎日 14:00 起以 Android best-effort 排程檢查；'
                      '系統若延後執行，回到 App 會自動補抓。關閉時不允許背景獎號網路更新。',
                    ),
                    value: _automaticRefreshConsented,
                    onChanged: _automaticScheduler == null || _refreshing
                        ? null
                        : _setAutomaticRefreshConsent,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _automaticScheduleStatus,
                        key: const Key('invoice_award_automatic_refresh_status'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('invoice_award_winning_notification_switch'),
                    title: const Text('中獎結果通知'),
                    subtitle: const Text(
                      '開啟後，已確認中獎會通知；雲端獎若號碼吻合但資格仍待確認，也會提醒你回 App 核對。'
                      '鎖定畫面只顯示期別、獎別與金額，不顯示發票號碼、商家或記帳內容。',
                    ),
                    value: _winningNotificationsEnabled,
                    onChanged:
                        _refreshing ? null : _setWinningNotificationsEnabled,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _winningNotificationStatus,
                        key: const Key('invoice_award_winning_notification_status'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _refreshing || !canCheckSelectedPeriod ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_refreshing ? '更新中…' : '授權更新並檢查既有交易'),
            ),
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(_status)),
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(_cloudStatus)),
            if (_cloudTierSummaries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '雲端獎項解析摘要',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      for (final tierCode in const <String>[
                        'cloud-500',
                        'cloud-800',
                        'cloud-2000',
                        'cloud-1000000',
                      ])
                        if (_cloudTierSummaries[tierCode] != null)
                          Text(
                            '${_tierLabel(tierCode)}：'
                            '${_cloudTierSummaries[tierCode]}',
                          ),
                    ],
                  ),
                ),
              ),
            ],
            if (_cloudDiagnosticStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText('PDF 解析診斷：$_cloudDiagnosticStatus'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(_scanStatus)),
            if (winningCandidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '中獎摘要',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text('點選中獎發票可直接跳到下方該筆明細。'),
                      const SizedBox(height: 6),
                      for (final candidate in winningCandidates)
                        TextButton.icon(
                          key: Key(
                            'invoice_award_winner_jump_${candidate.invoiceNumber}',
                          ),
                          onPressed: () => _scrollToCandidate(candidate),
                          icon: const Icon(Icons.arrow_downward),
                          label: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${candidate.invoiceNumber} · '
                              '${_winnerSummaryText(
                                generalByKey[_candidateKey(candidate)],
                                cloudByKey[_candidateKey(candidate)],
                                currentCloudAuthorityComplete:
                                    _cloudCurrentAuthorityComplete,
                                eligibilityConfirmation: cloudByKey[
                                            _candidateKey(candidate)] ==
                                        null
                                    ? null
                                    : _cloudEligibilityConfirmations[
                                        _cloudEligibilityConfirmationKey(
                                          cloudByKey[
                                              _candidateKey(candidate)]!,
                                        )],
                              )}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (hasCloudReviewWinner) ...[
              const SizedBox(height: 8),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '雲端專屬獎資格怎麼看？\n'
                    '號碼吻合代表這張發票已對中雲端專屬獎號。'
                    '本 App 無法從本機資料確認你在開獎前是否已列印電子發票證明聯，'
                    '所以會先標示「資格待確認」。\n'
                    '依財政部現行規則：開獎前已列印證明聯，該張就不屬於雲端發票專屬獎；'
                    '若是在開獎後才列印中獎證明聯，不會因此讓已中的獎失效，'
                    '但紙本會成為兌獎憑證，遺失後不能再重印。'
                    '未列印者可依官方兌獎 App／自動匯款流程領獎。'
                  ),
                ),
              ),
            ],
            if (visibleCandidates.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('既有交易對獎結果', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final candidate in visibleCandidates)
                KeyedSubtree(
                  key: _tileKeyFor(candidate),
                  child: _ExistingTransactionAwardTile(
                    candidate: candidate,
                    generalEvaluation: generalByKey[_candidateKey(candidate)],
                    cloudEvaluation: cloudByKey[_candidateKey(candidate)],
                    cloudCurrentAuthorityComplete: _cloudCurrentAuthorityComplete,
                    cloudEligibilityConfirmation:
                        cloudByKey[_candidateKey(candidate)] == null
                            ? null
                            : _cloudEligibilityConfirmations[
                                _cloudEligibilityConfirmationKey(
                                  cloudByKey[_candidateKey(candidate)]!,
                                )],
                    onCloudEligibilityDecision:
                        cloudByKey[_candidateKey(candidate)]?.status ==
                                    ExistingInvoiceAwardCloudEvaluationStatus
                                        .matchedReviewRequired &&
                                _cloudCurrentAuthorityComplete
                            ? (decision) => _setCloudEligibilityDecision(
                                  cloudByKey[_candidateKey(candidate)]!,
                                  decision,
                                )
                            : null,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            const Text('雲端發票會先參與一般獎，再增加一次雲端專屬獎號碼比對。'
                '號碼吻合不等於已確認可領獎；資格證據不足時會標示待確認。'),
            const SizedBox(height: 12),
            const Text('本 App 僅提供本機中獎比對與記帳輔助，不是兌獎、領獎或自動匯款平台。'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingTransactionAwardTile extends StatelessWidget {
  const _ExistingTransactionAwardTile({
    required this.candidate,
    required this.generalEvaluation,
    required this.cloudEvaluation,
    required this.cloudCurrentAuthorityComplete,
    required this.cloudEligibilityConfirmation,
    required this.onCloudEligibilityDecision,
  });

  final ExistingInvoiceAwardCandidate candidate;
  final ExistingInvoiceAwardGeneralEvaluation? generalEvaluation;
  final ExistingInvoiceAwardCloudEvaluation? cloudEvaluation;
  final bool cloudCurrentAuthorityComplete;
  final InvoiceAwardCloudEligibilityConfirmation? cloudEligibilityConfirmation;
  final ValueChanged<InvoiceAwardCloudEligibilityUserDecision>?
      onCloudEligibilityDecision;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[Text(_generalResultText(generalEvaluation))];
    if (candidate.identitySource == ExistingInvoiceAwardIdentitySource.cloudMetadata) {
      lines.add(const SizedBox(height: 4));
      lines.add(Text(_cloudResultText(
        cloudEvaluation,
        currentAuthorityComplete: cloudCurrentAuthorityComplete,
        eligibilityConfirmation: cloudEligibilityConfirmation,
      )));
      if (cloudEvaluation?.status ==
              ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired &&
          cloudCurrentAuthorityComplete) {
        lines.add(const SizedBox(height: 8));
        lines.add(Text(
          _cloudEligibilityConfirmationText(cloudEligibilityConfirmation),
          key: Key(
            'invoice_award_cloud_eligibility_status_${candidate.invoiceNumber}',
          ),
        ));
        lines.add(const SizedBox(height: 6));
        lines.add(Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton(
            key: Key('invoice_award_cloud_eligibility_confirm_${candidate.invoiceNumber}'),
            onPressed: onCloudEligibilityDecision == null ? null : () =>
                onCloudEligibilityDecision!(
                  InvoiceAwardCloudEligibilityUserDecision.eligible),
            child: const Text('確認符合資格'),
          ),
          TextButton(
            key: Key('invoice_award_cloud_eligibility_reject_${candidate.invoiceNumber}'),
            onPressed: onCloudEligibilityDecision == null ? null : () =>
                onCloudEligibilityDecision!(
                  InvoiceAwardCloudEligibilityUserDecision.ineligible),
            child: const Text('確認不符合資格'),
          ),
        ]));
      }
      final fingerprint = cloudEvaluation?.indexSha256;
      if (fingerprint != null && fingerprint.length >= 12) {
        lines.add(const SizedBox(height: 2));
        lines.add(Text(
          '雲端索引指紋：${fingerprint.substring(0, 12)}…',
          style: Theme.of(context).textTheme.bodySmall,
        ));
      }
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(candidate.invoiceNumber),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${candidate.invoiceTypeLabel} · ${_formatCandidateDate(candidate.invoiceDate)}'),
            Text(
              '${candidate.merchantDisplayName} · '
              '${candidate.transactionCurrencyCode} '
              '${_formatTransactionAmount(candidate.transactionAmount)}',
            ),
            const SizedBox(height: 6),
            ...lines,
          ],
        ),
      ),
    );
  }
}

String _generalResultText(ExistingInvoiceAwardGeneralEvaluation? evaluation) {
  if (evaluation == null) return '一般獎：官方資料尚未可判定';
  if (evaluation.isWinner) {
    return '一般獎：${evaluation.tierLabel} · NT\$${_formatAmount(evaluation.grossAmount)}';
  }
  return switch (evaluation.status) {
    ExistingInvoiceAwardGeneralEvaluationStatus.invalid => '一般獎：資料不足，需人工確認',
    ExistingInvoiceAwardGeneralEvaluationStatus.outOfPeriod => '一般獎：非目前檢查期別',
    _ => '一般獎：未中獎',
  };
}

String _winnerSummaryText(
  ExistingInvoiceAwardGeneralEvaluation? general,
  ExistingInvoiceAwardCloudEvaluation? cloud, {
  required bool currentCloudAuthorityComplete,
  InvoiceAwardCloudEligibilityConfirmation? eligibilityConfirmation,
}) {
  final parts = <String>[];
  if (general?.isWinner ?? false) {
    parts.add(
      '一般獎 ${general!.tierLabel} NT\$${_formatAmount(general.grossAmount)}',
    );
  }
  if (cloud?.hasCloudNumberMatch ?? false) {
    final suffix = cloud!.requiresReview || !currentCloudAuthorityComplete
        ? eligibilityConfirmation?.confirmsEligibility == true
            ? '（已由你確認資格）'
            : eligibilityConfirmation?.confirmsIneligibility == true
                ? '（你已確認不符合資格）'
                : '（資格待確認）'
        : '';
    parts.add(
      '雲端專屬獎 NT\$${_formatAmount(cloud.grossAmount)}$suffix',
    );
  }
  return parts.isEmpty ? '尚無中獎結果' : parts.join(' · ');
}

String _cloudResultText(
  ExistingInvoiceAwardCloudEvaluation? evaluation, {
  required bool currentAuthorityComplete,
  InvoiceAwardCloudEligibilityConfirmation? eligibilityConfirmation,
}) {
  if (evaluation == null) return '雲端專屬獎：尚未可判定';
  if (!currentAuthorityComplete &&
      evaluation.status != ExistingInvoiceAwardCloudEvaluationStatus.ineligible &&
      evaluation.status != ExistingInvoiceAwardCloudEvaluationStatus.notApplicable) {
    if (evaluation.hasCloudNumberMatch) {
      return '雲端專屬獎：既有已驗證資料號碼吻合 · '
          'NT\$${_formatAmount(evaluation.grossAmount)}；本次獎號更新不完整，需確認';
    }
    return '雲端專屬獎：獎號資料不完整，無法確認未中獎';
  }
  return switch (evaluation.status) {
    ExistingInvoiceAwardCloudEvaluationStatus.notApplicable => '雲端專屬獎：不適用',
    ExistingInvoiceAwardCloudEvaluationStatus.ineligible => '雲端專屬獎：依現有資格證據不適用',
    ExistingInvoiceAwardCloudEvaluationStatus.invalidPeriod => '雲端專屬獎：期別資料異常，需確認',
    ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete => '雲端專屬獎：獎號資料不完整，無法確認未中獎',
    ExistingInvoiceAwardCloudEvaluationStatus.notMatched => '雲端專屬獎：未中獎',
    ExistingInvoiceAwardCloudEvaluationStatus.matchedEligible =>
      '雲端專屬獎：號碼吻合 · NT\$${_formatAmount(evaluation.grossAmount)}；仍請依官方兌獎規則確認',
    ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired =>
      eligibilityConfirmation?.confirmsEligibility == true
          ? '雲端專屬獎：號碼吻合 · NT\${_formatAmount(evaluation.grossAmount)}；'
              '你已確認符合兌獎資格'
          : eligibilityConfirmation?.confirmsIneligibility == true
              ? '雲端專屬獎：號碼吻合 · NT\${_formatAmount(evaluation.grossAmount)}；'
                  '你已確認不符合兌獎資格'
              : '雲端專屬獎：號碼吻合 · NT\${_formatAmount(evaluation.grossAmount)}；'
                  '資格待確認（請核對開獎前是否曾列印證明聯）',
    ExistingInvoiceAwardCloudEvaluationStatus.anomalyReviewRequired =>
      '雲端專屬獎：號碼出現在多個獎別資料；暫列最高 NT\$${_formatAmount(evaluation.grossAmount)}，需人工確認',
  };
}

String _cloudEligibilityConfirmationKey(
  ExistingInvoiceAwardCloudEvaluation evaluation,
) =>
    '${evaluation.candidate.dedupeKey}|${evaluation.selectedTierCode ?? ''}';

String _cloudEligibilityConfirmationText(
  InvoiceAwardCloudEligibilityConfirmation? confirmation,
) {
  if (confirmation?.confirmsEligibility == true) {
    return '兌獎資格：你已確認符合。此紀錄可供後續兌獎／記帳流程判斷；本版不會自動建立交易。';
  }
  if (confirmation?.confirmsIneligibility == true) {
    return '兌獎資格：你已確認不符合。後續自動入帳不得使用這筆雲端獎。';
  }
  return '兌獎資格：待你確認。號碼吻合不等於已確認可兌獎。';
}

String _cloudTierProgressSummary(CloudAwardForegroundProgress progress) {
  final message = progress.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  return switch (progress.stage) {
    CloudAwardForegroundStage.downloading =>
      '下載中 ${_downloadProgress(progress)}',
    CloudAwardForegroundStage.downloadedSaved => '下載完成並已保存',
    CloudAwardForegroundStage.cachedPdfReused => '重用已保存官方 PDF',
    CloudAwardForegroundStage.extracting =>
      '解析 ${progress.pageNumber ?? 0}/${progress.pageCount ?? 0} 頁'
      '${progress.rowCount == null ? '' : ' · rows=${progress.rowCount}'}',
    CloudAwardForegroundStage.promoting =>
      '正在驗證並保存'
      '${progress.rowCount == null ? '' : ' · rows=${progress.rowCount}'}',
    CloudAwardForegroundStage.candidateVerified => '候選範圍已驗證',
    CloudAwardForegroundStage.reused =>
      '重用已驗證資料'
      '${progress.rowCount == null ? '' : ' · rows=${progress.rowCount}'}',
    CloudAwardForegroundStage.failed => '更新失敗',
    _ => progress.stage.name,
  };
}

String _terminalCloudTierSummary(
  CloudAwardTierRefreshResult result,
  String? latestProgress,
) {
  return switch (result.status) {
    CloudAwardTierRefreshStatus.failed =>
      '失敗：${result.failureCode ?? 'UNKNOWN'}',
    CloudAwardTierRefreshStatus.candidateScopedEmptyVerified =>
      '候選 0/0 · 已驗證（略過大型 PDF）',
    CloudAwardTierRefreshStatus.candidateScopedVerified =>
      latestProgress ??
          '候選範圍已驗證並保存 · 吻合 '
              '${result.candidateAuthority?.matchedInvoiceNumbers.length ?? 0}',
    CloudAwardTierRefreshStatus.candidateScopedReused =>
      latestProgress ??
          '重用候選範圍 · 吻合 '
              '${result.candidateAuthority?.matchedInvoiceNumbers.length ?? 0}',
    CloudAwardTierRefreshStatus.promoted =>
      '完整索引已保存 · rows=${result.snapshot?.manifest.rowCount ?? 0}',
    CloudAwardTierRefreshStatus.reused =>
      '重用已驗證資料 · rows=${result.snapshot?.manifest.rowCount ?? 0}',
  };
}

String _safeCloudFailureCode(Object error) {
  if (error is PlatformException) return error.code;
  final text = error.toString().toUpperCase();
  final match = RegExp(r'(?:CLOUD|PLATFORM|PDFIUM|PDF)_[A-Z0-9_]+').firstMatch(text);
  return match?.group(0) ?? error.runtimeType.toString();
}

String _cloudProgressText(CloudAwardForegroundProgress progress) {
  final tier = progress.tierCode == null ? '' : '${_tierLabel(progress.tierCode!)} · ';
  return switch (progress.stage) {
    CloudAwardForegroundStage.publication => '雲端專屬獎：正在取得財政部官方公告…',
    CloudAwardForegroundStage.downloading => '雲端專屬獎：$tier${_downloadProgress(progress)}',
    CloudAwardForegroundStage.downloadedSaved => '雲端專屬獎：$tier下載完成並已保存，準備解析…',
    CloudAwardForegroundStage.cachedPdfReused => '雲端專屬獎：$tier重用已保存官方 PDF，準備解析…',
    CloudAwardForegroundStage.extracting => progress.message != null
        ? '雲端專屬獎：$tier${progress.message!}'
        : '雲端專屬獎：$tier解析 PDF ${progress.pageNumber ?? 0}/${progress.pageCount ?? 0} 頁 · 已建立 ${progress.rowCount ?? 0} 筆索引',
    CloudAwardForegroundStage.promoting => '雲端專屬獎：$tier正在驗證並保存本機索引…',
    CloudAwardForegroundStage.candidateVerified =>
      '雲端專屬獎：$tier${progress.message ?? '候選範圍已驗證'}',
    CloudAwardForegroundStage.reused => '雲端專屬獎：$tier已重用本機驗證資料',
    CloudAwardForegroundStage.completed => '雲端專屬獎四個官方獎別資料已驗證完成。',
    CloudAwardForegroundStage.failed => '雲端專屬獎：$tier更新未完成；保留既有已驗證資料',
  };
}

String _downloadProgress(CloudAwardForegroundProgress progress) {
  final downloaded = _formatMegabytes(progress.downloadedBytes);
  final declared = progress.declaredBytes;
  final rate = progress.bytesPerSecond;
  final totalText = declared == null ? '' : ' / ${_formatMegabytes(declared)}';
  final rateText = rate == null || rate <= 0 ? '' : ' · ${(rate / 1048576).toStringAsFixed(1)} MB/s';
  return '下載 $downloaded$totalText$rateText';
}

String _formatMegabytes(int? bytes) {
  if (bytes == null) return '0.0 MB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

String _tierLabel(String tierCode) => switch (tierCode) {
  'cloud-1000000' => '100萬元獎',
  'cloud-2000' => '2,000元獎',
  'cloud-800' => '800元獎',
  'cloud-500' => '500元獎',
  _ => tierCode,
};

String _candidateKey(ExistingInvoiceAwardCandidate candidate) =>
    '${candidate.transactionId}|${candidate.invoiceNumber}|${candidate.invoiceDate.toIso8601String()}';

String _formatCandidateDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _formatTransactionAmount(double value) {
  final rounded = value.roundToDouble();
  final text = value == rounded
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = _formatAmount(int.parse(parts.first));
  return parts.length == 1 ? whole : '$whole.${parts.last}';
}

String _formatAmount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
