import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../account/account_record.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';

class LoanPreviewRow {
  const LoanPreviewRow({required this.period, required this.payment, required this.principal, required this.interest, required this.remainingPrincipal});
  final int period;
  final double payment;
  final double principal;
  final double interest;
  final double remainingPrincipal;

  @override
  bool operator ==(Object other) => other is LoanPreviewRow && other.period == period;

  @override
  int get hashCode => period.hashCode;
}

Future<void> showLoanRepaymentFlow({
  required BuildContext context,
  required WidgetRef ref,
  required List<AccountRecord> loans,
  required List<AccountRecord> accounts,
  required List<TransactionRecord> transactions,
  AccountRecord? sourceAccount,
  AccountRecord? initialLoan,
}) async {
  if (loans.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚未建立借貸帳戶')));
    return;
  }
  var selectedLoan = initialLoan ?? loans.first;
  var rows = buildLoanPreviewRows(selectedLoan, maxRows: selectedLoan.loanTermMonths);
  var paidPeriods = paidPeriodsFor(selectedLoan, transactions);
  var selectedRow = nextUnpaidLoanRow(rows, paidPeriods) ?? (rows.isNotEmpty ? rows.first : null);
  var paymentAccounts = _paymentAccountsFor(accounts, selectedLoan);
  var selectedPaymentAccount = _defaultPaymentAccount(paymentAccounts, sourceAccount);
  var paymentDate = DateTime.now();
  final principalController = TextEditingController(text: _amountText(selectedRow?.principal ?? 0));
  final interestController = TextEditingController(text: _amountText(selectedRow?.interest ?? 0));

  void syncAmountControllers(LoanPreviewRow? row) {
    principalController.text = _amountText(row?.principal ?? 0);
    interestController.text = _amountText(row?.interest ?? 0);
  }

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        rows = buildLoanPreviewRows(selectedLoan, maxRows: selectedLoan.loanTermMonths);
        paidPeriods = paidPeriodsFor(selectedLoan, transactions);
        selectedRow ??= nextUnpaidLoanRow(rows, paidPeriods) ?? (rows.isNotEmpty ? rows.first : null);
        paymentAccounts = _paymentAccountsFor(accounts, selectedLoan);
        selectedPaymentAccount ??= _defaultPaymentAccount(paymentAccounts, sourceAccount);
        final row = selectedRow;
        final principal = selectedLoan.currency.roundAmount(double.tryParse(principalController.text.trim()) ?? row?.principal ?? 0);
        final interest = selectedLoan.currency.roundAmount(double.tryParse(interestController.text.trim()) ?? row?.interest ?? 0);
        final totalPayment = selectedLoan.currency.roundAmount(principal + interest);
        final principalDiff = row == null ? 0.0 : selectedLoan.currency.roundAmount(principal - row.principal);
        final interestDiff = row == null ? 0.0 : selectedLoan.currency.roundAmount(interest - row.interest);
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('確認借貸還款', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const _DisclaimerText(),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountRecord>(
                  initialValue: selectedLoan,
                  decoration: const InputDecoration(labelText: '借貸帳戶'),
                  items: loans.map((loan) => DropdownMenuItem(value: loan, child: Text(loan.displayName))).toList(),
                  onChanged: (value) => setModalState(() {
                    selectedLoan = value ?? selectedLoan;
                    selectedRow = null;
                    selectedPaymentAccount = null;
                    rows = buildLoanPreviewRows(selectedLoan, maxRows: selectedLoan.loanTermMonths);
                    paidPeriods = paidPeriodsFor(selectedLoan, transactions);
                    selectedRow = nextUnpaidLoanRow(rows, paidPeriods) ?? (rows.isNotEmpty ? rows.first : null);
                    syncAmountControllers(selectedRow);
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: row?.period,
                  decoration: const InputDecoration(labelText: '還款期數'),
                  items: rows.map((item) => DropdownMenuItem(value: item.period, child: Text('第 ${item.period} 期${paidPeriods.contains(item.period) ? '・已還' : ''}'))).toList(),
                  onChanged: (value) => setModalState(() {
                    selectedRow = rows.where((item) => item.period == value).firstOrNull ?? selectedRow;
                    syncAmountControllers(selectedRow);
                  }),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(label: '本期總額', value: '${_money(totalPayment)} ${selectedLoan.currency.code}'),
                    _SummaryChip(label: '試算本金', value: '${_money(row?.principal ?? 0)} ${selectedLoan.currency.code}'),
                    _SummaryChip(label: '試算利息', value: '${_money(row?.interest ?? 0)} ${selectedLoan.currency.code}'),
                    _SummaryChip(label: '本金差異', value: _signedMoney(principalDiff, selectedLoan.currency)),
                    _SummaryChip(label: '利息差異', value: _signedMoney(interestDiff, selectedLoan.currency)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: principalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: '本金（${selectedLoan.currency.code}）'),
                        onChanged: (_) => setModalState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: interestController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: '利息（${selectedLoan.currency.code}）'),
                        onChanged: (_) => setModalState(() {}),
                      ),
                    ),
                  ],
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
                  label: Text('還款日期 ${DateFormat('yyyy/MM/dd').format(paymentDate)}'),
                ),
                const SizedBox(height: 8),
                Text('可依帳單或合約修改本金與利息；確認後本金與利息會共用同一組還款識別。', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消'))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(onPressed: row == null || selectedPaymentAccount == null || totalPayment <= 0 ? null : () => Navigator.of(context).pop(true), child: const Text('確認還款'))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  final row = selectedRow;
  final paymentAccount = selectedPaymentAccount;
  if (confirmed != true || row == null || paymentAccount == null || !context.mounted) return;
  final principal = selectedLoan.currency.roundAmount(double.tryParse(principalController.text.trim()) ?? row.principal);
  final interest = selectedLoan.currency.roundAmount(double.tryParse(interestController.text.trim()) ?? row.interest);
  await createLoanPaymentRecords(ref, selectedLoan, paymentAccount, row.copyWith(principal: principal, interest: interest), paymentDate);
  if (!context.mounted) return;
  await ref.read(transactionLedgerProvider.notifier).load();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已建立第 ${row.period} 期還款記帳'), duration: const Duration(milliseconds: 900), behavior: SnackBarBehavior.floating));
}

