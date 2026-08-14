import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../account/account_providers.dart';
import '../account/account_record.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import 'credit_card_installment_plan_visibility_card.dart';
import 'credit_card_installment_preview_page.dart';
import 'credit_card_installment_providers.dart';
import 'credit_card_installment_repository.dart';
import 'plan_due_summary_service.dart';
import 'plan_payment_entry_flow.dart';

class RepaymentPlanPage extends ConsumerWidget {
  const RepaymentPlanPage({super.key});

  static const routeName = 'repayment-plan';
  static const routePath = '/plans';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountListProvider);
    final ledgerState = ref.watch(transactionLedgerProvider);
    final transactions = ledgerState.valueOrNull?.records ?? const <TransactionRecord>[];

    return Scaffold(
      appBar: AppBar(title: const Text('計劃')),
      body: accountsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('讀取計劃失敗：$error')),
        data: (accounts) {
          final activeAccounts = accounts.where((account) => !account.isArchived).toList();
          final creditCards = activeAccounts.where((account) => account.type == AccountType.creditCard).toList();
          return FutureBuilder<List<InstallmentPlanScheduleSnapshot>>(
            future: _loadInstallmentSnapshots(ref.read(creditCardInstallmentRepositoryProvider), creditCards),
            builder: (context, snapshot) {
              final installmentSnapshots = snapshot.data ?? const <InstallmentPlanScheduleSnapshot>[];
              final dueSummary = buildPlanDueSummary(accounts: activeAccounts, transactions: transactions, installmentPlans: installmentSnapshots);
              return RefreshIndicator(
                onRefresh: () async {
                  await ref.read(accountListProvider.notifier).load();
                  await ref.read(transactionLedgerProvider.notifier).load();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
                    _PlanSummaryCard(summary: dueSummary),
                    const SizedBox(height: 16),
                    CreditCardInstallmentPlanVisibilityCard(
                      onOpenPreview: () => context.pushNamed(CreditCardInstallmentPreviewPage.routeName),
                    ),
                    const SizedBox(height: 16),
                    _CreditCardDueSummarySection(summary: dueSummary.creditCard),
                    const SizedBox(height: 16),
                    _LoanDueSummarySection(summary: dueSummary.loan),
                    const SizedBox(height: 16),
                    const _PlanSettingsSummarySection(),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan-payment-entry',
        onPressed: () => openPlanPaymentEntryFlow(context, ref),
        icon: const Icon(Icons.payments_outlined),
        label: const Text('繳款/還款'),
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.summary});

  final PlanDueSummary summary;

  @override
  Widget build(BuildContext context) {
    final card = summary.creditCard;
    final loan = summary.loan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('還款提醒總覽', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text('信用卡 ${card.cardCount} 張，應繳金額 ${_money(card.totalDueTwd)} TWD（最低應繳 ${_money(card.minimumDueTwd)} TWD）', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('含分期 ${_money(card.installmentDueTwd)}、一般消費 ${_money(card.generalPurchaseDueTwd)}、循環利息 0、違約金 0；已轉分期來源交易已排除 ${_money(card.excludedInstallmentSourceAmountTwd)}。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Text('貸款 ${loan.loanCount} 筆，應繳金額 ${_money(loan.totalDueTwd)} TWD（含本金 ${_money(loan.principalDueTwd)} + 利息 ${_money(loan.interestDueTwd)}）', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('此頁採區塊式摘要：先看總覽，點開各區塊再看帳戶 / 期別明細。', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _CreditCardDueSummarySection extends StatelessWidget {
  const _CreditCardDueSummarySection({required this.summary});

  final CreditCardDueSummary summary;

  @override
  Widget build(BuildContext context) {
    return _ExpandableSummarySection(
      icon: Icons.credit_card_outlined,
      title: '信用卡消費應繳',
      chips: [_SummaryChip(label: '卡片', value: '${summary.cardCount} 張'), _SummaryChip(label: '應繳', value: '${_money(summary.totalDueTwd)} TWD'), _SummaryChip(label: '最低應繳', value: '${_money(summary.minimumDueTwd)} TWD')],
      emptyMessage: '尚未建立信用卡帳戶。',
      isEmpty: summary.accounts.isEmpty,
      detail: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [DataColumn(label: Text('卡片')), DataColumn(label: Text('總應繳')), DataColumn(label: Text('最低應繳')), DataColumn(label: Text('一般消費')), DataColumn(label: Text('分期')), DataColumn(label: Text('已排除'))], rows: [
            for (final row in summary.accounts)
              DataRow(cells: [
                DataCell(Text(row.card.displayName)),
                DataCell(Text('${_money(row.totalDue)} ${row.card.currency.code}')),
                DataCell(Text('${_money(row.minimumDue)} ${row.card.currency.code}')),
                DataCell(Text('${_money(row.generalPurchaseDue)} ${row.card.currency.code}')),
                DataCell(Text('${_money(row.installmentDue)} ${row.card.currency.code}')),
                DataCell(Text('${_money(row.excludedInstallmentSourceAmount)} ${row.card.currency.code}')),
              ]),
          ]),
        ),
        const SizedBox(height: 8),
        for (final row in summary.accounts) _CreditCardAccountDetailTile(row: row),
      ]),
    );
  }
}

class _CreditCardAccountDetailTile extends StatelessWidget {
  const _CreditCardAccountDetailTile({required this.row});

  final CreditCardDueAccountSummary row;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${row.card.displayName} 明細', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
      subtitle: Text('一般 ${_money(row.generalPurchaseDue)}・分期 ${_money(row.installmentDue)}・最低 ${_money(row.minimumDue)} ${row.card.currency.code}'),
      children: [
        const _SectionCaption('一般信用卡消費（已排除轉分期來源交易）'),
        _TransactionTable(transactions: row.generalTransactions, currency: row.card.currency),
        const SizedBox(height: 8),
        const _SectionCaption('已轉分期來源交易排除額'),
        _TransactionTable(transactions: row.excludedInstallmentSourceTransactions, currency: row.card.currency),
        const SizedBox(height: 8),
        const _SectionCaption('分期期別應繳'),
        _InstallmentScheduleTable(items: row.installmentPlans),
      ],
    );
  }
}

