import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../account/account_providers.dart';
import '../account/account_record.dart';
import 'credit_card_installment_providers.dart';
import 'credit_card_installment_repository.dart';
import 'credit_card_installment_repository_factory.dart';
import 'credit_card_installment_service.dart';

class CreditCardInstallmentPreviewPage extends ConsumerStatefulWidget {
  const CreditCardInstallmentPreviewPage({super.key});

  static const routeName = 'credit-card-installment-preview';
  static const routePath = '/plans/credit-card-installment-preview';

  @override
  ConsumerState<CreditCardInstallmentPreviewPage> createState() => _CreditCardInstallmentPreviewPageState();
}

class _CreditCardInstallmentPreviewPageState extends ConsumerState<CreditCardInstallmentPreviewPage> {
  final _principalController = TextEditingController(text: '12000');
  final _termController = TextEditingController(text: '6');
  final _totalFeeController = TextEditingController(text: '0');
  final _annualRateController = TextEditingController(text: '12');
  final _originalUnpaidBalanceController = TextEditingController(text: '12000');
  DateTime _firstStatementDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  CreditCardInstallmentScenario _scenario = CreditCardInstallmentScenario.purchaseTime;
  CreditCardInstallmentRemainderPolicy _remainderPolicy = CreditCardInstallmentRemainderPolicy.firstPeriod;
  String? _selectedCardId;
  String? _errorText;
  CreditCardInstallmentSchedule? _schedule;
  int _activePlanReloadToken = 0;

