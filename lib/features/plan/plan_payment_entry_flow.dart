import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../account/account_providers.dart';
import '../account/account_record.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'credit_card_installment_providers.dart';
import 'credit_card_installment_repository.dart';
import 'credit_card_payment_flow.dart';
import 'credit_card_statement_service.dart';
import 'loan_repayment_flow.dart';
import 'plan_due_summary_service.dart';

Future<void> openPlanPaymentEntryFlow(BuildContext context, WidgetRef ref) async {
  final data = await _loadRepaymentEntryData(ref);
  if (!context.mounted) return;
  final accounts = data.accounts;
  final transactions = data.transactions;
  final creditCards = accounts.where((account) => account.type == AccountType.creditCard).toList();
  final loans = accounts.where((account) => account.type == AccountType.loan).toList();
  final installmentSnapshots = await _loadInstallmentSnapshots(ref.read(creditCardInstallmentRepositoryProvider), creditCards);
  if (!context.mounted) return;
  final dueSummary = buildPlanDueSummary(accounts: accounts, transactions: transactions, installmentPlans: installmentSnapshots);
  final installmentDueCount = installmentSnapshots.where((snapshot) => snapshot.nextDueItem != null).length;
  final installmentDueTwd = dueSummary.creditCard.installmentDueTwd;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text('選擇繳款 / 還款類型', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close)),
          ]),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.credit_card_outlined)),
            title: const Text('信用卡繳款'),
            subtitle: Text(dueSummary.creditCard.cardCount == 0 ? '尚未建立信用卡帳戶' : '${dueSummary.creditCard.cardCount} 張・應繳 ${_money(dueSummary.creditCard.totalDueTwd)} TWD・最低 ${_money(dueSummary.creditCard.minimumDueTwd)} TWD'),
            trailing: const Icon(Icons.chevron_right),
            enabled: dueSummary.creditCard.cardCount > 0,
            onTap: dueSummary.creditCard.cardCount == 0
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    _openCreditCardPaymentFlowFromPlan(context, ref, accounts: accounts, summary: dueSummary.creditCard, transactions: transactions);
                  },
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.splitscreen_outlined)),
            title: const Text('信用卡分期繳款'),
            subtitle: Text(installmentDueCount == 0 ? '尚無待繳分期期別' : '$installmentDueCount 筆待繳・下一期合計 ${_money(installmentDueTwd)} TWD'),
            trailing: const Icon(Icons.chevron_right),
            enabled: installmentDueCount > 0,
            onTap: installmentDueCount == 0
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    _showInstallmentPaymentFlow(context, ref, accounts: accounts, installmentSnapshots: installmentSnapshots);
                  },
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.account_balance_outlined)),
            title: const Text('貸款還款'),
            subtitle: Text(dueSummary.loan.loanCount == 0 ? '尚未建立借貸帳戶' : '${dueSummary.loan.loanCount} 筆・應繳 ${_money(dueSummary.loan.totalDueTwd)} TWD（本金 ${_money(dueSummary.loan.principalDueTwd)} + 利息 ${_money(dueSummary.loan.interestDueTwd)}）'),
            trailing: const Icon(Icons.chevron_right),
            enabled: dueSummary.loan.loanCount > 0,
            onTap: dueSummary.loan.loanCount == 0
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    showLoanRepaymentFlow(context: context, ref: ref, loans: loans, accounts: accounts, transactions: transactions);
                  },
          ),
        ]),
      ),
    ),
  );
}

