import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../transaction/debit_card_settlement_confirmation.dart';
import '../transaction/debit_card_settlement_presentation.dart';
import '../transaction/transaction_providers.dart';
import 'account_providers.dart';
import 'account_record.dart';
import 'debit_card_available_balance_providers.dart';
import 'debit_card_settlement_providers.dart';

class DebitCardSettlementPanel extends StatelessWidget {
  const DebitCardSettlementPanel({
    super.key,
    required this.account,
    required this.value,
    this.embedded = false,
  });

  final AccountRecord account;
  final AsyncValue<List<DebitCardSettlementPresentation>> value;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = _SettlementPanelContent(
      account: account,
      value: value,
    );
    if (embedded) return content;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }
}

class _SettlementPanelContent extends StatelessWidget {
  const _SettlementPanelContent({
    required this.account,
    required this.value,
  });

  final AccountRecord account;
  final AsyncValue<List<DebitCardSettlementPresentation>> value;

  @override
  Widget build(BuildContext context) {
    final title = account.type == AccountType.bank
        ? '簽帳金融卡待扣款'
        : '預計扣款';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '此狀態為 App 依授權紀錄推算，並非銀行回傳結果。',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.blueGrey),
        ),
        const SizedBox(height: 12),
        value.when(
          loading: () => const _SettlementLoadingState(),
          error: (error, stackTrace) => _SettlementErrorState(error: error),
          data: (items) => items.isEmpty
              ? const _SettlementEmptyState()
              : Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      _SettlementRow(
                        item: items[index],
                        account: account,
                      ),
                      if (index != items.length - 1)
                        const Divider(height: 24),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SettlementLoadingState extends StatelessWidget {
  const _SettlementLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('讀取預計扣款資料中…'),
      ],
    );
  }
}

class _SettlementEmptyState extends StatelessWidget {
  const _SettlementEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Text('目前沒有尚待確認的簽帳金融卡扣款。');
  }
}

class _SettlementErrorState extends StatelessWidget {
  const _SettlementErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '待扣款資料關聯不完整，已停止顯示：$error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _SettlementRow extends ConsumerStatefulWidget {
  const _SettlementRow({
    required this.item,
    required this.account,
  });

  final DebitCardSettlementPresentation item;
  final AccountRecord account;

  @override
  ConsumerState<_SettlementRow> createState() => _SettlementRowState();
}

class _SettlementRowState extends ConsumerState<_SettlementRow> {
  var _submitting = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final expectedDate = const DebitCardSettlementPresentationClock()
        .taiwanDate(item.settlement.expectedSettlementDate);
    final contextLabel = widget.account.type == AccountType.bank
        ? '簽帳卡：${item.debitCardAccount.displayName}'
        : '扣款帳戶：${item.linkedBankAccount.displayName}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.sourceTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            _StatusChip(status: item.status, label: item.statusLabel),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${_money(item.settlement.amount, item.settlement.currency)}・'
          '預計扣款日 ${DateFormat('yyyy/MM/dd').format(expectedDate)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          contextLabel,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.blueGrey),
        ),
        if (item.status == DebitCardSettlementPresentationStatus.overdue) ...[
          const SizedBox(height: 4),
          Text(
            '已逾預計扣款日，尚待確認；App 不會自動標記完成。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _submitting ? null : _confirmSettlement,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(_submitting ? '確認中…' : '確認已扣款'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSettlement() async {
    final item = widget.item;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認此筆已完成扣款'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.sourceTitle),
            const SizedBox(height: 6),
            Text(_money(item.settlement.amount, item.settlement.currency)),
            const SizedBox(height: 6),
            Text('簽帳卡：${item.debitCardAccount.displayName}'),
            Text('綁定銀行：${item.linkedBankAccount.displayName}'),
            const SizedBox(height: 12),
            const Text(
              '確認後將更新 App 內綁定銀行帳戶帳務，並解除此筆待扣款保留額。',
            ),
            const SizedBox(height: 8),
            Text(
              '此操作不會向銀行查詢，也不代表銀行即時回傳結果。',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認並更新帳務'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final service = ref.read(debitCardSettlementConfirmationServiceProvider);
      final settlementId = item.settlement.id;
      await service.confirm(
        DebitCardSettlementConfirmationRequest(
          requestId: 'debit-settlement-confirm:$settlementId',
          settlementId: settlementId,
          transferTransactionId: 'debit-settlement-transfer:$settlementId',
          confirmedAt: DateTime.now().toUtc(),
        ),
      );
      _refreshAfterCommit(item);
      try {
        await ref.read(
          debitCardSettlementReminderReconciliationProvider.future,
        );
      } catch (_) {
        // Financial commit is authoritative; notification retry remains safe.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('扣款確認完成，App 內銀行帳務已更新。')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is DebitCardSettlementConfirmationException
          ? error.userMessage
          : '扣款確認失敗，未變更任何帳務：$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _refreshAfterCommit(DebitCardSettlementPresentation item) {
    ref.invalidate(transactionLedgerProvider);
    ref.invalidate(accountListProvider);
    ref.invalidate(
      accountDebitCardSettlementPresentationProvider(widget.account),
    );
    ref.invalidate(
      accountAvailableBalancePresentationProvider(widget.account),
    );
    ref.invalidate(
      accountDebitCardSettlementPresentationProvider(item.debitCardAccount),
    );
    ref.invalidate(
      accountAvailableBalancePresentationProvider(item.debitCardAccount),
    );
    ref.invalidate(
      accountDebitCardSettlementPresentationProvider(item.linkedBankAccount),
    );
    ref.invalidate(
      accountAvailableBalancePresentationProvider(item.linkedBankAccount),
    );
    ref.invalidate(debitCardSettlementReminderReconciliationProvider);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.label});

  final DebitCardSettlementPresentationStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      DebitCardSettlementPresentationStatus.upcoming =>
        (scheme.primaryContainer, scheme.onPrimaryContainer),
      DebitCardSettlementPresentationStatus.due =>
        (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      DebitCardSettlementPresentationStatus.overdue =>
        (scheme.errorContainer, scheme.onErrorContainer),
      DebitCardSettlementPresentationStatus.inactive =>
        (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _money(double value, CurrencyCode currency) {
  final pattern = currency.decimalDigits == 0
      ? '#,##0'
      : '#,##0.${List<String>.filled(currency.decimalDigits, '0').join()}';
  return '${NumberFormat(pattern).format(value)} ${currency.code}';
}
