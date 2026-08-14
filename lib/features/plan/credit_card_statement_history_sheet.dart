import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../account/account_record.dart';
import 'credit_card_statement_event.dart';

class CreditCardStatementHistoryAction {
  const CreditCardStatementHistoryAction._({required this.type, this.event});

  final CreditCardStatementHistoryActionType type;
  final CreditCardStatementEvent? event;

  factory CreditCardStatementHistoryAction.correct(CreditCardStatementEvent event) => CreditCardStatementHistoryAction._(type: CreditCardStatementHistoryActionType.correct, event: event);
  factory CreditCardStatementHistoryAction.delete(CreditCardStatementEvent event) => CreditCardStatementHistoryAction._(type: CreditCardStatementHistoryActionType.delete, event: event);
}

enum CreditCardStatementHistoryActionType { correct, delete }

Future<CreditCardStatementHistoryAction?> showCreditCardStatementHistorySheet({
  required BuildContext context,
  required String cardName,
  required CurrencyCode currency,
  required List<CreditCardStatementEvent> events,
}) async {
  final sorted = [...events]..sort((a, b) {
      final byPeriod = b.periodEnd.compareTo(a.periodEnd);
      if (byPeriod != 0) return byPeriod;
      return b.updatedAt.compareTo(a.updatedAt);
    });

  return showModalBottomSheet<CreditCardStatementHistoryAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Text('$cardName 帳單快照歷史', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('此列表僅顯示帳單快照，不代表交易流水。校正或刪除快照不會改變帳戶餘額。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('尚未保存帳單快照。')))
            else
              for (final event in sorted) _StatementHistoryTile(event: event, currency: currency),
          ],
        ),
      ),
    ),
  );
}

class _StatementHistoryTile extends StatelessWidget {
  const _StatementHistoryTile({required this.event, required this.currency});
  final CreditCardStatementEvent event;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    final statusLabel = event.isFullyPaid ? '已繳清' : event.isBelowMinimum ? '低於最低應繳' : '未繳清';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${DateFormat('yyyy/MM/dd').format(event.statementDate)} 帳單', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            Chip(label: Text(statusLabel)),
          ]),
          const SizedBox(height: 4),
          Text('到期日 ${DateFormat('yyyy/MM/dd').format(event.dueDate)}｜更新 ${DateFormat('MM/dd HH:mm').format(event.updatedAt)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _MiniChip(label: '總應繳', value: '${_money(event.totalBalance)} ${currency.code}'),
            _MiniChip(label: '最低應繳', value: '${_money(event.minimumPayment)} ${currency.code}'),
            _MiniChip(label: '已繳', value: '${_money(event.paidAmount)} ${currency.code}'),
            _MiniChip(label: '未繳', value: '${_money(event.unpaidBalance)} ${currency.code}'),
            _MiniChip(label: '利息', value: '${_money(event.estimatedRevolvingInterest)} ${currency.code}'),
            _MiniChip(label: '違約/費用', value: '${_money(event.estimatedLateFee)} ${currency.code}'),
          ]),
          if (event.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(event.note, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.of(context).pop(CreditCardStatementHistoryAction.delete(event)), icon: const Icon(Icons.delete_outline), label: const Text('刪除'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: () => Navigator.of(context).pop(CreditCardStatementHistoryAction.correct(event)), icon: const Icon(Icons.edit_outlined), label: const Text('校正'))),
          ]),
        ]),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label：$value'));
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
