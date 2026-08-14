import 'package:flutter/material.dart';

import 'cloud_invoice_candidate.dart';
import 'cloud_invoice_mock_provider.dart';

class CloudInvoiceReviewPage extends StatelessWidget {
  const CloudInvoiceReviewPage({
    super.key,
    required this.candidates,
    this.providerResults = const <CloudInvoiceMockProviderResult>[],
    this.onReviewCandidate,
    this.onConfirmDraft,
    this.onDiscardCandidate,
    this.onManualEntry,
    this.onRetryLater,
  });

  static const routeName = 'cloud-invoice-review';
  static const routePath = '/invoice/cloud/review';
  static const pendingSectionKey = Key('cloud_invoice_pending_section');
  static const duplicateSectionKey = Key('cloud_invoice_duplicate_section');
  static const errorSectionKey = Key('cloud_invoice_error_section');
  static const safetyBannerKey = Key('cloud_invoice_review_safety_banner');
  static const emptyManualEntryKey = Key('cloud_invoice_empty_manual_entry');

  final List<CloudInvoiceCandidate> candidates;
  final List<CloudInvoiceMockProviderResult> providerResults;
  final ValueChanged<CloudInvoiceCandidate>? onReviewCandidate;
  final ValueChanged<CloudInvoiceCandidate>? onConfirmDraft;
  final ValueChanged<CloudInvoiceCandidate>? onDiscardCandidate;
  final VoidCallback? onManualEntry;
  final VoidCallback? onRetryLater;

  @override
  Widget build(BuildContext context) {
    final pending = candidates.where((candidate) => candidate.status == CloudInvoiceCandidateStatus.pending).toList(growable: false);
    final duplicates = candidates.where((candidate) => candidate.status == CloudInvoiceCandidateStatus.duplicate).toList(growable: false);
    final rejected = candidates
        .where(
          (candidate) =>
              candidate.status == CloudInvoiceCandidateStatus.rejected ||
              candidate.status == CloudInvoiceCandidateStatus.blocked ||
              candidate.status == CloudInvoiceCandidateStatus.retryableError,
        )
        .toList(growable: false);
    final providerFailures = providerResults.where((result) => !result.isSuccess).toList(growable: false);
    final isEmptyState = pending.isEmpty && duplicates.isEmpty && rejected.isEmpty && providerFailures.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('雲端發票覆核')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SafetyBanner(pendingCount: pending.length, duplicateCount: duplicates.length, errorCount: rejected.length + providerFailures.length),
          const SizedBox(height: 12),
          _CandidateSection(
            key: pendingSectionKey,
            title: '待確認候選',
            emptyText: '目前沒有待確認候選',
            candidates: pending,
            actionLabel: '確認為本機草稿',
            onPrimaryAction: onConfirmDraft,
            onReviewCandidate: onReviewCandidate,
            onDiscardCandidate: onDiscardCandidate,
          ),
          if (isEmptyState) ...[
            const SizedBox(height: 12),
            _EmptyManualFallback(onManualEntry: onManualEntry),
          ],
          const SizedBox(height: 12),
          _CandidateSection(
            key: duplicateSectionKey,
            title: '疑似重複候選',
            emptyText: '目前沒有疑似重複候選',
            candidates: duplicates,
            actionLabel: '檢視重複處置',
            onPrimaryAction: onReviewCandidate,
            onReviewCandidate: onReviewCandidate,
            onDiscardCandidate: onDiscardCandidate,
          ),
          const SizedBox(height: 12),
          _ErrorSection(
            key: errorSectionKey,
            rejectedCandidates: rejected,
            providerFailures: providerFailures,
            onManualEntry: onManualEntry,
            onRetryLater: onRetryLater,
          ),
        ],
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.pendingCount, required this.duplicateCount, required this.errorCount});

  final int pendingCount;
  final int duplicateCount;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: CloudInvoiceReviewPage.safetyBannerKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('匯入摘要', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('待確認 $pendingCount 筆｜疑似重複 $duplicateCount 筆｜需處理 $errorCount 筆'),
            const SizedBox(height: 8),
            const Text('所有雲端發票候選都必須先覆核；本頁不會自動建立正式交易、商家或帳戶。'),
          ],
        ),
      ),
    );
  }
}

class _EmptyManualFallback extends StatelessWidget {
  const _EmptyManualFallback({this.onManualEntry});