Future<_RepaymentEntryData> _loadRepaymentEntryData(WidgetRef ref) async {
  var accounts = ref.read(accountListProvider).valueOrNull;
  var ledger = ref.read(transactionLedgerProvider).valueOrNull;

  final loadTasks = <Future<void>>[];
  if (accounts == null) {
    loadTasks.add(ref.read(accountListProvider.notifier).load());
  }
  if (ledger == null) {
    loadTasks.add(ref.read(transactionLedgerProvider.notifier).load());
  }
  if (loadTasks.isNotEmpty) await Future.wait(loadTasks);

  accounts = ref.read(accountListProvider).valueOrNull ?? const <AccountRecord>[];
  ledger = ref.read(transactionLedgerProvider).valueOrNull;
  return _RepaymentEntryData(
    accounts: accounts.where((account) => !account.isArchived).toList(),
    transactions: ledger?.records ?? const <TransactionRecord>[],
  );
}

class _RepaymentEntryData {
  const _RepaymentEntryData({required this.accounts, required this.transactions});

  final List<AccountRecord> accounts;
  final List<TransactionRecord> transactions;
}

void _openCreditCardPaymentFlowFromPlan(BuildContext context, WidgetRef ref, {required List<AccountRecord> accounts, required CreditCardDueSummary summary, required List<TransactionRecord> transactions}) {
  final creditCards = summary.accounts.map((row) => row.card).toList();
  if (creditCards.isEmpty) return;
  final initialRow = summary.accounts.where((row) => row.totalDue > 0).isEmpty ? summary.accounts.first : summary.accounts.where((row) => row.totalDue > 0).first;
  showCreditCardPaymentFlow(
    context: context,
    ref: ref,
    creditCards: creditCards,
    accounts: accounts,
    initialCard: initialRow.card,
    initialEstimate: _paymentEstimateFromDueRow(initialRow, transactions),
  );
}

CreditCardStatementEstimate _paymentEstimateFromDueRow(CreditCardDueAccountSummary row, List<TransactionRecord> transactions) {
  final base = buildCreditCardStatementEstimate(row.card, transactions);
  return CreditCardStatementEstimate(
    card: row.card,
    periodStart: base.periodStart,
    periodEnd: base.periodEnd,
    dueDate: base.dueDate,
    purchaseTotal: row.card.currency.roundAmount(row.generalPurchaseDue + row.installmentDue),
    paymentTotal: base.paymentTotal,
    estimatedDue: row.totalDue,
    outstandingTotal: row.totalDue,
    totalPurchaseCount: base.totalPurchaseCount,
    totalPaymentCount: base.totalPaymentCount,
    isPaid: row.totalDue <= 0,
    purchaseCount: base.purchaseCount,
    paymentCount: base.paymentCount,
  );
}

