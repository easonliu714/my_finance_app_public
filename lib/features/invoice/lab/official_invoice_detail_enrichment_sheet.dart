// ignore_for_file: deprecated_member_use, prefer_const_constructors

import 'package:flutter/material.dart';

import 'disposable_webview_session.dart';
import 'official_invoice_detail_enrichment.dart';
import 'official_invoice_detail_enrichment_review_page.dart';
import 'official_invoice_detail_screen_awake_guard.dart';

class OfficialInvoiceDetailEnrichmentSheet extends StatefulWidget {
  const OfficialInvoiceDetailEnrichmentSheet({
    super.key,
    required this.controller,
  });

  static const consentKey = Key('official_detail_consent');
  static const startKey = Key('official_detail_start');
  static const cancelKey = Key('official_detail_cancel');
  static const reviewButtonKey = Key('official_detail_review_button');
  static const refreshSelectionKey = Key('official_detail_refresh_selection');

  final DisposableWebViewSessionController controller;

  @override
  State<OfficialInvoiceDetailEnrichmentSheet> createState() =>
      _OfficialInvoiceDetailEnrichmentSheetState();
}

class _OfficialInvoiceDetailEnrichmentSheetState
    extends State<OfficialInvoiceDetailEnrichmentSheet> {
  late Future<OfficialInvoiceDetailTargetReport> _targetsFuture;
  OfficialInvoiceDetailSelectionScope _scope =
      OfficialInvoiceDetailSelectionScope.singleInvoice;
  String? _singleInvoiceNumber;
  bool _selectionInitialized = false;
  bool _consentAccepted = false;
  bool _running = false;
  bool _refreshingTargets = false;
  String? _selectionNotice;
  OfficialInvoiceDetailProgress? _progress;
  OfficialInvoiceDetailBatchResult? _result;
  Object? _error;
  final OfficialInvoiceDetailScreenAwakeGuard _screenAwakeGuard =
      OfficialInvoiceDetailScreenAwakeGuard();

  @override
  void initState() {
    super.initState();
    _targetsFuture = _inspectStableTargets(
      initialDelay: const Duration(milliseconds: 250),
    );
  }

  Future<OfficialInvoiceDetailTargetReport> _inspectStableTargets({
    Duration initialDelay = Duration.zero,
  }) async {
    if (initialDelay > Duration.zero) {
      await Future<void>.delayed(initialDelay);
    }
    OfficialInvoiceDetailTargetReport? lastReport;
    String? lastFingerprint;
    var stableSamples = 0;
    for (var attempt = 0; attempt < 5; attempt += 1) {
      final report =
          await widget.controller.inspectOfficialDetailTargets();
      final fingerprint = _selectionFingerprint(report);
      if (fingerprint == lastFingerprint) {
        stableSamples += 1;
      } else {
        lastFingerprint = fingerprint;
        stableSamples = 1;
      }
      lastReport = report;
      final requiredSamples = report.selectedCount > 0 ? 2 : 3;
      if (stableSamples >= requiredSamples) return report;
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    if (lastReport != null) return lastReport;
    return widget.controller.inspectOfficialDetailTargets();
  }

  String _selectionFingerprint(OfficialInvoiceDetailTargetReport report) {
    final selected = report.targets
        .where((target) => target.selected)
        .map((target) => target.invoiceNumber.trim().toUpperCase())
        .toList(growable: false)
      ..sort();
    return '${report.routeApproved}|${report.targets.length}|${selected.join(',')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: FutureBuilder<OfficialInvoiceDetailTargetReport>(
          future: _targetsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _buildInspectionFailure(snapshot.error);
            }
            final report = snapshot.data!;
            if (!report.canStart) return _buildUnavailable(report);
            _initializeSelection(report);
            return _buildContent(report);
          },
        ),
      ),
    );
  }

  Widget _buildContent(OfficialInvoiceDetailTargetReport report) {
    final selectedCount = report.selectedCount;
    final scopeCount = switch (_scope) {
      OfficialInvoiceDetailSelectionScope.singleInvoice => 1,
      OfficialInvoiceDetailSelectionScope.selectedInvoices => selectedCount,
      OfficialInvoiceDetailSelectionScope.currentPage => report.targets.length,
    };
    final allResultsScope =
        _scope == OfficialInvoiceDetailSelectionScope.currentPage;
    final scopeDescription =
        allResultsScope ? '目前查詢結果全部' : '$scopeCount 筆';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          '補充官方發票明細',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '本功能在目前一次性 WebView 工作階段中逐筆開啟財政部官方發票明細。執行期間會防止系統自動熄屏；手動鎖定或切換 App 時暫停逾時計時，回到前景後延續目前記憶體佇列。',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '將讀取的標準化欄位',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text('• 精確發票日期時間與顯示幣別'),
                Text('• 官方狀態、賣方名稱與統編一致性'),
                Text('• 品名、數量、單價、金額與總額一致性'),
                Text('• 擷取時間與 selector profile 版本'),
                SizedBox(height: 8),
                Text(
                  '不保存帳號、密碼、Cookie、DOM、HTML、截圖、驗證碼、下載網址或頁面網址。單筆失敗不會改動 CSV 或其他發票。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '目前頁面可辨識 ${report.targets.length} 筆；已勾選 $selectedCount 筆。選擇「全部」時，開始後才會切換為每頁 100 筆。',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '勾選狀態說明',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  '只有官方頁面的藍底白勾代表已納入；黃色或橘色外框只是鍵盤／點擊焦點，不會算成已選取。',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: OfficialInvoiceDetailEnrichmentSheet.refreshSelectionKey,
                  onPressed: _running || _refreshingTargets
                      ? null
                      : _refreshTargets,
                  icon: _refreshingTargets
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _refreshingTargets ? '正在重新讀取' : '重新讀取官方勾選狀態',
                  ),
                ),
                if (_selectionNotice != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _selectionNotice!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        RadioListTile<OfficialInvoiceDetailSelectionScope>(
          value: OfficialInvoiceDetailSelectionScope.singleInvoice,
          groupValue: _scope,
          onChanged: _running || _refreshingTargets ? null : _setScope,
          title: const Text('單一發票'),
          subtitle: const Text('只開啟下方指定的 1 筆發票。'),
        ),
        if (_scope == OfficialInvoiceDetailSelectionScope.singleInvoice)
          DropdownButtonFormField<String>(
            value: _singleInvoiceNumber,
            decoration: const InputDecoration(labelText: '指定發票號碼'),
            items: report.targets
                .map(
                  (target) => DropdownMenuItem<String>(
                    value: target.invoiceNumber,
                    child: Text(target.invoiceNumber),
                  ),
                )
                .toList(growable: false),
            onChanged: _running || _refreshingTargets
                ? null
                : (value) => setState(() => _singleInvoiceNumber = value),
          ),
        RadioListTile<OfficialInvoiceDetailSelectionScope>(
          value: OfficialInvoiceDetailSelectionScope.selectedInvoices,
          groupValue: _scope,
          onChanged: _running || _refreshingTargets || selectedCount == 0
              ? null
              : _setScope,
          title: Text('目前已選取發票（$selectedCount 筆）'),
          subtitle: const Text('只讀取真正 checked 的列；焦點框不會被納入。開始前會再重新檢查一次。'),
        ),
        RadioListTile<OfficialInvoiceDetailSelectionScope>(
          value: OfficialInvoiceDetailSelectionScope.currentPage,
          groupValue: _scope,
          onChanged: _running || _refreshingTargets ? null : _setScope,
          title: const Text('目前查詢結果全部'),
          subtitle: const Text('只有選擇此範圍並按下開始後，才會切換為每頁 100 筆；切換完成後以實際載入筆數為準。'),
        ),
        const Divider(height: 24),
        CheckboxListTile(
          key: OfficialInvoiceDetailEnrichmentSheet.consentKey,
          value: _consentAccepted,
          onChanged: _running || _refreshingTargets
              ? null
              : (value) => setState(() => _consentAccepted = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('我同意本次逐筆開啟 $scopeDescription 的官方發票明細'),
          subtitle: const Text('此勾選預設關閉；中途可取消，未處理發票維持原狀。'),
        ),
        if (_running) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _progress == null || _progress!.total <= 0
                ? null
                : _progress!.current / _progress!.total,
          ),
          const SizedBox(height: 8),
          Text(
            _progress == null
                ? '正在準備逐筆處理…'
                : '${_progress!.current}/${_progress!.total}｜${_progress!.invoiceNumber}｜${_progress!.message}',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: OfficialInvoiceDetailEnrichmentSheet.cancelKey,
            onPressed: _cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('取消後續處理'),
          ),
        ] else ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: OfficialInvoiceDetailEnrichmentSheet.startKey,
            onPressed:
                _consentAccepted && scopeCount > 0 && !_refreshingTargets
                    ? _start
                    : null,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text('開始補充 $scopeDescription 的官方明細'),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '本次處理結果',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('預定：${_result!.requestedCount}'),
                  Text('已取得內容結果：${_result!.results.length}'),
                  Text('成功：${_result!.successCount}'),
                  Text('失敗／需覆核：${_result!.failedCount}'),
                  if (_result!.truncatedCount > 0)
                    Text(
                      '超過 100 項提示：${_result!.truncatedCount} 筆（不阻擋建立草稿或正式交易）',
                    ),
                  Text(
                    '逐筆終態紀錄：${_result!.terminalTraceCount}/${_result!.requestedCount}',
                  ),
                  Text('未完成處理：${_result!.unprocessedCount}'),
                  Text('中途取消：${_result!.cancelled ? '是' : '否'}'),
                  if (_result!.errorCode != null)
                    Text(
                      '狀態：${officialInvoiceDetailFailureLabel(_result!.errorCode!)}',
                    ),
                  if (_result!.unprocessedTraces.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '未完成發票',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    ..._result!.unprocessedTraces.map(
                      (trace) => Text(
                        '• ${trace.ordinal}. ${trace.invoiceNumber}｜'
                        '${officialInvoiceDetailFailureLabel(trace.reasonCode ?? 'DETAIL_MISSING_TERMINAL_RESULT')}',
                      ),
                    ),
                  ],
                  if (_result!.failureCounts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '失敗原因',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    ..._result!.failureCounts.entries.map(
                      (entry) => Text(
                        '• ${officialInvoiceDetailFailureLabel(entry.key)}：${entry.value}',
                      ),
                    ),
                  ],
                  if (_result!.results.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: OfficialInvoiceDetailEnrichmentSheet.reviewButtonKey,
                      onPressed: () => _openReview(_result!),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text('檢視擷取內容（${_result!.results.length} 筆）'),
                    ),
                    const SizedBox(height: 6),
                    const Text('處理完成後會自動開啟內容審查頁；返回後可由此再次檢視。'),
                  ],
                  const SizedBox(height: 6),
                  const Text('成功資料只保留標準化欄位，並於後續 CSV 對帳時再次核對發票號碼與金額。'),
                ],
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('官方明細處理失敗：$_error'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }

  void _initializeSelection(OfficialInvoiceDetailTargetReport report) {
    if (_selectionInitialized) return;
    final selectedTargets = report.targets
        .where((target) => target.selected)
        .toList(growable: false);
    _singleInvoiceNumber =
        (selectedTargets.isNotEmpty
                ? selectedTargets.first
                : report.targets.first)
            .invoiceNumber;
    _scope = selectedTargets.isNotEmpty
        ? OfficialInvoiceDetailSelectionScope.selectedInvoices
        : OfficialInvoiceDetailSelectionScope.singleInvoice;
    _selectionInitialized = true;
  }

  void _setScope(OfficialInvoiceDetailSelectionScope? value) {
    if (value == null) return;
    setState(() {
      _scope = value;
      _consentAccepted = false;
      _result = null;
      _error = null;
      _selectionNotice = null;
    });
  }

  Future<void> _refreshTargets() async {
    if (_refreshingTargets || _running) return;
    setState(() {
      _refreshingTargets = true;
      _error = null;
      _selectionNotice = null;
    });
    try {
      final report = await _inspectStableTargets();
      if (!mounted) return;
      setState(() {
        _selectionInitialized = false;
        _targetsFuture = Future<OfficialInvoiceDetailTargetReport>.value(report);
        _consentAccepted = false;
        _selectionNotice = report.selectedCount == 0
            ? '目前偵測到 0 筆真正勾選；黃色／橘色焦點框不會算入。'
            : '已等待官方頁面狀態穩定並重新讀取：${report.selectedCount} 筆真正勾選。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _refreshingTargets = false);
    }
  }

  Future<OfficialInvoiceDetailTargetReport?> _preflightSelection() async {
    try {
      final report = await _inspectStableTargets();
      if (!mounted) return null;
      setState(() {
        _targetsFuture = Future<OfficialInvoiceDetailTargetReport>.value(report);
        _selectionNotice = '開始前已完成穩定讀取：${report.selectedCount} 筆真正勾選。';
      });
      if (_scope == OfficialInvoiceDetailSelectionScope.selectedInvoices &&
          report.selectedCount == 0) {
        setState(() {
          _consentAccepted = false;
          _error = '目前沒有真正勾選的發票。黃色／橘色外框只是焦點，請回官方頁面點成藍底白勾後再重新讀取。';
        });
        return null;
      }
      if (_scope == OfficialInvoiceDetailSelectionScope.singleInvoice &&
          !report.targets.any(
            (target) => target.invoiceNumber == _singleInvoiceNumber,
          )) {
        setState(() {
          _consentAccepted = false;
          _error = '指定發票已不在目前官方查詢結果中，請重新讀取後再選擇。';
        });
        return null;
      }
      return report;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _consentAccepted = false;
        _error = '開始前重新讀取官方勾選狀態失敗：$error';
      });
      return null;
    }
  }

  Future<void> _start() async {
    final report = await _preflightSelection();
    if (report == null || !mounted) return;

    OfficialInvoiceDetailBatchResult? completedResult;
    setState(() {
      _running = true;
      _progress = null;
      _result = null;
      _error = null;
    });
    await _screenAwakeGuard.acquire();
    try {
      completedResult = await widget.controller.enrichOfficialInvoiceDetails(
        scope: _scope,
        singleInvoiceNumber: _singleInvoiceNumber,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _result = completedResult);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      await _screenAwakeGuard.release();
      if (mounted) {
        setState(() {
          _running = false;
          _consentAccepted = false;
        });
      }
    }

    if (!mounted ||
        completedResult == null ||
        completedResult.results.isEmpty) {
      return;
    }
    await _openReview(completedResult);
  }

  Future<void> _openReview(OfficialInvoiceDetailBatchResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfficialInvoiceDetailEnrichmentReviewPage(
          batchResult: result,
          controller: widget.controller,
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    await widget.controller.cancelOfficialInvoiceDetailEnrichment();
  }

  Widget _buildInspectionFailure(Object? error) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('無法檢查目前官方查詢結果頁。'),
          const SizedBox(height: 8),
          Text('$error'),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailable(OfficialInvoiceDetailTargetReport report) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link_off_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('目前頁面沒有可安全開啟的官方發票明細。'),
          const SizedBox(height: 8),
          Text('狀態：${report.errorCode ?? 'DETAIL_TARGET_UNAVAILABLE'}'),
          const SizedBox(height: 12),
          const Text('請先登入、完成查詢，並停留在含完整發票號碼的結果表格。'),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}
