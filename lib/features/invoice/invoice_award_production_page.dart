import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
import 'invoice_award_cloud_candidate_scope.dart';
import 'invoice_award_cloud_foreground_acquisition.dart';
import 'invoice_award_cloud_pdf_index.dart';
import 'invoice_award_cloud_index_lkg_repository.dart';
import 'invoice_award_official_acquisition.dart';
import 'invoice_award_official_dataset.dart';
import 'invoice_award_official_html_parser.dart';
import 'invoice_award_period_catalog.dart';
import 'invoice_award_production_refresh_controller.dart';
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

class _InvoiceAwardProductionPageState extends State<InvoiceAwardProductionPage> {
  final http.Client _httpClient = http.Client();
  final CloudAwardIndexLkgRepository _cloudRepository = CloudAwardIndexLkgRepository();

  late final List<InvoiceAwardSelectablePeriod> _periodOptions;
  late InvoiceAwardSelectablePeriod _selectedPeriod;

  bool _refreshing = false;
  bool _cloudCurrentAuthorityComplete = false;
  String _status = '';
  String _cloudStatus = '';
  String _cloudDiagnosticStatus = '';
  String _scanStatus = '';

  List<ExistingInvoiceAwardCandidate> _candidates = const [];
  List<ExistingInvoiceAwardGeneralEvaluation> _generalEvaluations = const [];
  List<ExistingInvoiceAwardCloudEvaluation> _cloudEvaluations = const [];

