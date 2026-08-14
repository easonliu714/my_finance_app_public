import 'package:flutter/material.dart';

import 'disposable_webview_session.dart';
import 'official_invoice_detail_draft_import_page.dart';
import 'official_invoice_detail_draft_import_v2_service.dart';
import 'official_invoice_detail_enrichment.dart';
import 'official_invoice_detail_retry.dart';
import 'official_invoice_detail_retry_page.dart';

class OfficialInvoiceDetailEnrichmentReviewPage extends StatelessWidget {
  const OfficialInvoiceDetailEnrichmentReviewPage({
    super.key,
    required this.batchResult,
    this.controller,
  });

  static const Key listKey = Key('official_detail_review_list');
  static const Key formalImportButtonKey = Key(
    'official_detail_review_formal_import',
  );

  final OfficialInvoiceDetailBatchResult batchResult;
  final DisposableWebViewSessionController? controller;

  @override
  Widget build(BuildContext context) {
    final eligibleCount = batchResult.results
        .where(isOfficialInvoiceDetailEligibleForFormalImportV2)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('官方明細內容審查')),
      body: SafeArea(
        child: ListView(
          key: listKey,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildSummaryCard(context),
            if (eligibleCount > 0) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '下一步：導入正式交易',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$eligibleCount 筆可進入正式交易預先比對。下一頁會先排除已是正式交易的發票，'
                        '境外交易若只有總額差額，必須逐筆確認推算稅額後才能建立草稿。',
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: formalImportButtonKey,
                        onPressed: () => _openFormalImport(context),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: Text('準備導入正式交易（$eligibleCount 筆）'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '逐筆擷取結果',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              '請展開每一筆，核對官方頁面的發票號碼、精確時間、賣方、總額、官方稅額與消費明細。'
              '若官方頁面未明示稅額，但官方總額與品項小計均已確認，下一頁可由使用者逐筆確認差額作為「推算稅額」；系統不推算稅率。',
            ),
            const SizedBox(height: 12),
            for (
              var index = 0;
              index < batchResult.results.length;
              index++
            ) ...[
              _buildInvoiceCard(context, batchResult.results[index], index),
              const SizedBox(height: 10),
            ],
            if (batchResult.results.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('本次沒有可供審查的擷取結果。'),
                ),
              ),
            if (batchResult.residualItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildResidualSummaryCard(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResidualSummaryCard(BuildContext context) {
    final technical = batchResult.technicalRetryableCount;
    final safeRetryable = batchResult.safeRetryableCount;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('剩餘結果診斷', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('可確認推算稅額：${batchResult.estimatedTaxReviewCount}'),
            Text('技術性可重試：$technical'),
            Text('來源內容不足：${batchResult.sourceContentIncompleteCount}'),
            Text('身分／總額衝突：${batchResult.identityOrTotalConflictCount}'),
            Text('其他需覆核：${batchResult.otherFailClosedCount}'),
            if (technical > safeRetryable)
              Text('因同號碼重複而禁止自動重試：${technical - safeRetryable}'),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('official_detail_review_retry_button'),
              onPressed: controller != null && safeRetryable > 0
                  ? () => _openRetry(context)
                  : null,
              icon: const Icon(Icons.refresh_outlined),
              label: Text('只重試技術性失敗（$safeRetryable 筆）'),
            ),
            const SizedBox(height: 6),
            const Text('重試只在目前 WebView 前景工作階段執行；來源內容不足與身分／總額衝突維持 fail-closed。'),
          ],
        ),
      ),
    );
  }

  Future<void> _openRetry(BuildContext context) async {
    final currentController = controller;
    if (currentController == null) return;
    final updated = await Navigator.of(context)
        .push<OfficialInvoiceDetailBatchResult>(
          MaterialPageRoute<OfficialInvoiceDetailBatchResult>(
            builder: (_) => OfficialInvoiceDetailRetryPage(
              batchResult: batchResult,
              controller: currentController,
            ),
          ),
        );
    if (!context.mounted || updated == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfficialInvoiceDetailEnrichmentReviewPage(
          batchResult: updated,
          controller: currentController,
        ),
      ),
    );
  }

  Future<void> _openFormalImport(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OfficialInvoiceDetailDraftImportPage(batchResult: batchResult),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本次審查摘要',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('預定：${batchResult.requestedCount}'),
            Text('已取得內容結果：${batchResult.results.length}'),
            Text('成功：${batchResult.successCount}'),
            Text('失敗／需覆核：${batchResult.failedCount}'),
            if (batchResult.truncatedCount > 0)
              Text(
                '超過 100 項提示：${batchResult.truncatedCount} 筆；可繼續建立草稿與正式交易',
              ),
            Text(
              '逐筆終態紀錄：${batchResult.terminalTraceCount}/${batchResult.requestedCount}',
            ),
            Text('未完成處理：${batchResult.unprocessedCount}'),
            Text('中途取消：${batchResult.cancelled ? '是' : '否'}'),
            if (batchResult.unprocessedTraces.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                '未完成發票',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              ...batchResult.unprocessedTraces.map(
                (trace) => Text(
                  '• ${trace.ordinal}. ${trace.invoiceNumber}｜'
                  '${officialInvoiceDetailFailureLabel(trace.reasonCode ?? 'DETAIL_MISSING_TERMINAL_RESULT')}',
                ),
              ),
            ],
            if (batchResult.errorCode != null)
              Text(
                '批次狀態：${officialInvoiceDetailFailureLabel(batchResult.errorCode!)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(
    BuildContext context,
    OfficialInvoiceDetailEnrichment item,
    int index,
  ) {
    final invoiceNumber = item.invoiceNumber.isNotEmpty
        ? item.invoiceNumber
        : item.requestedInvoiceNumber;
    final subtitle = <String>[
      _formatDateTime(item.exactTimestamp),
      item.sellerName ?? '賣方未提供',
      _formatAmount(item.detailTotal, item.currencyCode),
    ].join('｜');

    return Card(
      child: ExpansionTile(
        key: Key('official_detail_review_$invoiceNumber'),
        initiallyExpanded: batchResult.results.length == 1,
        title: Row(
          children: [
            Expanded(
              child: Text(
                invoiceNumber,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Chip(
              label: Text(
                officialInvoiceDetailResidualCategoryForEnrichment(item).label,
              ),
            ),
          ],
        ),
        subtitle: Text(subtitle),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.lineItemsTruncated) ...[
                  Container(
                    key: Key('official_detail_truncated_warning_$invoiceNumber'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '此發票官方明細共 ${item.declaredItemCount ?? '超過 100'} 項，'
                      '目前只列入可讀取的前 ${item.lineItems.length} 項；'
                      '另有 ${item.omittedItemCount} 項未列入。這不會阻擋建立草稿或正式交易，'
                      '請在正式交易中自行補充其餘明細。',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _sectionTitle(context, '官方欄位'),
                _fieldRow('指定發票號碼', item.requestedInvoiceNumber),
                _fieldRow(
                  '擷取發票號碼',
                  item.invoiceNumber.isEmpty ? '未取得' : item.invoiceNumber,
                ),
                _fieldRow('精確日期時間', _formatDateTime(item.exactTimestamp)),
                _fieldRow('官方狀態', item.officialStatus ?? '未提供'),
                _fieldRow('賣方名稱', item.sellerName ?? '未提供'),
                _fieldRow('賣方統編', item.sellerIdentifier ?? '未提供'),
                _fieldRow(
                  '品項小計',
                  _formatAmount(item.lineItemSubtotal, item.currencyCode),
                ),
                _fieldRow(
                  '官方稅額',
                  _formatAmount(item.officialTaxAmount, item.currencyCode),
                ),
                _fieldRow('稅額來源', item.officialTaxLabel ?? '官方頁面未提供'),
                if (item.positiveEstimatedTaxAmount != null)
                  _fieldRow(
                    '推算稅額（待確認）',
                    _formatAmount(
                      item.positiveEstimatedTaxAmount,
                      item.currencyCode,
                    ),
                  ),
                _fieldRow(
                  '官方明細總額',
                  _formatAmount(item.detailTotal, item.currencyCode),
                ),
                _fieldRow(
                  '查詢／CSV 預期總額',
                  _formatAmount(item.expectedTotal, item.currencyCode),
                ),
                _fieldRow(
                  '未分配差額',
                  _formatAmount(item.unallocatedDifference, item.currencyCode),
                ),
                _fieldRow('幣別', item.currencyCode ?? '官方頁面未提供'),
                const SizedBox(height: 12),
                _sectionTitle(context, '一致性檢查'),
                _checkRow('發票號碼一致', item.invoiceIdentityMatches),
                if (item.lineItemsTruncated)
                  _fieldRow(
                    '品項完整性',
                    '僅讀取前 100 項；不要求可見品項小計等於官方總額',
                  )
                else
                  _checkRow(
                    '品項小計＋官方稅額與官方總額一致',
                    item.detailTotalInternallyConsistent,
                  ),
                if (item.positiveEstimatedTaxAmount != null)
                  _checkRow(
                    '官方總額－品項小計可形成待確認推算稅額',
                    item.canUseUserConfirmedEstimatedTax,
                  ),
                _checkRow('官方總額與查詢／CSV 一致', item.detailTotalMatchesCsv),
                _checkRow('賣方統編一致', item.sellerIdentifierConsistent),
                const SizedBox(height: 12),
                _sectionTitle(
                  context,
                  item.lineItemsTruncated
                      ? '消費明細（已列入 ${item.lineItems.length}/${item.declaredItemCount ?? '100+'} 項）'
                      : '消費明細（${item.lineItems.length} 項）',
                ),
                if (item.lineItems.isEmpty)
                  const Text('未取得可顯示的消費明細。')
                else
                  for (
                    var itemIndex = 0;
                    itemIndex < item.lineItems.length;
                    itemIndex++
                  )
                    _buildLineItem(
                      item.lineItems[itemIndex],
                      item.currencyCode,
                      invoiceNumber,
                      itemIndex,
                    ),
                const SizedBox(height: 12),
                _sectionTitle(context, '擷取資訊'),
                _fieldRow(
                  '擷取時間',
                  _formatDateTime(item.fetchedAt, includeUnknown: false),
                ),
                _fieldRow(
                  'Selector profile',
                  item.selectorProfileVersion.toString(),
                ),
                if (item.lineItemsTruncated) ...[
                  _fieldRow(
                    '明細提示',
                    officialInvoiceDetailFailureLabel(
                      item.warningCode ?? 'DETAIL_ITEM_LIST_TRUNCATED_TO_100',
                    ),
                  ),
                  _fieldRow(
                    '未列入項目',
                    item.omittedItemCount.toString(),
                  ),
                ],
                if (!item.success) ...[
                  _fieldRow(
                    item.canUseUserConfirmedEstimatedTax ? '覆核狀態' : '失敗原因',
                    item.canUseUserConfirmedEstimatedTax
                        ? '官方總額已確認；請於下一步確認推算稅額'
                        : officialInvoiceDetailResidualReasonLabel(
                            item.errorCode ?? 'DETAIL_UNKNOWN_FAILURE',
                          ),
                  ),
                  _fieldRow('偵測到明細視窗', item.dialogDetected ? '是' : '否'),
                  _fieldRow('偵測到摘要表格', item.summaryTableDetected ? '是' : '否'),
                  _fieldRow('偵測到品項表格', item.itemTableDetected ? '是' : '否'),
                  _fieldRow('切換前品項列數', item.initialItemRowCount.toString()),
                  _fieldRow(
                    '目標可見品項列數',
                    item.requiredVisibleItemCount.toString(),
                  ),
                  _fieldRow('最多偵測品項列數', item.detectedItemRowCount.toString()),
                  _fieldRow(
                    '找到每頁筆數控制項',
                    item.pageSizeControlDetected ? '是' : '否',
                  ),
                  _fieldRow(
                    '找到 100 筆選項',
                    item.pageSize100OptionDetected ? '是' : '否',
                  ),
                  _fieldRow(
                    '控制項確認為 100 筆',
                    item.pageSize100SelectionObserved ? '是' : '否',
                  ),
                  _fieldRow(
                    '找到表格更新按鈕',
                    item.pageSizeApplyControlDetected ? '是' : '否',
                  ),
                  _fieldRow(
                    '已觸發表格更新按鈕',
                    item.pageSizeApplyTriggered ? '是' : '否',
                  ),
                  _fieldRow(
                    '曾偵測載入遮罩',
                    item.loadingMaskObserved ? '是' : '否',
                  ),
                  if (item.errorCode ==
                      'DETAIL_ITEM_PAGE_SIZE_APPLY_NOT_TRIGGERED')
                    _fieldRow(
                      '建議處理',
                      '每頁筆數已顯示 100，但官方頁面仍需按下拉選單右側的執行按鈕。新版會主動尋找並點擊該按鈕；若仍失敗，請保留此診斷畫面。',
                    )
                  else if (item.errorCode ==
                      'DETAIL_ITEM_TABLE_RELOAD_TIMEOUT')
                    _fieldRow(
                      '建議處理',
                      item.pageSizeApplyTriggered
                          ? '已選擇 100 筆並觸發右側更新按鈕，但表格仍未更新。請保持官方頁面在前景，確認網路後使用「只重試技術性失敗」。'
                          : '官方控制項未完成更新。可先在官方明細手動選擇 100 筆並按右側執行按鈕，再使用「只重試技術性失敗」。',
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItem(
    OfficialInvoiceDetailLineItem item,
    String? currencyCode,
    String invoiceNumber,
    int index,
  ) {
    return Card(
      key: Key('official_detail_review_item_${invoiceNumber}_$index'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${item.name}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('數量：${_formatNumber(item.quantity)}'),
                Text('單價：${_formatAmount(item.unitPrice, currencyCode)}'),
                Text('金額：${_formatAmount(item.amount, currencyCode)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _fieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _checkRow(String label, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('$label：${passed ? '通過' : '未通過'}')),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value, {bool includeUnknown = true}) {
    if (value == null) return includeUnknown ? '未提供' : '';
    final normalized = value.isUtc ? value.toLocal() : value;
    String pad(int part) => part.toString().padLeft(2, '0');
    return '${normalized.year}-${pad(normalized.month)}-${pad(normalized.day)} '
        '${pad(normalized.hour)}:${pad(normalized.minute)}:${pad(normalized.second)}';
  }

  String _formatAmount(double? value, String? currencyCode) {
    if (value == null) return '未提供';
    final prefix = currencyCode == null || currencyCode.isEmpty
        ? ''
        : '$currencyCode ';
    return '$prefix${_formatNumber(value)}';
  }

  String _formatNumber(double? value) {
    if (value == null) return '未提供';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
