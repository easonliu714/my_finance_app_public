import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_record.dart';
import '../transaction/transaction_record.dart';
import 'credit_card_installment_generation_guard.dart';
import 'credit_card_installment_payment_preview.dart';
import 'credit_card_installment_providers.dart';
import 'credit_card_installment_repository.dart';
import 'credit_card_installment_service.dart';
import 'credit_card_installment_source_transaction_flow.dart';

class SourceTransactionInstallmentEntryCard extends ConsumerStatefulWidget {
  const SourceTransactionInstallmentEntryCard({
    super.key,
    required this.transaction,
    required this.card,
    this.onPlanCreated,
  });

  final TransactionRecord transaction;
  final AccountRecord card;
  final ValueChanged<InstallmentPlanRecord>? onPlanCreated;

  @override
  ConsumerState<SourceTransactionInstallmentEntryCard> createState() => _SourceTransactionInstallmentEntryCardState();
}

class _SourceTransactionInstallmentEntryCardState extends ConsumerState<SourceTransactionInstallmentEntryCard> {
  final _termController = TextEditingController(text: '6');
  final _feeController = TextEditingController(text: '0');
  final _annualRateController = TextEditingController(text: '0');
  DateTime _firstStatementDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _isCreating = false;
  String _message = '';
  late Future<InstallmentPlanRecord?> _existingPlanFuture;

  @override
  void initState() {
    super.initState();
    _existingPlanFuture = _loadExistingPlan();
  }

