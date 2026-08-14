import 'package:flutter/material.dart';

import 'authenticated_selector_capability_probe.dart';
import 'disposable_webview_session.dart';
import 'official_mobile_selector_capability_profile.dart';
import 'official_query_page_preparation.dart';

class AuthenticatedSelectorProbePanel extends StatefulWidget {
  const AuthenticatedSelectorProbePanel({
    super.key,
    required this.controller,
  });

  static const Key probeButtonKey = Key('selector_probe_button');
  static const Key prepareButtonKey = Key('selector_prepare_page_button');
  static const Key progressKey = Key('selector_probe_progress');
  static const Key reportKey = Key('selector_probe_report');
  static const Key preparationResultKey = Key('selector_preparation_result');
  static const Key fallbackKey = Key('selector_probe_csv_fallback');

  final DisposableWebViewSessionController controller;

  @override
  State<AuthenticatedSelectorProbePanel> createState() =>
      _AuthenticatedSelectorProbePanelState();
}

class _AuthenticatedSelectorProbePanelState
    extends State<AuthenticatedSelectorProbePanel> {
  bool _probing = false;
  bool _preparing = false;
  AuthenticatedSelectorCapabilityReport? _report;
  OfficialQueryPagePreparationResult? _preparationResult;
  bool _probeFailed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(AuthenticatedSelectorProbePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onSessionChanged);
    widget.controller.addListener(_onSessionChanged);
    _clearProbeState();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (widget.controller.phase != DisposableWebViewSessionPhase.active) {
      setState(_clearProbeState);
      return;
    }
    setState(() {});
  }

  void _clearProbeState() {
    _probing = false;
    _preparing = false;
    _report = null;
    _preparationResult = null;
    _probeFailed = false;
  }

  Future<void> _runProbe() async {
    if (_probing || !widget.controller.canProbeAuthenticatedSelectors) return;
    setState(() {
      _probing = true;
      _report = null;
      _probeFailed = false;
    });
    try {
      final report =
          await widget.controller.probeAuthenticatedSelectorCapabilities();
      if (!mounted) return;
      setState(() {
        _probing = false;
        _report = report;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeFailed = true;
      });
    }
  }

  Future<void> _prepareCurrentPage() async {
    if (_preparing || !widget.controller.canPrepareOfficialQueryPage) return;
    setState(() {
      _preparing = true;
      _preparationResult = null;
    });
    try {
      final result =
          await widget.controller.prepareOfficialQueryPageForExport();
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _preparationResult = result;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _preparationResult = const OfficialQueryPagePreparationResult(
          code: 'PAGE_PREPARATION_EXECUTION_FAILED',
          routeApproved: false,
          pageSizeControlFound: false,
          pageSize100Requested: false,
          pageSizeApplyControlFound: false,
          pageSizeApplyTriggered: false,
          pageSizeAlreadyApplied: false,
          headerCheckboxFound: false,
          headerCheckboxSelected: false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final preparationResult = _preparationResult;
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        primary: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '登入後頁面相容性檢查',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '結構檢查不讀取或保存發票欄位值。只有您主動按下「準備本頁匯出」時，才會操作官方可見的每頁筆數選單、套用箭頭與表頭全選框。',
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                key: AuthenticatedSelectorProbePanel.probeButtonKey,
                onPressed:
                    widget.controller.canProbeAuthenticatedSelectors &&
                            !_probing
                        ? _runProbe
                        : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('檢查查詢頁相容性'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: AuthenticatedSelectorProbePanel.prepareButtonKey,
                onPressed: widget.controller.canPrepareOfficialQueryPage &&
                        !_preparing
                    ? _prepareCurrentPage
                    : null,
                icon: const Icon(Icons.select_all_outlined),
                label: Text(_preparing ? '正在準備本頁…' : '準備本頁匯出（100 筆並全選）'),
              ),
              if (_probing || _preparing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  key: AuthenticatedSelectorProbePanel.progressKey,
                ),
              ],
              if (preparationResult != null) ...[
                const SizedBox(height: 10),
                Text(
                  preparationResult.accepted
                      ? preparationResult.pageSizeAlreadyApplied
                          ? '官方頁面已是每頁 100 筆，已啟動表頭全選。請回到頁面確認後，再親自點擊官方下載按鈕。'
                          : '已切換為 100 並啟動官方套用箭頭；重新載入後將執行表頭全選。請回到頁面確認後，再親自點擊官方下載按鈕。'
                      : '本頁尚未完成匯出準備（${preparationResult.code}）。',
                  key: AuthenticatedSelectorProbePanel.preparationResultKey,
                ),
              ],
              if (_probeFailed) ...[
                const SizedBox(height: 12),
                const Text('結構檢查未完成，請改用財政部 CSV 匯入。'),
                const SizedBox(height: 4),
                const Text(
                  '無法自動讀取？請於財政部頁面下載雲端發票明細 CSV 後上傳。',
                  key: AuthenticatedSelectorProbePanel.fallbackKey,
                ),
              ],
              if (report != null) ...[
                const SizedBox(height: 12),
                _ProbeReportView(report: report),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProbeReportView extends StatelessWidget {
  const _ProbeReportView({required this.report});

  final AuthenticatedSelectorCapabilityReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: AuthenticatedSelectorProbePanel.reportKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusRow(
          label: '指定查詢頁',
          passed: report.routeApproved,
          value: report.routeApproved ? '符合' : '不符合',
        ),
        _StatusRow(
          label: '可進入查詢欄位填入階段',
          passed: report.canProceedToQueryPopulation,
          value: report.canProceedToQueryPopulation ? '可以' : '阻擋',
        ),
        _StatusRow(
          label: '結果表格結構可供擷取',
          passed: report.canProceedToResultExtraction,
          value: report.canProceedToResultExtraction ? '可以' : '尚未確認',
        ),
        _StatusRow(
          label: '每頁筆數選項',
          passed: report.availablePageSizes.isNotEmpty,
          value: report.availablePageSizes.isEmpty
              ? '未找到（選用）'
              : report.availablePageSizes.join(' / '),
        ),
        const Divider(),
        for (final capability in AuthenticatedSelectorCapability.values)
          _CapabilityRow(
            capability: capability,
            match: report.matches[capability],
          ),
        if (report.requiresManualCsvFallback) ...[
          const Divider(),
          const Text(
            '目前頁面結構無法安全進入自動取得流程，請改用財政部 CSV 匯入。',
            key: AuthenticatedSelectorProbePanel.fallbackKey,
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.passed,
    required this.value,
  });

  final String label;
  final bool passed;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_outline : Icons.block_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.capability, required this.match});

  final AuthenticatedSelectorCapability capability;
  final AuthenticatedSelectorCapabilityMatch? match;

  @override
  Widget build(BuildContext context) {
    final currentMatch = match;
    final required = isOfficialMobileRequiredCapability(capability);
    final found = currentMatch?.valid ?? false;
    final value = currentMatch == null
        ? required
            ? '未回報'
            : '未回報（選用）'
        : currentMatch.ambiguous
            ? required
                ? '過多（${currentMatch.matchCount}）'
                : '過多（選用）'
            : currentMatch.found
                ? '找到（${currentMatch.matchCount}）'
                : required
                    ? '未找到'
                    : '未找到（選用）';
    return _StatusRow(
      label: _capabilityLabel(capability),
      passed: found || !required,
      value: value,
    );
  }

  String _capabilityLabel(AuthenticatedSelectorCapability capability) {
    return switch (capability) {
      AuthenticatedSelectorCapability.startDate => '起始日期欄位',
      AuthenticatedSelectorCapability.endDate => '結束日期欄位',
      AuthenticatedSelectorCapability.carrierSelector => '歸戶載具選單',
      AuthenticatedSelectorCapability.invoiceStatusSelector => '發票狀態選單',
      AuthenticatedSelectorCapability.buyerIdentifierInput => '買方統編欄位',
      AuthenticatedSelectorCapability.itemKeywordInput => '品名關鍵字欄位',
      AuthenticatedSelectorCapability.queryButton => '查詢按鈕',
      AuthenticatedSelectorCapability.clearButton => '清除按鈕',
      AuthenticatedSelectorCapability.pageSizeSelector => '每頁筆數選單',
      AuthenticatedSelectorCapability.currentPageIndicator => '目前頁碼',
      AuthenticatedSelectorCapability.totalPageIndicator => '總頁數',
      AuthenticatedSelectorCapability.totalRowIndicator => '總筆數',
      AuthenticatedSelectorCapability.resultTable => '結果表格',
    };
  }
}