Future<void> _showInstallmentPaymentFlow(BuildContext context, WidgetRef ref, {required List<AccountRecord> accounts, required List<InstallmentPlanScheduleSnapshot> installmentSnapshots}) async {
  final payable = installmentSnapshots.where((snapshot) => snapshot.nextDueItem != null).toList();
  if (payable.isEmpty) return;
  final paymentAccounts = accounts.where((account) => !account.isArchived && account.type != AccountType.creditCard && account.type != AccountType.loan).toList();
  var selectedSnapshot = payable.first;
  var selectedPaymentAccount = paymentAccounts.isEmpty ? null : paymentAccounts.first;
  var paymentDate = DateTime.now();
  final amountController = TextEditingController(text: _amountInputText(selectedSnapshot.nextDueItem?.totalPayment ?? 0));
  try {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final nextDue = selectedSnapshot.nextDueItem;
          final amount = selectedSnapshot.plan.currency.roundAmount(double.tryParse(amountController.text.trim()) ?? 0);
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('確認信用卡分期繳款', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('付款成功後會建立付款交易，並把該期別標記為 paid 且綁定 generatedTransactionId，避免同一期重複繳款。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                DropdownButtonFormField<InstallmentPlanScheduleSnapshot>(
                  initialValue: selectedSnapshot,
                  decoration: const InputDecoration(labelText: '信用卡分期計畫'),
                  items: payable.map((snapshot) {
                    final item = snapshot.nextDueItem;
                    final title = item == null ? snapshot.plan.cardNameSnapshot : '${snapshot.plan.cardNameSnapshot} 第 ${item.periodNumber}/${snapshot.plan.termCount} 期・${_money(item.totalPayment)} ${snapshot.plan.currency.code}';
                    return DropdownMenuItem(value: snapshot, child: Text(title, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (value) => setModalState(() {
                    selectedSnapshot = value ?? selectedSnapshot;
                    amountController.text = _amountInputText(selectedSnapshot.nextDueItem?.totalPayment ?? 0);
                  }),
                ),
                if (nextDue != null) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(label: Text('本金：${_money(nextDue.principal)} ${selectedSnapshot.plan.currency.code}')),
                    Chip(label: Text('費用：${_money(nextDue.fee)} ${selectedSnapshot.plan.currency.code}')),
                    Chip(label: Text('應繳：${_money(nextDue.totalPayment)} ${selectedSnapshot.plan.currency.code}')),
                  ]),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '繳款金額（${selectedSnapshot.plan.currency.code}）'),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountRecord>(
                  initialValue: selectedPaymentAccount,
                  decoration: const InputDecoration(labelText: '付款來源帳戶'),
                  items: paymentAccounts.map((account) => DropdownMenuItem(value: account, child: Text(account.displayName))).toList(),
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
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: nextDue == null || selectedPaymentAccount == null || amount <= 0 ? null : () => Navigator.of(context).pop(true), child: const Text('確認繳款'))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    final nextDue = selectedSnapshot.nextDueItem;
    final paymentAccount = selectedPaymentAccount;
    if (confirmed != true || nextDue == null || paymentAccount == null || !context.mounted) return;
    final amount = selectedSnapshot.plan.currency.roundAmount(double.tryParse(amountController.text.trim()) ?? nextDue.totalPayment);
    final generatedTransactionId = const Uuid().v4();
    await ref.read(transactionLedgerProvider.notifier).add(TransactionRecord(
      id: generatedTransactionId,
      type: TransactionType.expense,
      amount: amount,
      category: '信用卡分期付款',
      occurredAt: paymentDate,
      accountName: paymentAccount.displayName,
      memberName: '自己',
      merchantName: selectedSnapshot.plan.cardNameSnapshot,
      tagName: '信用卡分期',
      note: '信用卡分期繳款：${selectedSnapshot.plan.cardNameSnapshot} 第 ${nextDue.periodNumber}/${selectedSnapshot.plan.termCount} 期；plan=${selectedSnapshot.plan.id}; schedule=${nextDue.id}',
      currency: selectedSnapshot.plan.currency,
      exchangeRateToBase: selectedSnapshot.plan.currency.defaultRateToTwd,
    ));
    await ref.read(creditCardInstallmentRepositoryProvider).markScheduleItemPaid(
          planId: selectedSnapshot.plan.id,
          scheduleItemId: nextDue.id,
          generatedTransactionId: generatedTransactionId,
        );
    await ref.read(transactionLedgerProvider.notifier).load();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已建立信用卡分期繳款交易，並更新分期期別狀態'), duration: Duration(milliseconds: 900), behavior: SnackBarBehavior.floating));
  } on InstallmentRepositoryFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分期繳款狀態更新失敗：${error.message}'), behavior: SnackBarBehavior.floating));
  } finally {
    amountController.dispose();
  }
}

Future<List<InstallmentPlanScheduleSnapshot>> _loadInstallmentSnapshots(CreditCardInstallmentRepository repository, List<AccountRecord> creditCards) async {
  final result = <InstallmentPlanScheduleSnapshot>[];
  for (final card in creditCards) {
    final plans = await repository.loadPlansByCardId(card.id, status: InstallmentPlanStatus.active);
    for (final plan in plans) {
      result.add(InstallmentPlanScheduleSnapshot(plan: plan, scheduleItems: await repository.loadScheduleItems(plan.id)));
    }
  }
  return result;
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
String _amountInputText(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