class _LoanDueSummarySection extends StatelessWidget {
  const _LoanDueSummarySection({required this.summary});

  final LoanDueSummary summary;

  @override
  Widget build(BuildContext context) {
    return _ExpandableSummarySection(
      icon: Icons.account_balance_outlined,
      title: '貸款應繳',
      chips: [_SummaryChip(label: '貸款', value: '${summary.loanCount} 筆'), _SummaryChip(label: '應繳', value: '${_money(summary.totalDueTwd)} TWD'), _SummaryChip(label: '本金', value: '${_money(summary.principalDueTwd)} TWD'), _SummaryChip(label: '利息', value: '${_money(summary.interestDueTwd)} TWD')],
      emptyMessage: '尚未建立借貸帳戶。',
      isEmpty: summary.accounts.isEmpty,
      detail: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [DataColumn(label: Text('帳戶')), DataColumn(label: Text('本期本金')), DataColumn(label: Text('本期利息')), DataColumn(label: Text('本期應繳')), DataColumn(label: Text('到期日'))], rows: [
            for (final row in summary.accounts)
              DataRow(cells: [
                DataCell(Text(row.loan.displayName)),
                DataCell(Text('${_money(row.principalDue)} ${row.loan.currency.code}')),
                DataCell(Text('${_money(row.interestDue)} ${row.loan.currency.code}')),
                DataCell(Text('${_money(row.totalDue)} ${row.loan.currency.code}')),
                DataCell(Text('${row.loan.loanPaymentDueDay} 日')),
              ]),
          ]),
        ),
        const SizedBox(height: 8),
        for (final row in summary.accounts) _LoanAccountDetailTile(row: row),
      ]),
    );
  }
}

class _LoanAccountDetailTile extends StatelessWidget {
  const _LoanAccountDetailTile({required this.row});

  final LoanDueAccountSummary row;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${row.loan.displayName} 還款期別', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
      subtitle: Text('本期本金 ${_money(row.principalDue)} + 利息 ${_money(row.interestDue)} ${row.loan.currency.code}'),
      children: [_LoanScheduleTable(row: row)],
    );
  }
}

