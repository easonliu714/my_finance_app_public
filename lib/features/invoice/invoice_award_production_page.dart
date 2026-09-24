import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
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
  const InvoiceAwardProductionPage({
    super.key,
    this.clock,
  });

  final DateTime Function()? clock;

  @override
  State<InvoiceAwardProductionPage> createState() =>
      _InvoiceAwardProductionPageState();
}

class _InvoiceAwardProductionPageState extends State<InvoiceAwardProductionPage> {
  final http.Client _httpClient = http.Client();
  final CloudAwardIndexLkgRepository _cloudRepository =
      CloudAwardIndexLkgRepository();

  late final List<InvoiceAwardSelectablePeriod> _periodOptions;
  late InvoiceAwardSelectablePeriod _selectedPeriod;

  bool _refreshing = false;
  bool _cloudCurrentAuthorityComplete = false;
  String _status = '';
  String _cloudStatus = '';
  String _cloudDiagnosticStatus = '';
  String _scanStatus = '';

  List<ExistingInvoiceAwardCandidate> _candidates =
      const <ExistingInvoiceAwardCandidate>[];
  List<ExistingInvoiceAwardGeneralEvaluation> _generalEvaluations =
      const <ExistingInvoiceAwardGeneralEvaluation>[];
  List<ExistingInvoiceAwardCloudEvaluation> _cloudEvaluations =
      const <ExistingInvoiceAwardCloudEvaluation>[];

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
    _candidates = const <ExistingInvoiceAwardCandidate>[];
    _generalEvaluations = const <ExistingInvoiceAwardGeneralEvaluation>[];
    _cloudEvaluations = const <ExistingInvoiceAwardCloudEvaluation>[];
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
    final selected = _periodOptions.firstWhere(
      (item) => item.period.id == periodId,
    );
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
      setState(() {
        _resetSelectedPeriodState(now);
      });
      return;
    }

    setState(() {
      _refreshing = true;
      _status = '正在更新官方 ${selectedPeriod.periodLabel} 中獎資料…';
      _cloudStatus = '準備更新雲端專屬獎官方資料…';
      _cloudDiagnosticStatus = '';
      _scanStatus = '等待官方資料更新後掃描既有正式交易';
    });

    try {
      final preferences = await SharedPreferences.getInstance();
      final generalRepository =
          InvoiceAwardSharedPreferencesLkgRepository(preferences);
      final generalAcquisition = InvoiceAwardOfficialAcquisition(
        client: _httpClient,
        parser: const InvoiceAwardOfficialHtmlParser(),
        repository: generalRepository,
      );
      final generalController = InvoiceAwardProductionRefreshController(
        acquisition: generalAcquisition,
      );
      final generalResult = await generalController.refresh(
        period: selectedPeriod.period,
      );

      if (!mounted) return;
      setState(() {
        _status = generalResult.message;
      });

      final cloudAcquisition = MinistryOfFinanceCloudAwardForegroundAcquisitionService(
        client: _httpClient,
        repository: _cloudRepository,
      );
      final cloudResult = await cloudAcquisition.refresh(
        period: selectedPeriod.period,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _cloudStatus = progress.message;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _cloudCurrentAuthorityComplete = cloudResult.currentAuthorityComplete;
        _cloudStatus = cloudResult.message;
        final diagnostic = cloudResult.diagnostic;
        if (diagnostic != null) {
          _cloudDiagnosticStatus = diagnostic;
        }
      });

      final candidateRepository = ExistingInvoiceAwardCandidateRepository();
      final candidates = await candidateRepository.readCandidates();
      final generalEvaluations = ExistingInvoiceAwardGeneralBatchMatcher().evaluate(
        candidates: candidates,
        dataset: generalResult.dataset,
      );
      final cloudEvaluations = ExistingInvoiceAwardCloudBatchMatcher().evaluate(
        candidates: candidates,
        index: cloudResult.index,
        currentAuthorityComplete: cloudResult.currentAuthorityComplete,
      );

      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _generalEvaluations = generalEvaluations;
        _cloudEvaluations = cloudEvaluations;
        _scanStatus = '已掃描 ${candidates.length} 筆既有正式交易';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '更新或對獎失敗：$error';
        _scanStatus = '未完成既有正式交易掃描';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final canCheck = _selectedPeriod.canCheckAt(now);
    return Scaffold(
      appBar: AppBar(title: const Text('發票對獎')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _selectedPeriod.period.id,
            decoration: const InputDecoration(labelText: '對獎期別'),
            items: _periodOptions
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.period.id,
                    enabled: item.canCheckAt(now),
                    child: Text(
                      item.canCheckAt(now)
                          ? item.periodLabel
                          : '${item.periodLabel}（尚未開獎）',
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: _refreshing ? null : _selectPeriod,
          ),
          const SizedBox(height: 12),
          const Text(
            '雲端專屬獎官方資料可能包含大型 PDF；更新時會顯示下載、解析與索引進度。',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: !_refreshing && canCheck ? _refresh : null,
            child: Text(_refreshing ? '更新中…' : '授權更新並檢查既有交易'),
          ),
          const SizedBox(height: 16),
          Text(_status),
          const SizedBox(height: 8),
          Text(_cloudStatus),
          if (_cloudDiagnosticStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('PDF 解析診斷：$_cloudDiagnosticStatus'),
          ],
          const SizedBox(height: 8),
          Text(_scanStatus),
          const SizedBox(height: 16),
          ...List<Widget>.generate(_candidates.length, (index) {
            final candidate = _candidates[index];
            final general = _generalEvaluations[index];
            final cloud = _cloudEvaluations[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(candidate.invoiceNumber),
                    Text('一般獎：${general.presentationLabel}'),
                    Text('雲端專屬：${cloud.presentationLabel}'),
                    if (!_cloudCurrentAuthorityComplete)
                      const Text('雲端獎號資料不完整，無法確認未中獎'),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