  @override
  void didUpdateWidget(covariant SourceTransactionInstallmentEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transaction.id != widget.transaction.id || oldWidget.card.id != widget.card.id) {
      _existingPlanFuture = _loadExistingPlan();
    }
  }

  @override
  void dispose() {
    _termController.dispose();
    _feeController.dispose();
    _annualRateController.dispose();
    super.dispose();
  }

  Future<InstallmentPlanRecord?> _loadExistingPlan() {
    return ref.read(creditCardInstallmentRepositoryProvider).findActivePlanBySourceTransactionId(widget.transaction.id);
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = checkSourceTransactionInstallmentEligibility(transaction: widget.transaction, card: widget.card);
    final colorScheme = Theme.of(context).colorScheme;
    final repository = ref.watch(creditCardInstallmentRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.splitscreen_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text('轉為信用卡分期', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Chip(label: Text(widget.transaction.currency.code)),
          ]),
          const SizedBox(height: 8),
          Text(
            '建立後只保存分期計畫與期別；不建立付款交易、不寫帳單快照、不更新帳戶餘額。手續費與年利率是兩個獨立欄位，可同時輸入。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ReadonlyFacts(transaction: widget.transaction, card: widget.card),
          const SizedBox(height: 12),
          if (!eligibility.isEligible)
            Text(eligibility.message, style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w800))
          else
            FutureBuilder<InstallmentPlanRecord?>(
              future: _existingPlanFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  );
                }
                final existingPlan = snapshot.data;
                if (existingPlan != null) {
                  return _ExistingPlanSummary(plan: existingPlan, repository: repository);
                }
                return _CreatePlanForm(
                  termController: _termController,
                  feeController: _feeController,
                  annualRateController: _annualRateController,
                  firstStatementDate: _firstStatementDate,
                  currencyCode: widget.transaction.currency.code,
                  isCreating: _isCreating,
                  onPickFirstStatementDate: _pickFirstStatementDate,
                  onCreatePlan: _createPlan,
                );
              },
            ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_message, style: TextStyle(color: _message.startsWith('已建立') ? colorScheme.primary : colorScheme.error, fontWeight: FontWeight.w800)),
          ],
        ]),
      ),
    );
  }

  Future<void> _pickFirstStatementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstStatementDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _firstStatementDate = picked);
  }

  Future<void> _createPlan() async {
    final termCount = int.tryParse(_termController.text.trim());
    if (termCount == null || termCount <= 0 || termCount > 120) {
      setState(() => _message = '請輸入 1 到 120 之間的期數。');
      return;
    }
    final fee = double.tryParse(_feeController.text.trim()) ?? 0;
    final annualRate = double.tryParse(_annualRateController.text.trim()) ?? 0;
    if (fee < 0 || annualRate < 0) {
      setState(() => _message = '總手續費與年利率不可為負數。');
      return;
    }
    setState(() {
      _isCreating = true;
      _message = '';
    });
    try {
      final repository = ref.read(creditCardInstallmentRepositoryProvider);
      final existingPlan = await repository.findActivePlanBySourceTransactionId(widget.transaction.id);
      if (existingPlan != null) {
        if (!mounted) return;
        setState(() {
          _existingPlanFuture = Future<InstallmentPlanRecord?>.value(existingPlan);
          _message = '此交易已有分期計畫，不能重複建立。';
        });
        return;
      }
      final plan = await createInstallmentPlanFromSourceTransaction(
        repository: repository,
        transaction: widget.transaction,
        card: widget.card,
        termCount: termCount,
        firstStatementDate: _firstStatementDate,
        feeMode: CreditCardInstallmentFeeMode.totalFee,
        totalFee: fee,
        annualRate: annualRate,
        note: 'source transaction UI flow: ${widget.transaction.id}',
      );
      await ref.read(creditCardInstallmentControllerProvider.notifier).loadPlansByCardId(widget.card.id, status: InstallmentPlanStatus.active);
      if (!mounted) return;
      setState(() {
        _existingPlanFuture = Future<InstallmentPlanRecord?>.value(plan);
        _message = '已建立分期計畫：${plan.id}';
      });
      widget.onPlanCreated?.call(plan);
    } on DuplicateInstallmentSourceFailure catch (error) {
      if (!mounted) return;
      final existingPlan = await ref.read(creditCardInstallmentRepositoryProvider).findActivePlanBySourceTransactionId(widget.transaction.id);
      if (!mounted) return;
      setState(() {
        if (existingPlan != null) _existingPlanFuture = Future<InstallmentPlanRecord?>.value(existingPlan);
        _message = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '建立分期計畫失敗：$error');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}

class _CreatePlanForm extends StatelessWidget {
  const _CreatePlanForm({
    required this.termController,
    required this.feeController,
    required this.annualRateController,
    required this.firstStatementDate,
    required this.currencyCode,
    required this.isCreating,
    required this.onPickFirstStatementDate,
    required this.onCreatePlan,
  });

  final TextEditingController termController;
  final TextEditingController feeController;
  final TextEditingController annualRateController;
  final DateTime firstStatementDate;
  final String currencyCode;
  final bool isCreating;
  final VoidCallback onPickFirstStatementDate;
  final VoidCallback onCreatePlan;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('分期條件', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      TextField(
        controller: termController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.format_list_numbered_outlined), labelText: '期數', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: feeController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.payments_outlined), labelText: '總手續費 $currencyCode', border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('sourceTransactionInstallmentAnnualRateField'),
        controller: annualRateController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.percent_outlined), labelText: '年利率估算 %', helperText: '可留 0；若與總手續費同時輸入，兩者會合併計算。', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined),
        title: const Text('第一期帳單日'),
        subtitle: Text(_dateLabel(firstStatementDate)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onPickFirstStatementDate,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: isCreating ? null : onCreatePlan,
          icon: isCreating ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_task_outlined),
          label: const Text('建立分期計畫'),
        ),
      ),
    ]);
  }
}

class _ExistingPlanSummary extends StatelessWidget {
  const _ExistingPlanSummary({required this.plan, required this.repository});