  @override
  void dispose() {
    _principalController.dispose();
    _termController.dispose();
    _totalFeeController.dispose();
    _annualRateController.dispose();
    _originalUnpaidBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountListProvider);
    final repositoryMode = ref.watch(creditCardInstallmentDebugRepositoryModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('信用卡分期')),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('讀取信用卡帳戶失敗：$error')),
        data: (items) {
          final cards = items.where((account) => account.type == AccountType.creditCard && !account.isArchived).toList();
          final selectedCard = _resolveSelectedCard(cards);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              _PreviewScopeNotice(currency: selectedCard?.currency ?? CurrencyCode.twd, repositoryMode: repositoryMode),
              if (kDebugMode) ...[
                const SizedBox(height: 12),
                _DebugSQLiteToggleCard(
                  mode: repositoryMode,
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(creditCardInstallmentDebugRepositoryModeProvider.notifier).state = value;
                    setState(() {
                      _schedule = null;
                      _errorText = null;
                      _activePlanReloadToken += 1;
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              if (cards.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('尚未建立信用卡帳戶，請先到帳戶頁新增信用卡。')))
              else ...[
                _InputCard(
                  cards: cards,
                  selectedCard: selectedCard,
                  selectedCardId: _selectedCardId,
                  onCardChanged: (value) => setState(() {
                    _selectedCardId = value;
                    _schedule = null;
                  }),
                  scenario: _scenario,
                  onScenarioChanged: (value) => setState(() {
                    _scenario = value;
                    _schedule = null;
                  }),
                  remainderPolicy: _remainderPolicy,
                  onRemainderPolicyChanged: (value) => setState(() {
                    _remainderPolicy = value;
                    _schedule = null;
                  }),
                  principalController: _principalController,
                  termController: _termController,
                  totalFeeController: _totalFeeController,
                  annualRateController: _annualRateController,
                  originalUnpaidBalanceController: _originalUnpaidBalanceController,
                  firstStatementDate: _firstStatementDate,
                  onPickDate: () => _pickFirstStatementDate(context),
                  onPreview: () => _buildPreview(selectedCard),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_errorText!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                    ),
                  ),
                ],
                if (_schedule != null) ...[
                  const SizedBox(height: 12),
                  _ScheduleResultCard(schedule: _schedule!, repositoryMode: repositoryMode, onCreateActivePlan: () => _createActivePlan(selectedCard, repositoryMode)),
                ],
                const SizedBox(height: 12),
                _ActivePlansCard(
                  key: ValueKey('${repositoryMode.name}-${cards.map((card) => card.id).join('|')}-$_activePlanReloadToken'),
                  cards: cards,
                  repository: ref.watch(creditCardInstallmentRepositoryProvider),
                  repositoryMode: repositoryMode,
                  onRefresh: () => setState(() => _activePlanReloadToken += 1),
                  onCancel: (planId) => _cancelPlan(planId, repositoryMode),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  AccountRecord? _resolveSelectedCard(List<AccountRecord> cards) {
    if (cards.isEmpty) return null;
    final selectedId = _selectedCardId;
    if (selectedId != null) {
      for (final card in cards) {
        if (card.id == selectedId) return card;
      }
    }
    return cards.first;
  }

  Future<void> _pickFirstStatementDate(BuildContext context) async {
    final picked = await showDatePicker(context: context, initialDate: _firstStatementDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null || !mounted) return;
    setState(() {
      _firstStatementDate = picked;
      _schedule = null;
    });
  }

  Future<void> _buildPreview(AccountRecord? card) async {
    final input = _buildInput(card, idPrefix: 'preview');
    if (input == null) return;
    try {
      final schedule = await ref.read(creditCardInstallmentControllerProvider.notifier).buildPreview(input);
      setState(() {
        _errorText = null;
        _schedule = schedule;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已更新分期試算預覽，不會寫入任何資料。')));
    } catch (error) {
      setState(() {
        _errorText = '試算失敗：$error';
        _schedule = null;
      });
    }
  }

  Future<void> _createActivePlan(AccountRecord? card, CreditCardInstallmentRepositoryMode repositoryMode) async {
    final input = _buildInput(card, idPrefix: repositoryMode == CreditCardInstallmentRepositoryMode.sqlite ? 'installment' : 'fake-active');
    if (input == null) return;
    try {
      final plan = await ref.read(creditCardInstallmentControllerProvider.notifier).createActivePlan(input);
      if (!mounted) return;
      setState(() => _activePlanReloadToken += 1);
      final message = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite
          ? '已建立分期計畫：${plan.id}。只保存分期表，不建立交易/帳單/餘額。'
          : '已建立 Fake Active Plan：${plan.id}。尚未寫入 SQLite。';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      setState(() {
        _errorText = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite ? '建立分期計畫失敗：$error' : '建立 Fake Active Plan 失敗：$error';
      });
    }
  }

  Future<void> _cancelPlan(String planId, CreditCardInstallmentRepositoryMode repositoryMode) async {
    try {
      await ref.read(creditCardInstallmentRepositoryProvider).cancelPlan(planId);
      if (!mounted) return;
      setState(() => _activePlanReloadToken += 1);
      final label = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite ? '分期計畫' : 'Fake Active Plan';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已取消 $label：$planId')));
    } catch (error) {
      setState(() {
        _errorText = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite ? '取消分期計畫失敗：$error' : '取消 Fake Active Plan 失敗：$error';
      });
    }
  }

  CreditCardInstallmentPlanInput? _buildInput(AccountRecord? card, {required String idPrefix}) {
    if (card == null) return null;
    final principal = double.tryParse(_principalController.text.trim());
    final termCount = int.tryParse(_termController.text.trim());
    final totalFee = double.tryParse(_totalFeeController.text.trim()) ?? 0;
    final annualRate = double.tryParse(_annualRateController.text.trim()) ?? 0;
    final originalUnpaidBalance = double.tryParse(_originalUnpaidBalanceController.text.trim()) ?? 0;
    if (principal == null || principal <= 0) {
      setState(() {
        _errorText = '請輸入大於 0 的分期本金。';
        _schedule = null;
      });
      return null;
    }
    if (termCount == null || termCount <= 0 || termCount > 120) {
      setState(() {
        _errorText = '請輸入 1 到 120 之間的分期期數。';
        _schedule = null;
      });
      return null;
    }
    return CreditCardInstallmentPlanInput(
      id: '$idPrefix-${DateTime.now().millisecondsSinceEpoch}',
      scenario: _scenario,
      cardId: card.id,
      cardName: card.displayName,
      currency: card.currency,
      principal: principal,
      termCount: termCount,
      firstStatementDate: _firstStatementDate,
      feeMode: CreditCardInstallmentFeeMode.totalFee,
      totalFee: totalFee,
      annualRate: annualRate,
      remainderPolicy: _remainderPolicy,
      originalUnpaidBalance: originalUnpaidBalance,
      note: '$idPrefix only',
    );
  }
}

class _PreviewScopeNotice extends StatelessWidget {
  const _PreviewScopeNotice({required this.currency, required this.repositoryMode});
  final CurrencyCode currency;
  final CreditCardInstallmentRepositoryMode repositoryMode;

  @override
  Widget build(BuildContext context) {
    final isSqlite = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.calculate_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text('分期試算', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Chip(label: Text(currency.code)),
          ]),
          const SizedBox(height: 8),
          Text(
            isSqlite
                ? '建立分期計畫只會保存分期計畫與期別；不建立付款交易、不保存帳單快照、不更新帳戶餘額。'
                : '目前為 Preview-safe in-memory 模式：可建立 Fake Active Plan 以驗證流程；不建立交易、不保存帳單快照，也不會寫入 SQLite。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

class _DebugSQLiteToggleCard extends StatelessWidget {
  const _DebugSQLiteToggleCard({required this.mode, required this.onChanged});
  final CreditCardInstallmentRepositoryMode mode;
  final ValueChanged<CreditCardInstallmentRepositoryMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.32),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.developer_mode_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text('Debug-only SQLite 測試入口', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            const Chip(label: Text('DEBUG')),
          ]),
          const SizedBox(height: 8),
          Text('此入口只在 debug build 顯示。切到 SQLite 後，建立分期只允許寫入 installment tables；不得產生交易流水、帳單快照或帳戶餘額異動。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<CreditCardInstallmentRepositoryMode>(
            isExpanded: true,
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Repository 模式', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: CreditCardInstallmentRepositoryMode.previewSafeInMemory, child: Text('Preview-safe in-memory（預設）')),
              DropdownMenuItem(value: CreditCardInstallmentRepositoryMode.sqlite, child: Text('SQLite adapter')),
            ],
            onChanged: onChanged,
          ),
        ]),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.cards,
    required this.selectedCard,
    required this.selectedCardId,
    required this.onCardChanged,
    required this.scenario,
    required this.onScenarioChanged,
    required this.remainderPolicy,
    required this.onRemainderPolicyChanged,
    required this.principalController,
    required this.termController,
    required this.totalFeeController,
    required this.annualRateController,
    required this.originalUnpaidBalanceController,
    required this.firstStatementDate,
    required this.onPickDate,
    required this.onPreview,
  });
  final List<AccountRecord> cards;
  final AccountRecord? selectedCard;
  final String? selectedCardId;
  final ValueChanged<String?> onCardChanged;
  final CreditCardInstallmentScenario scenario;
  final ValueChanged<CreditCardInstallmentScenario> onScenarioChanged;
  final CreditCardInstallmentRemainderPolicy remainderPolicy;
  final ValueChanged<CreditCardInstallmentRemainderPolicy> onRemainderPolicyChanged;
  final TextEditingController principalController;
  final TextEditingController termController;
  final TextEditingController totalFeeController;
  final TextEditingController annualRateController;
  final TextEditingController originalUnpaidBalanceController;
  final DateTime firstStatementDate;
  final VoidCallback onPickDate;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final currency = selectedCard?.currency ?? CurrencyCode.twd;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.edit_note_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text('試算條件', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedCard?.id ?? selectedCardId,
            decoration: const InputDecoration(labelText: '信用卡', border: OutlineInputBorder()),
            items: [for (final card in cards) DropdownMenuItem(value: card.id, child: Text(card.displayName, overflow: TextOverflow.ellipsis))],
            onChanged: onCardChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CreditCardInstallmentScenario>(
            isExpanded: true,
            initialValue: scenario,
            decoration: const InputDecoration(labelText: '分期情境', border: OutlineInputBorder()),
            items: [for (final item in CreditCardInstallmentScenario.values) DropdownMenuItem(value: item, child: Text(item.label, overflow: TextOverflow.ellipsis))],
            onChanged: (value) {
              if (value != null) onScenarioChanged(value);
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _NumberField(controller: principalController, label: '分期本金 ${currency.code}')),
            const SizedBox(width: 8),
            Expanded(child: _NumberField(controller: termController, label: '期數')),
          ]),
          const SizedBox(height: 12),
          _NumberField(controller: totalFeeController, label: '總手續費 ${currency.code}'),
          const SizedBox(height: 12),
          _NumberField(controller: annualRateController, label: '年利率估算 %'),
          const SizedBox(height: 6),
          Text('總手續費與年利率可同時存在，會合併到每期手續費估算。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey)),
          const SizedBox(height: 12),
          DropdownButtonFormField<CreditCardInstallmentRemainderPolicy>(
            isExpanded: true,
            initialValue: remainderPolicy,
            decoration: const InputDecoration(labelText: '除不盡差額', border: OutlineInputBorder()),
            items: [for (final item in CreditCardInstallmentRemainderPolicy.values) DropdownMenuItem(value: item, child: Text(item.label, overflow: TextOverflow.ellipsis))],
            onChanged: (value) {
              if (value != null) onRemainderPolicyChanged(value);
            },
          ),
          if (scenario == CreditCardInstallmentScenario.postStatementSpecifiedAmount) ...[
            const SizedBox(height: 12),
            _NumberField(controller: originalUnpaidBalanceController, label: '原未繳 / 循環暴險 ${currency.code}'),
          ],
          const SizedBox(height: 12),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_outlined), title: const Text('第一期帳單日'), subtitle: Text(DateFormat('yyyy/MM/dd').format(firstStatementDate)), trailing: const Icon(Icons.chevron_right), onTap: onPickDate),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: onPreview, icon: const Icon(Icons.preview_outlined), label: const Text('更新試算預覽'))),
        ]),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));
  }
}