class _PlanSettingsSummarySection extends StatelessWidget {
  const _PlanSettingsSummarySection();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.settings_outlined),
        title: Text('計劃設定', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        subtitle: const Text('通知、提醒、信用卡規則與後續擴充設定'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _PlanSettingTile(
            icon: Icons.notifications_active_outlined,
            title: '本機通知與提醒基礎',
            subtitle: '目前先保留計劃提醒入口；正式通知排程將接入 P3+ backlog。',
            status: '待接入通知套件',
            onTap: () => _showPlanSettingInfo(context, '本機通知與提醒基礎', '此區會承接還款提醒、繳款提醒與後續本機通知排程。現階段已明確標示為待接入，避免呈現空殼狀態。'),
          ),
          _PlanSettingTile(
            icon: Icons.rule_folder_outlined,
            title: '信用卡延伸規則',
            subtitle: '最低應繳、循環利息與銀行規則管理入口。',
            status: '已規劃',
            onTap: () => _showPlanSettingInfo(context, '信用卡延伸規則', '此區用來收斂最低應繳、循環利息、違約金與銀行規則 profile / assignment。完整設定頁會以獨立 issue 延伸。'),
          ),
          _PlanSettingTile(
            icon: Icons.tune_outlined,
            title: '通知顯示偏好',
            subtitle: '上方 / 下方、停留秒數、浮動樣式等個人化設定。',
            status: '#98 deferred',
            onTap: () => _showPlanSettingInfo(context, '通知顯示偏好', '#98 已完成 top overlay toast service 基礎；位置、秒數與浮動樣式設定頁化保留為 deferred follow-up。'),
          ),
        ],
      ),
    );
  }
}

class _PlanSettingTile extends StatelessWidget {
  const _PlanSettingTile({required this.icon, required this.title, required this.subtitle, required this.status, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Row(children: [Expanded(child: Text(title)), const SizedBox(width: 8), Chip(label: Text(status), visualDensity: VisualDensity.compact)]),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

Future<void> _showPlanSettingInfo(BuildContext context, String title, String message) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('知道了'))],
    ),
  );
}

class _ExpandableSummarySection extends StatelessWidget {
  const _ExpandableSummarySection({required this.icon, required this.title, required this.chips, required this.detail, required this.isEmpty, required this.emptyMessage});

  final IconData icon;
  final String title;
  final List<Widget> chips;
  final Widget detail;
  final bool isEmpty;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [isEmpty ? Align(alignment: Alignment.centerLeft, child: Text(emptyMessage)) : detail],
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900, color: Colors.blueGrey)));
}

class _TransactionTable extends StatelessWidget {
  const _TransactionTable({required this.transactions, required this.currency});
  final List<TransactionRecord> transactions;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) return const Align(alignment: Alignment.centerLeft, child: Text('無資料'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(columns: const [DataColumn(label: Text('日期')), DataColumn(label: Text('類別')), DataColumn(label: Text('金額')), DataColumn(label: Text('商家'))], rows: [
        for (final tx in transactions)
          DataRow(cells: [
            DataCell(Text(DateFormat('MM/dd').format(tx.occurredAt))),
            DataCell(Text(tx.category)),
            DataCell(Text('${_money(tx.amount)} ${currency.code}')),
            DataCell(Text(tx.merchantName.isEmpty ? '-' : tx.merchantName)),
          ]),
      ]),
    );
  }
}

class _InstallmentScheduleTable extends StatelessWidget {
  const _InstallmentScheduleTable({required this.items});
  final List<InstallmentPlanScheduleSnapshot> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Align(alignment: Alignment.centerLeft, child: Text('無待繳分期計畫'));
    return Column(children: [for (final snapshot in items) _InstallmentPlanExpansionTile(snapshot: snapshot)]);
  }
}

class _InstallmentPlanExpansionTile extends StatelessWidget {
  const _InstallmentPlanExpansionTile({required this.snapshot});

  final InstallmentPlanScheduleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final plan = snapshot.plan;
    final nextDue = snapshot.nextDueItem;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${plan.cardNameSnapshot}・${_money(plan.principal)} ${plan.currency.code}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
      subtitle: Text(nextDue == null ? '無待繳期別' : '下一期 第 ${nextDue.periodNumber}/${plan.termCount} 期・應繳 ${_money(nextDue.totalPayment)} ${plan.currency.code}'),
      children: [_InstallmentPlanScheduleRows(snapshot: snapshot)],
    );
  }
}

class _InstallmentPlanScheduleRows extends ConsumerWidget {
  const _InstallmentPlanScheduleRows({required this.snapshot});

  final InstallmentPlanScheduleSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (snapshot.scheduleItems.isEmpty) return const Align(alignment: Alignment.centerLeft, child: Text('無期別明細'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(columns: const [DataColumn(label: Text('期')), DataColumn(label: Text('帳單日')), DataColumn(label: Text('本金')), DataColumn(label: Text('費用')), DataColumn(label: Text('應繳')), DataColumn(label: Text('剩餘本金')), DataColumn(label: Text('狀態')), DataColumn(label: Text('操作'))], rows: [
        for (final item in snapshot.scheduleItems)
          DataRow(cells: [
            DataCell(Text('${item.periodNumber}/${snapshot.plan.termCount}')),
            DataCell(Text(DateFormat('yyyy/MM/dd').format(item.statementDate))),
            DataCell(Text('${_money(item.principal)} ${snapshot.plan.currency.code}')),
            DataCell(Text('${_money(item.fee)} ${snapshot.plan.currency.code}')),
            DataCell(Text('${_money(item.totalPayment)} ${snapshot.plan.currency.code}')),
            DataCell(Text('${_money(item.remainingPrincipalAfterPayment)} ${snapshot.plan.currency.code}')),
            DataCell(Text(_scheduleStatusText(item.status))),
            DataCell(_InstallmentScheduleAction(snapshot: snapshot, item: item)),
          ]),
      ]),
    );
  }
}

class _InstallmentScheduleAction extends ConsumerWidget {
  const _InstallmentScheduleAction({required this.snapshot, required this.item});

  final InstallmentPlanScheduleSnapshot snapshot;
  final InstallmentScheduleItemRecord item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generatedTransactionId = item.generatedTransactionId?.trim();
    final canReverse = item.status == InstallmentScheduleItemStatus.paid && generatedTransactionId != null && generatedTransactionId.isNotEmpty;
    if (!canReverse) return const Text('-');
    return TextButton.icon(
      onPressed: () => _confirmReverseInstallmentPayment(context, ref, snapshot: snapshot, item: item, generatedTransactionId: generatedTransactionId),
      icon: const Icon(Icons.undo, size: 18),
      label: const Text('撤銷繳款'),
    );
  }
}

class _LoanScheduleTable extends StatelessWidget {
  const _LoanScheduleTable({required this.row});
  final LoanDueAccountSummary row;

  @override
  Widget build(BuildContext context) {
    if (row.rows.isEmpty) return const Align(alignment: Alignment.centerLeft, child: Text('無貸款期別資料'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(columns: const [DataColumn(label: Text('期')), DataColumn(label: Text('到期日')), DataColumn(label: Text('本金')), DataColumn(label: Text('利息')), DataColumn(label: Text('應繳')), DataColumn(label: Text('剩餘本金')), DataColumn(label: Text('繳款註記'))], rows: [
        for (final item in row.rows)
          DataRow(cells: [
            DataCell(Text('${item.periodNumber}')),
            DataCell(Text(DateFormat('yyyy/MM/dd').format(item.dueDate))),
            DataCell(Text('${_money(item.principal)} ${row.loan.currency.code}')),
            DataCell(Text('${_money(item.interest)} ${row.loan.currency.code}')),
            DataCell(Text('${_money(item.total)} ${row.loan.currency.code}')),
            DataCell(Text('${_money(item.remainingPrincipal)} ${row.loan.currency.code}')),
            DataCell(Text(item.paymentNote)),
          ]),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label：$value'));
}

Future<void> _confirmReverseInstallmentPayment(
  BuildContext context,
  WidgetRef ref, {
  required InstallmentPlanScheduleSnapshot snapshot,
  required InstallmentScheduleItemRecord item,
  required String generatedTransactionId,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('撤銷分期繳款？'),
      content: Text('這會刪除第 ${item.periodNumber}/${snapshot.plan.termCount} 期的分期繳款交易，並把該期狀態回復為未繳。是否確認？'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('確認撤銷')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(transactionLedgerProvider.notifier).deleteLinkedInstallmentPayment(planId: snapshot.plan.id, scheduleItemId: item.id, generatedTransactionId: generatedTransactionId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已撤銷分期繳款，該期已回復為未繳'), behavior: SnackBarBehavior.floating));
  } on InstallmentRepositoryFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()), behavior: SnackBarBehavior.floating));
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

String _scheduleStatusText(InstallmentScheduleItemStatus status) {
  switch (status) {
    case InstallmentScheduleItemStatus.pending:
      return '未繳';
    case InstallmentScheduleItemStatus.billed:
      return '已出帳';
    case InstallmentScheduleItemStatus.paid:
      return '已繳';
    case InstallmentScheduleItemStatus.cancelled:
      return '已取消';
  }
}
