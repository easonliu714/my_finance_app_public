import 'package:flutter/material.dart';

import 'private_cloud_invoice_conflict_review_service.dart';

class PrivateCloudInvoiceConflictReviewPage extends StatefulWidget {
  PrivateCloudInvoiceConflictReviewPage({
    super.key,
    required this.conflictTransactionByDraftId,
    PrivateCloudInvoiceConflictReviewPort? service,
  }) : service = service ?? PrivateCloudInvoiceConflictReviewService();

  static const Key confirmationKey = Key(
    'private_invoice_conflict_confirmation',
  );
  static const Key resolveKey = Key('private_invoice_conflict_resolve');
  static const Key resultKey = Key('private_invoice_conflict_result');

  static Key actionKey(String draftId) =>
      ValueKey<String>('private_invoice_conflict_action_$draftId');

  final Map<String, String> conflictTransactionByDraftId;
  final PrivateCloudInvoiceConflictReviewPort service;

  @override
  State<PrivateCloudInvoiceConflictReviewPage> createState() => _State();
}

class _State extends State<PrivateCloudInvoiceConflictReviewPage> {
  List<PrivateCloudInvoiceConflictReviewItem> items =
      const <PrivateCloudInvoiceConflictReviewItem>[];
  final Map<String, PrivateCloudInvoiceConflictResolutionAction>
      actionByDraftId = <String, PrivateCloudInvoiceConflictResolutionAction>{};

  bool loading = true;
  bool resolving = false;
  bool confirmed = false;
  String? error;
  PrivateCloudInvoiceConflictResolutionSummary? summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get allActionsSelected =>
      items.isNotEmpty &&
      items.every((item) => actionByDraftId.containsKey(item.draft.id));

  bool get canResolve =>
      !loading && !resolving && confirmed && allActionsSelected;

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.service.loadReviewItems(
        widget.conflictTransactionByDraftId,
      );
      if (!mounted) return;
      setState(() {
        items = loaded;
        actionByDraftId.removeWhere(
          (draftId, _) => !loaded.any((item) => item.draft.id == draftId),
        );
        confirmed = false;
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error = '衝突資料載入失敗：$exception');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resolve() async {
    if (!canResolve) return;
    setState(() {
      resolving = true;
      error = null;
      summary = null;
    });
    try {
      final decisions = items
          .map(
            (item) => PrivateCloudInvoiceConflictResolutionDecision(
              draftId: item.draft.id,
              transactionId: item.existingTransaction.id,
              action: actionByDraftId[item.draft.id]!,
            ),
          )
          .toList(growable: false);
      final result = await widget.service.resolveMany(
        decisions: decisions,
        finalConfirmation: confirmed,
      );
      if (!mounted) return;
      setState(() {
        summary = result;
        confirmed = false;
      });
      await _load();
    } catch (exception) {
      if (mounted) {
        setState(() => error = '套用衝突處理決策失敗：$exception');
      }
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('交易衝突比對與更新')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '逐筆人工決策',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '官方明細與既有正式交易會並列顯示，系統不會自動覆蓋或自動建立第二筆交易。'
                      '只有明確選擇「兩筆皆保留並另建新交易」並完成下方第二次確認，才會建立新交易；既有交易保持不變。'
                      '「更新官方欄位」只會更新金額、時間、商家與幣別，帳戶、分類、成員、標籤仍保留。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('目前沒有尚待處理的交易衝突。'),
                ),
              )
            else
              for (final item in items) ...[
                _conflictCard(item),
                const SizedBox(height: 10),
              ],
            if (items.isNotEmpty) ...[
              CheckboxListTile(
                key: PrivateCloudInvoiceConflictReviewPage.confirmationKey,
                value: confirmed,
                onChanged: resolving || !allActionsSelected
                    ? null
                    : (value) => setState(() => confirmed = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('我確認套用 ${items.length} 筆衝突處理決策'),
                subtitle: const Text(
                  '每筆決策都會留下 operation 與 audit；掛載、更新或另建交易時另保留 promotion，更新既有交易時再保存 before image。',
                ),
              ),
              FilledButton.icon(
                key: PrivateCloudInvoiceConflictReviewPage.resolveKey,
                onPressed: canResolve ? _resolve : null,
                icon: const Icon(Icons.rule_folder_outlined),
                label: Text(resolving ? '套用中' : '套用衝突處理決策'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!),
                ),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 12),
              Card(
                key: PrivateCloudInvoiceConflictReviewPage.resultKey,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '衝突處理結果\n'
                    '已套用：${summary!.committedCount}\n'
                    '冪等 replay：${summary!.replayCount}\n'
                    '拒絕／失敗：${summary!.rejectedCount}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conflictCard(PrivateCloudInvoiceConflictReviewItem item) {
    final draft = item.draft;
    final existing = item.existingTransaction;
    final selectedAction = actionByDraftId[draft.id];

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              draft.invoiceNumber,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _comparisonSection(
              title: '官方明細',
              rows: <String>[
                '時間：${_dateTime(draft.invoiceDate)}',
                '商家：${draft.sellerName.isEmpty ? '未提供' : draft.sellerName}',
                '金額：${_money(draft.amount, draft.currencyCode)}',
                '帳戶：${draft.accountName}',
                '品項：${draft.lineItems.length} 項',
              ],
            ),
            const Divider(height: 24),
            _comparisonSection(
              title: '既有正式交易',
              rows: <String>[
                '時間：${_dateTime(existing.occurredAt)}',
                '商家：${existing.merchantName}',
                '金額：${_money(existing.amount, existing.currency.code)}',
                '帳戶：${existing.accountName}',
                '分類／成員／標籤：${existing.category}／${existing.memberName}／${existing.tagName}',
                '發票關聯：${item.existingHasInvoiceMetadata ? '已有' : '尚無'}',
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: item.differenceLabels
                  .map((label) => Chip(label: Text(label)))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<
                PrivateCloudInvoiceConflictResolutionAction>(
              key: PrivateCloudInvoiceConflictReviewPage.actionKey(draft.id),
              initialValue: selectedAction,
              decoration: const InputDecoration(labelText: '處理方式'),
              items: PrivateCloudInvoiceConflictResolutionAction.values
                  .map(
                    (action) => DropdownMenuItem(
                      value: action,
                      child: Text(action.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: resolving
                  ? null
                  : (action) {
                      if (action == null) return;
                      setState(() {
                        actionByDraftId[draft.id] = action;
                        confirmed = false;
                        summary = null;
                      });
                    },
            ),
            if (selectedAction != null) ...[
              const SizedBox(height: 8),
              Text(
                selectedAction.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _comparisonSection({
    required String title,
    required List<String> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final row in rows) Text(row),
      ],
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
