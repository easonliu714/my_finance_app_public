import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../account/account_providers.dart';
import '../account/account_record.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'credit_card_statement_service.dart';

Future<bool> showCreditCardPaymentFlow({
  required BuildContext context,
  required WidgetRef ref,
  required List<AccountRecord> creditCards,
  required List<AccountRecord> accounts,
  AccountRecord? sourceAccount,
  AccountRecord? initialCard,
  CreditCardStatementEstimate? initialEstimate,
}) async {
  if (creditCards.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未建立信用卡帳戶')));
    return false;
  }
  var selectedCard = initialCard ?? creditCards.first;
  var estimate = initialEstimate;
  var paymentAccounts = _paymentAccountsFor(accounts, selectedCard);
  var selectedPaymentAccount = _defaultPaymentAccount(paymentAccounts, sourceAccount);
  var paymentDate = DateTime.now();
  final amountController = TextEditingController(text: _amountText(estimate?.estimatedDue ?? 0));
  final noteController = TextEditingController(text: _defaultNote(selectedCard, estimate));

  try {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          paymentAccounts = _paymentAccountsFor(accounts, selectedCard);
          selectedPaymentAccount ??= _defaultPaymentAccount(paymentAccounts, sourceAccount);
          final amount = selectedCard.currency.roundAmount(double.tryParse(amountController.text.trim()) ?? 0);
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('確認信用卡繳款', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('此流程會建立一筆帳戶轉帳：還款來源帳戶 → 信用卡帳戶。估算內容僅供參考，實際應繳金額請以銀行帳單為準。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountRecord>(
                    initialValue: selectedCard,
                    decoration: const InputDecoration(labelText: '信用卡帳戶'),
                    items: creditCards.map((card) => DropdownMenuItem(value: card, child: Text(card.displayName))).toList(),
                    onChanged: (value) => setModalState(() {
                      selectedCard = value ?? selectedCard;
                      selectedPaymentAccount = null;
                      estimate = estimate?.card.id == selectedCard.id ? estimate : null;
                      amountController.text = _amountText(estimate?.estimatedDue ?? 0);
                      noteController.text = _defaultNote(selectedCard, estimate);
                    }),
                  ),
                  if (estimate != null) ...[
                    const SizedBox(height: 12),
                    _EstimateBox(estimate: estimate!),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: '繳款金額（${selectedCard.currency.code}）'),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountRecord>(
                    initialValue: selectedPaymentAccount,
                    decoration: const InputDecoration(labelText: '還款來源帳戶'),
                    items: paymentAccounts.map((item) => DropdownMenuItem(value: item, child: Text(item.displayName))).toList(),
                    onChanged: (value) => setModalState(() => selectedPaymentAccount = value),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: paymentDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (picked == null || !context.mounted) return;
                      setModalState(() => paymentDate = DateTime(picked.year, picked.month, picked.day, paymentDate.hour, paymentDate.minute));
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('繳款日期 ${DateFormat('yyyy/MM/dd').format(paymentDate)}'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: noteController, decoration: const InputDecoration(labelText: '備註')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('結帳日：${selectedCard.statementDay} 日')),
                      Chip(label: Text('繳款日：${selectedCard.paymentDueDay} 日')),
                      Chip(label: Text('繳款：${_money(amount)} ${selectedCard.currency.code}')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消'))),
                      const SizedBox(width: 8),
                      Expanded(child: FilledButton(onPressed: amount <= 0 || selectedPaymentAccount == null ? null : () => Navigator.of(context).pop(true), child: const Text('確認繳款'))),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    final paymentAccount = selectedPaymentAccount;
    if (confirmed != true || paymentAccount == null || !context.mounted) return false;
    final amount = selectedCard.currency.roundAmount(double.tryParse(amountController.text.trim()) ?? 0);
    if (amount <= 0) return false;
    await ref.read(transactionLedgerProvider.notifier).add(TransactionRecord(
      id: const Uuid().v4(),
      type: TransactionType.transfer,
      amount: amount,
      category: '信用卡繳款',
      occurredAt: paymentDate,
      accountName: paymentAccount.displayName,
      memberName: '自己',
      merchantName: '',
      tagName: '信用卡',
      note: noteController.text.trim(),
      currency: selectedCard.currency,
      exchangeRateToBase: selectedCard.currency.defaultRateToTwd,
      fromAccountName: paymentAccount.displayName,
      toAccountName: selectedCard.displayName,
    ));
    await ref.read(transactionLedgerProvider.notifier).load();
    await ref.read(accountListProvider.notifier).load();
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已建立信用卡繳款記錄，計劃頁已更新'), duration: Duration(milliseconds: 900), behavior: SnackBarBehavior.floating));
    return true;
  } finally {
    amountController.dispose();
    noteController.dispose();
  }
}

class _EstimateBox extends StatelessWidget {
  const _EstimateBox({required this.estimate});
  final CreditCardStatementEstimate estimate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('本期估算區間：${estimate.periodLabel}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text('估算應繳 ${_money(estimate.estimatedDue)} ${estimate.card.currency.code}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('消費 ${_money(estimate.purchaseTotal)}・已繳 ${_money(estimate.paymentTotal)}・繳款日 ${DateFormat('yyyy/MM/dd').format(estimate.dueDate)}', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

List<AccountRecord> _paymentAccountsFor(List<AccountRecord> accounts, AccountRecord card) {
  return accounts.where((item) => !item.isArchived && item.id != card.id && item.type != AccountType.creditCard && item.type != AccountType.loan).toList();
}

AccountRecord? _defaultPaymentAccount(List<AccountRecord> paymentAccounts, AccountRecord? sourceAccount) {
  if (sourceAccount != null && sourceAccount.type != AccountType.creditCard && sourceAccount.type != AccountType.loan) {
    for (final account in paymentAccounts) {
      if (account.id == sourceAccount.id) return account;
    }
  }
  return paymentAccounts.isNotEmpty ? paymentAccounts.first : null;
}

String _defaultNote(AccountRecord card, CreditCardStatementEstimate? estimate) {
  if (estimate == null) return '${card.displayName} 本期繳款';
  return '${card.displayName} ${estimate.periodLabel} 帳單繳款';
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
String _amountText(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