class _ScheduleResultCard extends StatelessWidget {
  const _ScheduleResultCard({required this.schedule, required this.repositoryMode, required this.onCreateActivePlan});
  final CreditCardInstallmentSchedule schedule;
  final CreditCardInstallmentRepositoryMode repositoryMode;
  final VoidCallback onCreateActivePlan;

  @override
  Widget build(BuildContext context) {
    final currency = schedule.input.currency;
    final isSqlite = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const CircleAvatar(child: Icon(Icons.table_chart_outlined)), const SizedBox(width: 12), Expanded(child: Text('試算結果', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))), Chip(label: Text('${schedule.items.length} 期'))]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _SummaryChip(label: '總本金', value: '${_money(schedule.totalPrincipal)} ${currency.code}'),
            _SummaryChip(label: '總手續費', value: '${_money(schedule.totalFee)} ${currency.code}'),
            _SummaryChip(label: '總應付', value: '${_money(schedule.grandTotal)} ${currency.code}'),
            if (schedule.isPostStatementSpecifiedAmount) _SummaryChip(label: '立即沖抵', value: '${_money(schedule.immediateRevolvingExposureOffset)} ${currency.code}'),
            if (schedule.isPostStatementSpecifiedAmount) _SummaryChip(label: '沖抵後暴險', value: '${_money(schedule.remainingRevolvingExposureAfterOffset)} ${currency.code}'),
          ]),
          const SizedBox(height: 12),
          Text(isSqlite ? '建立分期計畫只會保存分期表，不會建立交易流水、帳單快照或帳戶餘額異動。' : '此結果尚未入帳；按下「建立 Fake Active Plan」只會寫入 in-memory fake repository，不會寫入 SQLite。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: onCreateActivePlan, icon: const Icon(Icons.add_task_outlined), label: Text(isSqlite ? '建立分期計畫' : '建立 Fake Active Plan'))),
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('期')), DataColumn(label: Text('帳單日')), DataColumn(label: Text('本金')), DataColumn(label: Text('手續費')), DataColumn(label: Text('應付')), DataColumn(label: Text('剩餘本金')), DataColumn(label: Text('沖抵'))], rows: [for (final item in schedule.items) DataRow(cells: [DataCell(Text('${item.periodNumber}')), DataCell(Text(DateFormat('yyyy/MM/dd').format(item.statementDate))), DataCell(Text(_money(item.principal))), DataCell(Text(_money(item.fee))), DataCell(Text(_money(item.totalPayment))), DataCell(Text(_money(item.remainingPrincipalAfterPayment))), DataCell(Text(item.revolvingExposureOffset == 0 ? '-' : _money(item.revolvingExposureOffset)))]),])),
        ]),
      ),
    );
  }
}