Future<void> createLoanPaymentRecords(WidgetRef ref, AccountRecord loanAccount, AccountRecord paymentAccount, LoanPreviewRow row, DateTime paymentDate) async {
  final controller = ref.read(transactionLedgerProvider.notifier);
  final rate = loanAccount.currency.defaultRateToTwd;
  final repaymentGroupId = const Uuid().v4();
  if (row.principal > 0) {
    await controller.add(TransactionRecord(id: const Uuid().v4(), type: TransactionType.loan, amount: row.principal, category: '還本', occurredAt: paymentDate, accountName: loanAccount.displayName, memberName: '自己', merchantName: '', tagName: '還款', note: '${loanAccount.displayName} 第 ${row.period} 期本金還款，來源：${paymentAccount.displayName}', currency: loanAccount.currency, exchangeRateToBase: rate, repaymentGroupId: repaymentGroupId));
  }
  if (row.interest > 0) {
    await controller.add(TransactionRecord(id: const Uuid().v4(), type: TransactionType.expense, amount: row.interest, category: '利息支出', occurredAt: paymentDate, accountName: paymentAccount.displayName, memberName: '自己', merchantName: loanAccount.displayName, tagName: '還款', note: '${loanAccount.displayName} 第 ${row.period} 期利息', currency: loanAccount.currency, exchangeRateToBase: rate, repaymentGroupId: repaymentGroupId));
  }
}

class LoanPreviewTable extends StatelessWidget {
  const LoanPreviewTable({super.key, required this.rows, required this.currency, this.paidPeriods = const {}});
  final List<LoanPreviewRow> rows;
  final CurrencyCode currency;
  final Set<int> paidPeriods;

  @override
  Widget build(BuildContext context) => Table(
    columnWidths: const {0: FixedColumnWidth(44), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth(), 4: FixedColumnWidth(56)},
    children: [
      _tableRow(['期', '本金', '利息', '餘額', '狀態'], header: true),
      for (final row in rows) _tableRow(['${row.period}', _money(row.principal), _money(row.interest), _money(row.remainingPrincipal), paidPeriods.contains(row.period) ? '已還' : '未還']),
    ],
  );