  final VoidCallback? onManualEntry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('沒有可覆核項目', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('目前沒有雲端發票候選；若需要立即記錄，可改用既有手動發票流程。'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: CloudInvoiceReviewPage.emptyManualEntryKey,
              onPressed: onManualEntry,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('改用手動輸入'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateSection extends StatelessWidget {
  const _CandidateSection({
    super.key,
    required this.title,
    required this.emptyText,
    required this.candidates,
    required this.actionLabel,
    required this.onPrimaryAction,
    required this.onReviewCandidate,
    required this.onDiscardCandidate,
  });

  final String title;
  final String emptyText;
  final List<CloudInvoiceCandidate> candidates;
  final String actionLabel;
  final ValueChanged<CloudInvoiceCandidate>? onPrimaryAction;
  final ValueChanged<CloudInvoiceCandidate>? onReviewCandidate;
  final ValueChanged<CloudInvoiceCandidate>? onDiscardCandidate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              Text(emptyText)
            else
              ...candidates.map(
                (candidate) => _CandidateTile(
                  candidate: candidate,
                  actionLabel: actionLabel,
                  onPrimaryAction: onPrimaryAction,
                  onReviewCandidate: onReviewCandidate,
                  onDiscardCandidate: onDiscardCandidate,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.actionLabel,
    required this.onPrimaryAction,
    required this.onReviewCandidate,
    required this.onDiscardCandidate,
  });

  final CloudInvoiceCandidate candidate;
  final String actionLabel;
  final ValueChanged<CloudInvoiceCandidate>? onPrimaryAction;
  final ValueChanged<CloudInvoiceCandidate>? onReviewCandidate;
  final ValueChanged<CloudInvoiceCandidate>? onDiscardCandidate;

  @override
  Widget build(BuildContext context) {
    final buyerIdentifier = candidate.buyerIdentifier?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidate.invoiceNumber.isEmpty ? '未辨識發票號碼' : candidate.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('狀態：${_candidateStatusText(candidate.status)}'),
              Text('來源：${candidate.sourceLabel}'),
              if (candidate.status == CloudInvoiceCandidateStatus.duplicate) Text('重複依據：${candidate.duplicateKey}'),
              Text('發票日期：${_dateText(candidate.invoiceDate)}'),
              if (_hasTime(candidate.invoiceDate)) Text('發票時間：${_timeText(candidate.invoiceDate)}'),
              Text('取得日期：${_dateText(candidate.fetchedAt)}'),
              if (_hasTime(candidate.fetchedAt)) Text('取得時間：${_timeText(candidate.fetchedAt)}'),
              if (candidate.confidence != null) Text('信心值：${_confidenceText(candidate.confidence!)}'),
              Text('${candidate.displaySellerName}｜NT\$ ${candidate.totalAmount.toStringAsFixed(0)}'),
              if (candidate.sellerIdentifier.isNotEmpty) Text('商家代碼：${candidate.sellerIdentifier}'),
              if (buyerIdentifier != null && buyerIdentifier.isNotEmpty) Text('買方代碼：$buyerIdentifier'),
              if (candidate.taxAmount != null) Text('附加金額：NT\$ ${candidate.taxAmount!.toStringAsFixed(0)}'),
              Text('載具：${candidate.safeCarrierDisplay}'),
              if (candidate.hasLineItems) ...[
                const SizedBox(height: 4),
                _LineItemSummary(items: candidate.lineItems),
              ],
              if (candidate.hasWarnings) ...[
                const SizedBox(height: 4),
                Text('需人工確認：${candidate.warnings.map(_warningLabel).join('、')}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: onReviewCandidate == null ? null : () => onReviewCandidate!(candidate), child: const Text('檢視')),
                  FilledButton(onPressed: onPrimaryAction == null ? null : () => onPrimaryAction!(candidate), child: Text(actionLabel)),
                  TextButton(onPressed: onDiscardCandidate == null ? null : () => onDiscardCandidate!(candidate), child: const Text('捨棄')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineItemSummary extends StatelessWidget {
  const _LineItemSummary({required this.items});

  final List<CloudInvoiceLineItem> items;

  @override
  Widget build(BuildContext context) {
    final previewItems = items.take(2).map((item) => '${item.name} NT\$ ${item.amount.toStringAsFixed(0)}').join('、');
    final hintItems = items
        .where((item) => item.hasCategorySuggestion)
        .take(2)
        .map((item) => '${item.name}：${item.categorySuggestion!.trim()}')
        .join('、');
    final remainingCount = items.length - 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('品項：${items.length} 項', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (previewItems.isNotEmpty) Text(previewItems),
        if (remainingCount > 0) Text('另有 $remainingCount 項品項'),
        if (hintItems.isNotEmpty) Text('項目提示：$hintItems'),
      ],
    );
  }
}

class _ErrorSection extends StatelessWidget {
  const _ErrorSection({super.key, required this.rejectedCandidates, required this.providerFailures, this.onManualEntry, this.onRetryLater});

  final List<CloudInvoiceCandidate> rejectedCandidates;
  final List<CloudInvoiceMockProviderResult> providerFailures;
  final VoidCallback? onManualEntry;
  final VoidCallback? onRetryLater;

  @override
  Widget build(BuildContext context) {
    final hasErrors = rejectedCandidates.isNotEmpty || providerFailures.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('錯誤與需重試', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (!hasErrors)
              const Text('目前沒有錯誤項目')
            else ...[
              ...rejectedCandidates.map((candidate) => Text('${candidate.invoiceNumber.isEmpty ? '未辨識候選' : candidate.invoiceNumber}：${_errorStatusText(candidate.errorCategory)}')),
              ...providerFailures.map((result) => Text(_providerFailureText(result))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: onManualEntry, child: const Text('改用手動輸入')),
                  OutlinedButton(onPressed: _hasRetryable(providerFailures, rejectedCandidates) ? onRetryLater : null, child: const Text('稍後再試')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _hasRetryable(List<CloudInvoiceMockProviderResult> results, List<CloudInvoiceCandidate> candidates) {
    return results.any((result) => result.canRetryManually) || candidates.any((candidate) => candidate.isRetryable);
  }
}

String _dateText(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
}

String _timeText(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

bool _hasTime(DateTime value) => value.hour != 0 || value.minute != 0;

String _confidenceText(double confidence) {
  final percent = confidence <= 1 ? confidence * 100 : confidence;
  return '${percent.clamp(0, 100).round()}%';
}

String _candidateStatusText(CloudInvoiceCandidateStatus status) {
  final labels = <CloudInvoiceCandidateStatus, String>{
    CloudInvoiceCandidateStatus.pending: '待確認',
    CloudInvoiceCandidateStatus.duplicate: '疑似重複',
    CloudInvoiceCandidateStatus.rejected: '需處理',
    CloudInvoiceCandidateStatus.retryableError: '可稍後再試',
    CloudInvoiceCandidateStatus.confirmedDraft: '已轉草稿',
    CloudInvoiceCandidateStatus.discarded: '已捨棄',
    CloudInvoiceCandidateStatus.blocked: '暫不可用',
  };
  return labels[status] ?? '需確認';
}

String _warningLabel(CloudInvoiceCandidateWarning warning) {
  switch (warning) {
    case CloudInvoiceCandidateWarning.missingSellerName:
      return '缺少商家名稱';
    case CloudInvoiceCandidateWarning.missingLineItems:
      return '缺少品項明細';
    case CloudInvoiceCandidateWarning.partialPayload:
      return '資料不完整';
    case CloudInvoiceCandidateWarning.lowConfidence:
      return '辨識信心偏低';
  }
}

String _providerFailureText(CloudInvoiceMockProviderResult result) {
  final label = _errorStatusText(result.errorCategory);
  final message = result.message?.trim();
  if (message == null || message.isEmpty) return label;
  return '$label：$message';
}

String _errorStatusText(CloudInvoiceCandidateErrorCategory category) {
  final labels = <CloudInvoiceCandidateErrorCategory, String>{
    CloudInvoiceCandidateErrorCategory.none: '未分類',
    CloudInvoiceCandidateErrorCategory.parseError: '解析失敗',
    CloudInvoiceCandidateErrorCategory.network: '網路異常',
    CloudInvoiceCandidateErrorCategory.rateLimited: '請求過於頻繁',
    CloudInvoiceCandidateErrorCategory.unsupportedCarrier: '不支援來源',
    CloudInvoiceCandidateErrorCategory.policyBlocked: '目前不可使用',
  };
  return labels[category] ?? '需處理';
}