class _ActivePlansCard extends StatelessWidget {
  const _ActivePlansCard({super.key, required this.cards, required this.repository, required this.repositoryMode, required this.onRefresh, required this.onCancel});
  final List<AccountRecord> cards;
  final CreditCardInstallmentRepository repository;
  final CreditCardInstallmentRepositoryMode repositoryMode;
  final VoidCallback onRefresh;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final isSqlite = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.storage_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text(isSqlite ? '全部信用卡分期計畫' : '全部 Fake Active Plans', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh_outlined)),
          ]),
          const SizedBox(height: 8),
          Text(isSqlite ? '此區會列出所有未封存信用卡的 active 分期，不受上方試算信用卡選項限制。前版殘留分期也應可在此取消。' : '此區列出目前 repository 中所有 active fake plans。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FutureBuilder<List<_ActivePlanWithItems>>(
            future: _loadActivePlans(repository, cards),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done && !snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.data ?? const <_ActivePlanWithItems>[];
              if (items.isEmpty) return Text(isSqlite ? '尚無 active 分期計畫。' : '尚無 Fake Active Plan。');
              return Column(children: [for (final item in items) _ActivePlanTile(plan: item.plan, items: item.items, repositoryMode: repositoryMode, onCancel: onCancel)]);
            },
          ),
        ]),
      ),
    );
  }
}