  @override
  void initState() {
    super.initState();
    final now = _now();
    _periodOptions = InvoiceAwardRecentPeriodCatalog.visibleAt(now);
    _selectedPeriod = InvoiceAwardRecentPeriodCatalog.defaultAt(now);
    _resetSelectedPeriodState(now);
    _loadLastPdfDiagnostic();
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

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
    _candidates = const [];
    _generalEvaluations = const [];
    _cloudEvaluations = const [];
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
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final now = _now();
    final selectedPeriod = _selectedPeriod;
    if (!selectedPeriod.canCheckAt(now)) {
      setState(() => _resetSelectedPeriodState(now));
      return;
    }
    final usePreviousPublication =
        InvoiceAwardRecentPeriodCatalog.usesPreviousPublication(selectedPeriod, now);
    setState(() {
      _refreshing = true;
      _cloudCurrentAuthorityComplete = false;
      _cloudDiagnosticStatus = '';
      _status = '正在更新財政部一般獎資料…';
      _cloudStatus = '等待一般獎完成後更新雲端專屬獎…';
      _scanStatus = '等待官方資料驗證後掃描既有交易…';
    });

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
      final dataset = generalResult.dataset;
      final candidates =
          await ExistingInvoiceAwardCandidateRepository().listCandidates();
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
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            _cloudStatus = '雲端專屬獎本次更新失敗；保留既有已驗證資料，結果不會宣稱完整未中獎。';
          });
        }
      }

      final generalEvaluations = dataset == null
          ? const <ExistingInvoiceAwardGeneralEvaluation>[]
          : const ExistingInvoiceAwardGeneralBatchMatcher().evaluate(
              dataset: dataset,
              candidates: candidates,
            );
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
      final currentCandidates = candidates
          .where((candidate) => candidate.awardPeriod == selectedPeriod.candidateAwardPeriodLabel)
          .toList(growable: false);
      final currentKeys = currentCandidates.map(_candidateKey).toSet();
      final generalWinners = generalEvaluations
          .where((item) => currentKeys.contains(_candidateKey(item.candidate)) && item.isWinner)
          .length;
      final cloudNumberMatches = cloudEvaluations
          .where((item) =>
              currentKeys.contains(_candidateKey(item.candidate)) && item.hasCloudNumberMatch)
          .length;

      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _cloudCurrentAuthorityComplete = cloudComplete;
        _candidates = candidates;
        _generalEvaluations = generalEvaluations;
        _cloudEvaluations = cloudEvaluations;
        _scanStatus = '本期既有交易候選 ${currentCandidates.length} 筆；'
            '一般獎中獎 $generalWinners 筆；雲端專屬獎號碼吻合 $cloudNumberMatches 筆。';
        if (generalResult.isSuccess && dataset != null) {
          final fetched = dataset.provenance.fetchedAt.toLocal();
          _status = '一般獎官方資料已驗證：${dataset.period.id} · '
              '更新 ${fetched.year}-${fetched.month.toString().padLeft(2, '0')}-'
              '${fetched.day.toString().padLeft(2, '0')} '
              '${fetched.hour.toString().padLeft(2, '0')}:'
              '${fetched.minute.toString().padLeft(2, '0')}';
        } else if (dataset != null) {
          _status = '一般獎更新失敗；已保留並使用 ${dataset.period.id} 的最後已驗證資料。';
        } else {
          _status = '一般獎更新失敗，且目前沒有可用的已驗證官方資料。';
        }
        if (cloudRefresh != null) {
          _cloudStatus = cloudComplete
              ? '雲端專屬獎四個獎別 authority 已驗證完成。'
              : '雲端專屬獎本次更新不完整：'
                  '${cloudRefresh.failureSummary}; '
                  '保留既有 LKG，無法宣稱完整未中獎。';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _cloudCurrentAuthorityComplete = false;
        _status = '更新失敗；未變更任何既有已驗證資料。';
        _cloudStatus = '雲端專屬獎結果未完成；不會宣稱完整未中獎。';
        _scanStatus = '既有交易掃描未完成；請稍後重新執行授權更新。';
      });
    }
  }

  void _handleCloudProgress(CloudAwardForegroundProgress progress) {
    if (!mounted) return;
    setState(() {
      _cloudStatus = _cloudProgressText(progress);
      final diagnostic = progress.diagnosticMessage;
      if (diagnostic != null && diagnostic.isNotEmpty) {
        _cloudDiagnosticStatus = diagnostic;
      }
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
    final now = _now();
    final canCheckSelectedPeriod = _selectedPeriod.canCheckAt(now);

    return Scaffold(
      appBar: AppBar(title: const Text('統一發票中獎檢查')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
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
                    '四個獎別會依序下載與建立本機索引，已驗證且來源相同的資料會直接重用。'),
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
            if (visibleCandidates.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('既有交易對獎結果', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final candidate in visibleCandidates)
                _ExistingTransactionAwardTile(
                  candidate: candidate,
                  generalEvaluation: generalByKey[_candidateKey(candidate)],
                  cloudEvaluation: cloudByKey[_candidateKey(candidate)],
                  cloudCurrentAuthorityComplete: _cloudCurrentAuthorityComplete,
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
    );
  }
}

class _ExistingTransactionAwardTile extends StatelessWidget {
  const _ExistingTransactionAwardTile({
    required this.candidate,
    required this.generalEvaluation,
    required this.cloudEvaluation,
    required this.cloudCurrentAuthorityComplete,
  });

  final ExistingInvoiceAwardCandidate candidate;
  final ExistingInvoiceAwardGeneralEvaluation? generalEvaluation;
  final ExistingInvoiceAwardCloudEvaluation? cloudEvaluation;
  final bool cloudCurrentAuthorityComplete;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = candidate.identitySource == ExistingInvoiceAwardIdentitySource.cloudMetadata
        ? '雲端發票資料'
        : '發票辨識覆核';
    final lines = <Widget>[Text(_generalResultText(generalEvaluation))];
    if (candidate.identitySource == ExistingInvoiceAwardIdentitySource.cloudMetadata) {
      lines.add(const SizedBox(height: 4));
      lines.add(Text(_cloudResultText(
        cloudEvaluation,
        currentAuthorityComplete: cloudCurrentAuthorityComplete,
      )));
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
            Text('$sourceLabel · ${candidate.awardPeriod} · 交易 ${candidate.transactionId}'),
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

String _cloudResultText(
  ExistingInvoiceAwardCloudEvaluation? evaluation, {
  required bool currentAuthorityComplete,
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
      '雲端專屬獎號碼吻合／資格待確認 · NT\$${_formatAmount(evaluation.grossAmount)}',
    ExistingInvoiceAwardCloudEvaluationStatus.anomalyReviewRequired =>
      '雲端專屬獎：號碼出現在多個獎別資料；暫列最高 NT\$${_formatAmount(evaluation.grossAmount)}，需人工確認',
  };
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

String _formatAmount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
