import 'package:flutter/material.dart';

import 'disposable_webview_session.dart';
import 'official_invoice_detail_enrichment.dart';
import 'official_invoice_detail_retry.dart';
import 'official_invoice_detail_screen_awake_guard.dart';

class OfficialInvoiceDetailRetryPage extends StatefulWidget {
  const OfficialInvoiceDetailRetryPage({
    super.key,
    required this.batchResult,
    required this.controller,
  });

  static const Key consentKey = Key('official_detail_retry_consent');
  static const Key startKey = Key('official_detail_retry_start');
  static const Key returnKey = Key('official_detail_retry_return');

  final OfficialInvoiceDetailBatchResult batchResult;
  final DisposableWebViewSessionController controller;

  @override
  State<OfficialInvoiceDetailRetryPage> createState() =>
      _OfficialInvoiceDetailRetryPageState();
}

class _OfficialInvoiceDetailRetryPageState
    extends State<OfficialInvoiceDetailRetryPage> {
  late OfficialInvoiceDetailBatchResult _mergedResult;
  final Set<int> _selectedOrdinals = <int>{};
  bool _consentAccepted = false;
  bool _running = false;
  OfficialInvoiceDetailProgress? _progress;
  Object? _error;
  int _completedRetryCount = 0;
  final OfficialInvoiceDetailScreenAwakeGuard _screenAwakeGuard =
      OfficialInvoiceDetailScreenAwakeGuard();

  @override
  void initState() {
    super.initState();
    _mergedResult = widget.batchResult;
  }

  @override
  Widget build(BuildContext context) {
    final residuals = _mergedResult.residualItems;
    final technical = residuals
        .where(
          (item) =>
              item.category ==
              OfficialInvoiceDetailResidualCategory.technicalRetryable,
        )
        .toList(growable: false);
    final selected = technical
        .where((item) => _selectedOrdinals.contains(item.ordinal))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('重試失敗／需覆核明細')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '前景局部重試',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '只重新開啟使用者勾選的技術性失敗項目，不會重新執行整批，也不會建立草稿或正式交易。執行期間會防止系統自動熄屏；背景期間暫停等待，回到前景後續行。',
                    ),
                    const SizedBox(height: 8),
                    Text('技術性結果：${technical.length}'),
                    Text('可安全重試：${technical.where((item) => item.retryEligible).length}'),
                    Text('已完成本頁重試：$_completedRetryCount'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final item in technical) ...[
              Card(
                child: CheckboxListTile(
                  key: Key('official_detail_retry_${item.ordinal}'),
                  value: _selectedOrdinals.contains(item.ordinal),
                  onChanged: _running || !item.retryEligible
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _selectedOrdinals.add(item.ordinal);
                            } else {
                              _selectedOrdinals.remove(item.ordinal);
                            }
                            _consentAccepted = false;
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('${item.ordinal}. ${item.invoiceNumber}'),
                  subtitle: Text(
                    '${officialInvoiceDetailResidualReasonLabel(item.reasonCode)}'
                    '${item.retryBlockedReason == null ? '' : '\n${item.retryBlockedReason}'}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (technical.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('目前沒有技術性可重試項目。'),
                ),
              ),
            if (selected.isNotEmpty) ...[
              CheckboxListTile(
                key: OfficialInvoiceDetailRetryPage.consentKey,
                value: _consentAccepted,
                onChanged: _running
                    ? null
                    : (value) => setState(
                          () => _consentAccepted = value ?? false,
                        ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('我確認只在前景重試所選 ${selected.length} 筆官方明細'),
                subtitle: const Text(
                  '不保存帳密、Cookie、DOM、HTML 或截圖；重試結果仍需人工審查。',
                ),
              ),
              FilledButton.icon(
                key: OfficialInvoiceDetailRetryPage.startKey,
                onPressed:
                    !_running && _consentAccepted ? () => _retry(selected) : null,
                icon: const Icon(Icons.refresh_outlined),
                label: Text('開始重試 ${selected.length} 筆'),
              ),
            ],
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
                    ? '正在準備前景重試…'
                    : '${_progress!.current}/${_progress!.total}｜${_progress!.invoiceNumber}｜${_progress!.message}',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('局部重試發生錯誤：$_error'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: OfficialInvoiceDetailRetryPage.returnKey,
              onPressed: _running
                  ? null
                  : () => Navigator.of(context).pop(_mergedResult),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('回到更新後內容審查'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retry(List<OfficialInvoiceDetailResidualItem> selected) async {
    final ordered = selected.toList(growable: false)
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    setState(() {
      _running = true;
      _progress = null;
      _error = null;
    });

    final outcomes = <OfficialInvoiceDetailRetryOutcome>[];
    await _screenAwakeGuard.acquire();
    try {
      for (var index = 0; index < ordered.length; index++) {
        final item = ordered[index];
        try {
          final result = await widget.controller.enrichOfficialInvoiceDetails(
            scope: OfficialInvoiceDetailSelectionScope.singleInvoice,
            singleInvoiceNumber: item.invoiceNumber,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _progress = OfficialInvoiceDetailProgress(
                  current: index + 1,
                  total: ordered.length,
                  invoiceNumber: item.invoiceNumber,
                  message: progress.message,
                );
              });
            },
          );
          outcomes.add(
            OfficialInvoiceDetailRetryOutcome(
              originalOrdinal: item.ordinal,
              invoiceNumber: item.invoiceNumber,
              retryBatchResult: result,
            ),
          );
        } catch (error) {
          outcomes.add(
            OfficialInvoiceDetailRetryOutcome(
              originalOrdinal: item.ordinal,
              invoiceNumber: item.invoiceNumber,
              retryBatchResult: OfficialInvoiceDetailBatchResult(
                requestedCount: 1,
                results: const <OfficialInvoiceDetailEnrichment>[],
                cancelled: false,
                traces: <OfficialInvoiceDetailTraceItem>[
                  OfficialInvoiceDetailTraceItem(
                    invoiceNumber: item.invoiceNumber,
                    ordinal: 1,
                    status: OfficialInvoiceDetailTraceStatus.failed,
                    completedAt: DateTime.now().toUtc(),
                    reasonCode: 'DETAIL_RETRY_EXECUTION_FAILED',
                  ),
                ],
                errorCode: 'DETAIL_RETRY_EXECUTION_FAILED',
              ),
            ),
          );
          _error = error;
        }
      }
    } finally {
      await _screenAwakeGuard.release();
    }

    if (!mounted) return;
    setState(() {
      _mergedResult = _mergedResult.mergeRetryOutcomes(outcomes);
      _completedRetryCount += outcomes.length;
      _selectedOrdinals.clear();
      _consentAccepted = false;
      _running = false;
      _progress = null;
    });
  }
}