class _ActivePlanWithItems {
  const _ActivePlanWithItems({required this.plan, required this.items});
  final InstallmentPlanRecord plan;
  final List<InstallmentScheduleItemRecord> items;
}

Future<List<_ActivePlanWithItems>> _loadActivePlans(CreditCardInstallmentRepository repository, List<AccountRecord> cards) async {
  final result = <_ActivePlanWithItems>[];
  for (final card in cards) {
    final plans = await repository.loadPlansByCardId(card.id, status: InstallmentPlanStatus.active);
    for (final plan in plans) {
      result.add(_ActivePlanWithItems(plan: plan, items: await repository.loadScheduleItems(plan.id)));
    }
  }
  result.sort((a, b) => b.plan.createdAt.compareTo(a.plan.createdAt));
  return result;
}

class _ActivePlanTile extends StatelessWidget {
  const _ActivePlanTile({required this.plan, required this.items, required this.repositoryMode, required this.onCancel});
  final InstallmentPlanRecord plan;
  final List<InstallmentScheduleItemRecord> items;
  final CreditCardInstallmentRepositoryMode repositoryMode;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final isSqlite = repositoryMode == CreditCardInstallmentRepositoryMode.sqlite;
    final source = plan.sourceTransactionId == null || plan.sourceTransactionId!.isEmpty ? '-' : plan.sourceTransactionId!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(plan.cardNameSnapshot, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
              Chip(label: Text(plan.scenario.label)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _SummaryChip(label: '本金', value: '${_money(plan.principal)} ${plan.currency.code}'),
              _SummaryChip(label: '期數', value: '${plan.termCount}'),
              _SummaryChip(label: '手續費', value: '${_money(plan.totalFee)} ${plan.currency.code}'),
              _SummaryChip(label: '年利率', value: '${_money(plan.annualRate)}%'),
              _SummaryChip(label: '明細', value: '${items.length} 筆'),
              _SummaryChip(label: '來源交易', value: source),
            ]),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => onCancel(plan.id), icon: const Icon(Icons.cancel_outlined), label: Text(isSqlite ? '取消分期計畫' : '取消 Fake Plan'))),
          ]),
        ),
      ),
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

String _money(double value) => NumberFormat('#,##0.##').format(value);