  TableRow _tableRow(List<String> values, {bool header = false}) => TableRow(children: [for (final value in values) Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2), child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: header ? FontWeight.w800 : FontWeight.w400)))]);
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label：$value'));
}

class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText();
  @override
  Widget build(BuildContext context) => Text('試算內容僅供參考，請依照借貸合約為主還款。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700));
}

List<LoanPreviewRow> buildLoanPreviewRows(AccountRecord account, {required int maxRows}) {
  if (!account.isLoan || account.loanPrincipal <= 0 || account.loanTermMonths <= 0) return const [];
  final rows = <LoanPreviewRow>[];
  var remaining = account.currency.roundAmount(account.loanPrincipal);
  final monthlyRate = account.monthlyInterestRate;
  final limit = account.loanTermMonths < maxRows ? account.loanTermMonths : maxRows;
  for (var period = 1; period <= limit; period++) {
    final interest = account.currency.roundAmount(remaining * monthlyRate);
    double principal;
    double payment;
    switch (account.loanRepaymentMethod) {
      case LoanRepaymentMethod.principalOnly:
        principal = account.currency.roundAmount(account.loanPrincipal / account.loanTermMonths);
        payment = account.currency.roundAmount(principal + interest);
      case LoanRepaymentMethod.interestOnly:
        principal = period == account.loanTermMonths ? remaining : 0;
        payment = account.currency.roundAmount(principal + interest);
      case LoanRepaymentMethod.equalPrincipalAndInterest:
        payment = account.estimatedMonthlyPayment;
        principal = account.currency.roundAmount(payment - interest);
    }
    if (principal > remaining) principal = remaining;
    if (period == account.loanTermMonths) {
      principal = remaining;
      payment = account.currency.roundAmount(principal + interest);
    }
    remaining = account.currency.roundAmount(remaining - principal);
    rows.add(LoanPreviewRow(period: period, payment: payment, principal: principal, interest: interest, remainingPrincipal: remaining));
  }
  return rows;
}

LoanPreviewRow? nextUnpaidLoanRow(List<LoanPreviewRow> rows, Set<int> paidPeriods) {
  for (final row in rows) {
    if (!paidPeriods.contains(row.period)) return row;
  }
  return null;
}

Set<int> paidPeriodsFor(AccountRecord account, List<TransactionRecord> transactions) {
  final paid = <int>{};
  for (final tx in transactions) {
    if (!tx.isLoanRepayment) continue;
    if (tx.type != TransactionType.loan || tx.category != '還本') continue;
    if (tx.accountName != account.displayName) continue;
    final period = periodFromRepaymentNote(tx.note);
    if (period != null) paid.add(period);
  }
  return paid;
}

int? periodFromRepaymentNote(String note) {
  final match = RegExp(r'第\s*(\d+)\s*期').firstMatch(note);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

List<AccountRecord> _paymentAccountsFor(List<AccountRecord> accounts, AccountRecord loanAccount) => accounts.where((item) => !item.isArchived && item.id != loanAccount.id && item.type != AccountType.loan).toList();

AccountRecord? _defaultPaymentAccount(List<AccountRecord> paymentAccounts, AccountRecord? sourceAccount) {
  if (sourceAccount != null) {
    for (final account in paymentAccounts) {
      if (account.id == sourceAccount.id) return account;
    }
  }
  return paymentAccounts.isNotEmpty ? paymentAccounts.first : null;
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
String _amountText(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
String _signedMoney(double value, CurrencyCode currency) => '${value >= 0 ? '+' : ''}${_money(value)} ${currency.code}';

extension on LoanPreviewRow {
  LoanPreviewRow copyWith({double? principal, double? interest}) {
    final nextPrincipal = principal ?? this.principal;
    final nextInterest = interest ?? this.interest;
    return LoanPreviewRow(period: period, payment: nextPrincipal + nextInterest, principal: nextPrincipal, interest: nextInterest, remainingPrincipal: remainingPrincipal);
  }
}