  final InstallmentPlanRecord plan;
  final CreditCardInstallmentRepository repository;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_outlined, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('此交易已有分期計畫', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: colorScheme.primary)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text('計畫：${plan.id}')),
          Chip(label: Text('期數：${plan.termCount}')),
          Chip(label: Text('狀態：${plan.status.name}')),
          Chip(label: Text('手續費：${_amountLabel(plan.totalFee)} ${plan.currency.code}')),
          Chip(label: Text('年利率：${_amountLabel(plan.annualRate)}%')),
        ]),
        const SizedBox(height: 4),
        Text('為避免重複分期，本交易不能再次建立 active 分期計畫。', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        FutureBuilder<List<InstallmentScheduleItemRecord>>(
          future: repository.loadScheduleItems(plan.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            final items = snapshot.data ?? const <InstallmentScheduleItemRecord>[];
            if (items.isEmpty) return const Text('尚無分期期別。');
            return _ScheduleItemsPreview(plan: plan, items: items, currencyCode: plan.currency.code);
          },
        ),
      ]),
    );
  }
}

class _ScheduleItemsPreview extends StatelessWidget {
  const _ScheduleItemsPreview({required this.plan, required this.items, required this.currencyCode});

  final InstallmentPlanRecord plan;
  final List<InstallmentScheduleItemRecord> items;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('分期期別', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      for (final item in items.take(12)) _ScheduleItemTile(plan: plan, item: item, currencyCode: currencyCode),
      if (items.length > 12) Padding(padding: const EdgeInsets.only(top: 4), child: Text('另有 ${items.length - 12} 期未顯示', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class _ScheduleItemTile extends StatelessWidget {
  const _ScheduleItemTile({required this.plan, required this.item, required this.currencyCode});

  final InstallmentPlanRecord plan;
  final InstallmentScheduleItemRecord item;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('第 ${item.periodNumber} 期・${_dateLabel(item.statementDate)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
              Chip(label: Text(item.status.name)),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Text('本金 ${_amountLabel(item.principal)} $currencyCode'),
              Text('手續費 ${_amountLabel(item.fee)} $currencyCode'),
              Text('應付 ${_amountLabel(item.totalPayment)} $currencyCode'),
            ]),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _showDebugPaymentSimulation(context, plan: plan, item: item),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Debug 模擬付款'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _showDebugPaymentSimulation(BuildContext context, {required InstallmentPlanRecord plan, required InstallmentScheduleItemRecord item}) {
    try {
      final preview = buildInstallmentPaymentTransactionPreview(
        InstallmentPaymentPreviewInput(plan: plan, scheduleItem: item, paymentAccount: _debugPaymentAccount()),
      );
      final guard = markScheduleItemGeneratedPreview(
        GeneratedInstallmentTransactionGuardInput(scheduleItem: item, generatedTransactionId: preview.transaction.id),
      );
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Debug 付款模擬'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('此為 preview，不會寫入交易、帳單或帳戶餘額。'),
              const SizedBox(height: 8),
              Text('交易草案：${preview.transaction.id}'),
              Text('付款帳戶：${preview.transaction.accountName}'),
              Text('金額：${_amountLabel(preview.transaction.amount)} ${preview.transaction.currency.code}'),
              Text('期別狀態：${guard.previousStatus.name} → ${guard.nextStatus.name}'),
              Text('generatedTransactionId：${guard.generatedTransactionId}'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('關閉'))]
        ),
      );
    } catch (error) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Debug 付款模擬失敗'),
          content: Text('$error'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('關閉'))],
        ),
      );
    }
  }
}

class _ReadonlyFacts extends StatelessWidget {
  const _ReadonlyFacts({required this.transaction, required this.card});

  final TransactionRecord transaction;
  final AccountRecord card;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      Chip(label: Text('交易：${transaction.id}')),
      Chip(label: Text('卡片：${card.displayName}')),
      Chip(label: Text('本金：${_amountLabel(transaction.amount)} ${transaction.currency.code}')),
    ]);
  }
}

AccountRecord _debugPaymentAccount() {
  return const AccountRecord(id: 'debug-payment-account', name: 'Debug 付款帳戶', type: AccountType.bank, initialBalance: 0, sortOrder: 9999);
}

String _amountLabel(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _dateLabel(DateTime value) => '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
