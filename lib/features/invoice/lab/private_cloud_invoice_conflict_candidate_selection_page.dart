import 'package:flutter/material.dart';

import 'private_cloud_invoice_conflict_review_page.dart';
import 'private_cloud_invoice_conflict_review_service.dart';

class PrivateCloudInvoiceConflictCandidateSelectionPage extends StatefulWidget {
  PrivateCloudInvoiceConflictCandidateSelectionPage({
    super.key,
    required this.candidateTransactionIdsByDraftId,
    PrivateCloudInvoiceConflictReviewPort? service,
  }) : service = service ?? PrivateCloudInvoiceConflictReviewService();

  static const Key continueKey =
      Key('private_invoice_candidate_selection_continue');

  static Key candidateKey(String draftId, String transactionId) =>
      ValueKey<String>(
        'private_invoice_candidate_${draftId}_$transactionId',
      );

  final Map<String, List<String>> candidateTransactionIdsByDraftId;
  final PrivateCloudInvoiceConflictReviewPort service;

  @override
  State<PrivateCloudInvoiceConflictCandidateSelectionPage> createState() =>
      _State();
}

class _State
    extends State<PrivateCloudInvoiceConflictCandidateSelectionPage> {
  Map<String, List<PrivateCloudInvoiceConflictReviewItem>> candidatesByDraftId =
      const <String, List<PrivateCloudInvoiceConflictReviewItem>>{};
  final Map<String, String> selectedTransactionByDraftId = <String, String>{};

  bool loading = true;
  bool openingReview = false;
  String? error;

  bool get allSelected =>
      candidatesByDraftId.isNotEmpty &&
      candidatesByDraftId.entries.every(
        (entry) =>
            entry.value.isNotEmpty &&
            selectedTransactionByDraftId.containsKey(entry.key),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = <String, List<PrivateCloudInvoiceConflictReviewItem>>{};
      for (final entry in widget.candidateTransactionIdsByDraftId.entries) {
        final items = <PrivateCloudInvoiceConflictReviewItem>[];
        for (final transactionId in entry.value.toSet()) {
          final result = await widget.service.loadReviewItems(
            <String, String>{entry.key: transactionId},
          );
          if (result.isNotEmpty) items.add(result.single);
        }
        items.sort(
          (left, right) => left.existingTransaction.occurredAt.compareTo(
            right.existingTransaction.occurredAt,
          ),
        );
        loaded[entry.key] = List.unmodifiable(items);
      }
      if (!mounted) return;
      setState(() {
        candidatesByDraftId = Map.unmodifiable(loaded);
        selectedTransactionByDraftId.removeWhere(
          (draftId, transactionId) =>
              !loaded.containsKey(draftId) ||
              !loaded[draftId]!.any(
                (item) => item.existingTransaction.id == transactionId,
              ),
        );
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error = '候選交易載入失敗：$exception');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _continue() async {
    if (!allSelected || openingReview) return;
    setState(() => openingReview = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PrivateCloudInvoiceConflictReviewPage(
            conflictTransactionByDraftId:
                Map.unmodifiable(selectedTransactionByDraftId),
            service: widget.service,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => openingReview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('選擇可能重複交易')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '同一張官方發票找到多筆同帳戶、同日期、同金額的正式支出。'
                  '系統不會自動選擇，請逐筆指定要進行衝突比對的既有交易。'
                  '此頁只做選擇，不會修改任何帳務資料。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (candidatesByDraftId.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('目前沒有可供選擇的疑似重複交易。'),
                ),
              )
            else
              for (final entry in candidatesByDraftId.entries) ...[
                _draftCandidateCard(entry.key, entry.value),
                const SizedBox(height: 12),
              ],
            if (error != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: PrivateCloudInvoiceConflictCandidateSelectionPage.continueKey,
              onPressed: allSelected && !openingReview ? _continue : null,
              icon: const Icon(Icons.compare_arrows_outlined),
              label: Text(openingReview ? '開啟中' : '進入交易衝突比對與更新'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draftCandidateCard(
    String draftId,
    List<PrivateCloudInvoiceConflictReviewItem> candidates,
  ) {
    if (candidates.isEmpty) {
      return Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('草稿 $draftId 的候選交易已不存在，請返回重新執行。'),
        ),
      );
    }
    final draft = candidates.first.draft;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '官方發票 ${draft.invoiceNumber}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_dateTime(draft.invoiceDate)}｜${draft.sellerName.isEmpty ? '未提供商家' : draft.sellerName}\n'
              '${_money(draft.amount, draft.currencyCode)}｜帳戶：${draft.accountName}',
            ),
            const Divider(height: 24),
            Text(
              '找到 ${candidates.length} 筆候選正式交易',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            IgnorePointer(
              ignoring: openingReview,
              child: RadioGroup<String>(
                groupValue: selectedTransactionByDraftId[draftId],
                onChanged: (value) {
                  if (openingReview || value == null) return;
                  setState(() {
                    selectedTransactionByDraftId[draftId] = value;
                  });
                },
                child: Column(
                  children: [
                    for (final item in candidates)
                      RadioListTile<String>(
                        key: PrivateCloudInvoiceConflictCandidateSelectionPage
                            .candidateKey(
                          draftId,
                          item.existingTransaction.id,
                        ),
                        value: item.existingTransaction.id,
                        title: Text(
                          '${_dateTime(item.existingTransaction.occurredAt)}｜'
                          '${item.existingTransaction.merchantName}',
                        ),
                        subtitle: Text(
                          '${_money(item.existingTransaction.amount, item.existingTransaction.currency.code)}\n'
                          '分類／成員／標籤：${item.existingTransaction.category}／'
                          '${item.existingTransaction.memberName}／'
                          '${item.existingTransaction.tagName}',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _dateTime(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

String _money(double amount, String? currencyCode) {
  final currency = currencyCode?.trim().toUpperCase();
  final value = amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(2);
  return currency == null || currency.isEmpty ? value : '$currency $value';
}
