import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../account/account_page.dart';
import '../invoice/invoice_capture_page.dart';
import '../plan/credit_card_installment_payment_link.dart';
import '../plan/plan_payment_entry_flow.dart';
import '../plan/repayment_plan_page.dart';
import '../product/product_capture_page.dart';
import '../profile/my_page.dart';
import '../transaction/transaction_entry_page.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'ledger_detail_page.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  static const routeName = 'dashboard';

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DateTime _summaryMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<DateTime, GlobalKey> _dayGroupKeys = <DateTime, GlobalKey>{};
  bool _visibleMonthUpdateQueued = false;

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(transactionLedgerProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(transactionLedgerProvider.notifier).load(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final state = ledger.valueOrNull;
            if (state == null || state.records.isEmpty || notification.metrics.axis != Axis.vertical) return false;
            _queueVisibleMonthUpdate();
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                pinned: true,
                title: const Text('日常帳本'),
                expandedHeight: 260,
                actions: [IconButton(tooltip: '搜尋', onPressed: () {}, icon: const Icon(Icons.search)), IconButton(tooltip: '設定', onPressed: () {}, icon: const Icon(Icons.more_horiz))],
                flexibleSpace: FlexibleSpaceBar(
                  background: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 96, 16, 12),
                      child: ledger.when(data: (state) => _MonthlySummaryCard(total: _monthTotal(state.records, DateTime.now()), label: '本月'), loading: () => const _MonthlySummarySkeleton(), error: (error, stackTrace) => _ErrorCard(message: '讀取帳本失敗：$error')),
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    alignment: Alignment.centerLeft,
                    child: ledger.when(
                      data: (state) {
                        final month = state.records.isEmpty ? DateTime.now() : _summaryMonth;
                        final total = _monthTotal(state.records, month);
                        return Text('${DateFormat('yyyy/MM').format(month)}：收 ${_money(total.income)} ｜ 支 ${_money(total.expense)} ｜ 結 ${_money(total.balance)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800));
                      },
                      loading: () => const Text('月份帳本讀取中...'),
                      error: (error, stackTrace) => const Text('月份帳本讀取失敗'),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList.list(
                  children: [
                    const _QuickActionsCard(),
                    const SizedBox(height: 16),
                    const _BudgetCard(),
                    const SizedBox(height: 16),
                    ledger.when(
                      data: (state) {
                        final groups = _buildDayGroups(state.records);
                        _syncDayGroupKeys(groups);
                        _queueVisibleMonthUpdate();
                        return _DailyRecordListCard(records: state.records, dayGroupKeys: _dayGroupKeys, onEdit: _openEditPage, onDuplicate: _duplicateRecord, onDelete: _deleteRecord);
                      },
                      loading: () => const _LoadingLedgerCard(),
                      error: (error, stackTrace) => _ErrorCard(message: '讀取日常紀錄失敗：$error'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(tooltip: '新增記帳', onPressed: () => context.pushNamed(TransactionEntryPage.routeName), child: const Icon(Icons.add, size: 30)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: 2,
        onDestinationSelected: (index) {
          if (index == 0) context.pushNamed(AccountPage.routeName);
          if (index == 1) context.pushNamed(RepaymentPlanPage.routeName);
          if (index == 3) context.pushNamed(LedgerDetailPage.routeName);
          if (index == 4) context.pushNamed(MyPage.routeName);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: '帳戶'),
          NavigationDestination(icon: Icon(Icons.check_box_outlined), label: '計劃'),
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首頁'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: '報表'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }

  void _syncDayGroupKeys(List<_DayGroup> groups) {
    final days = groups.map((group) => group.day).toSet();
    _dayGroupKeys.removeWhere((day, _) => !days.contains(day));
    for (final day in days) {
      _dayGroupKeys.putIfAbsent(day, GlobalKey.new);
    }
  }

  void _queueVisibleMonthUpdate() {
    if (_visibleMonthUpdateQueued) return;
    _visibleMonthUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleMonthUpdateQueued = false;
      if (!mounted) return;
      final nextMonth = _visibleMonthFromRenderedDayGroups();
      if (nextMonth == null) return;
      if (nextMonth.year != _summaryMonth.year || nextMonth.month != _summaryMonth.month) {
        setState(() => _summaryMonth = nextMonth);
      }
    });
  }

  DateTime? _visibleMonthFromRenderedDayGroups() {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final stickyBottomY = MediaQuery.paddingOf(context).top + kToolbarHeight + 44;
    DateTime? nearestDay;
    double nearestDistance = double.infinity;

    for (final entry in _dayGroupKeys.entries) {
      final keyContext = entry.value.currentContext;
      if (keyContext == null) continue;
      final renderObject = keyContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      if (bottom >= stickyBottomY && top <= screenHeight) return DateTime(entry.key.year, entry.key.month);
      final distance = (bottom < stickyBottomY) ? stickyBottomY - bottom : top - screenHeight;
      if (distance >= 0 && distance < nearestDistance) {
        nearestDistance = distance;
        nearestDay = entry.key;
      }
    }

    if (nearestDay == null) return null;
    return DateTime(nearestDay.year, nearestDay.month);
  }

  Future<void> _duplicateRecord(TransactionRecord record) async {
    if (_isLoanRepaymentCandidate(record)) {
      final ok = await _confirmRepaymentAction('還款群組包含本金與利息兩筆紀錄；目前不建議從日常紀錄複製，請使用計劃頁的本期還款建立新還款。');
      if (!ok || !mounted) return;
      return;
    }
    await ref.read(transactionLedgerProvider.notifier).duplicate(record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製一筆記帳')));
  }

  Future<void> _deleteRecord(TransactionRecord record) async {
    final installmentPaymentLink = parseCreditCardInstallmentPaymentLink(record);
    if (installmentPaymentLink != null) {
      final ok = await _confirmRepaymentAction('刪除這筆信用卡分期繳款後，會同步把該期分期狀態回復為未繳，是否確認？');
      if (!ok || !mounted) return;
      await ref.read(transactionLedgerProvider.notifier).delete(record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除分期繳款，並回復該期未繳狀態')));
      return;
    }
    final linkedInstallmentPreview = await ref.read(transactionLedgerProvider.notifier).previewLinkedInstallmentSourceDeletion(record.id);
    if (!mounted) return;
    if (linkedInstallmentPreview.isBlocked) {
      await _showInfoDialog('無法刪除', '這筆信用卡消費已建立分期，且已有還款紀錄，不能直接刪除。請先從分期明細撤銷繳款，或保留原消費紀錄。');
      return;
    }
    if (linkedInstallmentPreview.canDeleteWithPlanCancel) {
      final label = linkedInstallmentPreview.planLabel ?? '信用卡分期計畫';
      final ok = await _confirmRepaymentAction('這筆信用卡消費已建立 $label。刪除原消費時會一併取消尚未執行的分期計畫與期別，是否確認？');
      if (!ok || !mounted) return;
      await ref.read(transactionLedgerProvider.notifier).delete(record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除原消費，並一併取消尚未執行的分期計畫')));
      return;
    }
    if (_isLoanRepaymentCandidate(record)) {
      final ok = await _confirmRepaymentAction('此筆屬於同一組還款事件。刪除後會同步刪除同組本金還本與利息支出，並影響貸款本金餘額，是否確認？');
      if (!ok || !mounted) return;
      await ref.read(transactionLedgerProvider.notifier).deleteLoanRepaymentCluster(record);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除同組還款記帳')));
      return;
    }
    await ref.read(transactionLedgerProvider.notifier).delete(record.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除記帳')));
  }

  Future<bool> _confirmRepaymentAction(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('請確認'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('確認')),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _showInfoDialog(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('知道了'))],
      ),
    );
  }

  bool _isLoanRepaymentCandidate(TransactionRecord record) {
    if (record.isLoanRepayment) return true;
    final hasPeriod = RegExp(r'第\s*\d+\s*期').hasMatch(record.note);
    if (!hasPeriod || record.tagName != '還款') return false;
    final isPrincipal = record.type == TransactionType.loan && record.category == '還本';
    final isInterest = record.type == TransactionType.expense && record.category == '利息支出';
    return isPrincipal || isInterest;
  }

  void _openEditPage(TransactionRecord record) {
    context.pushNamed(TransactionEntryPage.routeName, extra: record);
  }
}

class _MonthlySummaryCard extends StatelessWidget {
  const _MonthlySummaryCard({required this.total, required this.label});

  final _PeriodTotal total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$label支出', style: textTheme.bodyLarge), const SizedBox(height: 4), FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(_money(total.expense), style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800))), const SizedBox(height: 4), Text('收入 ${_money(total.income)} ｜ 結餘 ${_money(total.balance)}')])));
  }
}

class _MonthlySummarySkeleton extends StatelessWidget {
  const _MonthlySummarySkeleton();
  @override
  Widget build(BuildContext context) => const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('正在讀取本月帳本...')));
}

class _QuickActionsCard extends ConsumerWidget {
  const _QuickActionsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            const _QuickAction(icon: Icons.flash_on, label: '速記'),
            _QuickAction(icon: Icons.receipt_long, label: '發票', onTap: () => context.pushNamed(InvoiceCapturePage.routeName)),
            _QuickAction(icon: Icons.shopping_bag_outlined, label: '商品', onTap: () => context.pushNamed(ProductCapturePage.routeName)),
            _QuickAction(icon: Icons.payments_outlined, label: '還款', onTap: () => openPlanPaymentEntryFlow(context, ref)),
            _QuickAction(icon: Icons.grid_view, label: '全部', onTap: () => context.pushNamed(LedgerDetailPage.routeName)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 8), Text(label)])));
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();
  @override
  Widget build(BuildContext context) => const Card(child: Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('支出月預算', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), Text('去設定')]), SizedBox(height: 12), LinearProgressIndicator(value: 0), SizedBox(height: 8), Text('節制使我更富足')])));
}

class _DailyRecordListCard extends StatelessWidget {
  const _DailyRecordListCard({required this.records, required this.dayGroupKeys, required this.onEdit, required this.onDuplicate, required this.onDelete});
  final List<TransactionRecord> records;
  final Map<DateTime, GlobalKey> dayGroupKeys;
  final ValueChanged<TransactionRecord> onEdit;
  final ValueChanged<TransactionRecord> onDuplicate;
  final ValueChanged<TransactionRecord> onDelete;
  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('尚無記帳資料。點擊下方 + 開始新增第一筆交易。'))));
    final currency = NumberFormat('#,##0.##');
    final dayGroups = _buildDayGroups(records);
    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('日常紀錄', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8), for (final group in dayGroups) _DayRecordGroup(key: dayGroupKeys[group.day], group: group, currency: currency, onEdit: onEdit, onDuplicate: onDuplicate, onDelete: onDelete)])));
  }
}

class _DayRecordGroup extends StatelessWidget {
  const _DayRecordGroup({super.key, required this.group, required this.currency, required this.onEdit, required this.onDuplicate, required this.onDelete});
  final _DayGroup group;
  final NumberFormat currency;
  final ValueChanged<TransactionRecord> onEdit;
  final ValueChanged<TransactionRecord> onDuplicate;
  final ValueChanged<TransactionRecord> onDelete;
  @override
  Widget build(BuildContext context) {
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'][group.day.weekday - 1];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Row(children: [Text('${DateFormat('MM/dd').format(group.day)} 週$weekday', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.blueGrey, fontWeight: FontWeight.w700)), const Spacer(), Text('收 ${_money(group.total.income)}  支 ${_money(group.total.expense)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.blueGrey))])), for (final record in group.records) _SwipeTransactionTile(record: record, currency: currency, onEdit: onEdit, onDuplicate: onDuplicate, onDelete: onDelete), const Divider(height: 8)]);
  }
}

class _SwipeTransactionTile extends StatefulWidget {
  const _SwipeTransactionTile({required this.record, required this.currency, required this.onEdit, required this.onDuplicate, required this.onDelete});
  final TransactionRecord record;
  final NumberFormat currency;
  final ValueChanged<TransactionRecord> onEdit;
  final ValueChanged<TransactionRecord> onDuplicate;
  final ValueChanged<TransactionRecord> onDelete;

  @override
  State<_SwipeTransactionTile> createState() => _SwipeTransactionTileState();
}

class _SwipeTransactionTileState extends State<_SwipeTransactionTile> {
  static const double _actionWidth = 216;
  double _dragOffset = 0;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final offset = _revealed ? -_actionWidth : _dragOffset;
    return ClipRect(
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          SizedBox(
            height: 76,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _InlineSwipeAction(icon: Icons.edit_outlined, label: '編輯', color: Theme.of(context).colorScheme.primary, onTap: () => _runAction(widget.onEdit)),
                _InlineSwipeAction(icon: Icons.copy_outlined, label: '複製', color: Colors.blueGrey, onTap: () => _runAction(widget.onDuplicate)),
                _InlineSwipeAction(icon: Icons.delete_outline, label: '刪除', color: Theme.of(context).colorScheme.error, onTap: () => _runAction(widget.onDelete)),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _revealed ? _hideActions : null,
              onHorizontalDragUpdate: (details) {
                final next = (_dragOffset + details.delta.dx).clamp(-_actionWidth, 0.0);
                setState(() => _dragOffset = next);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _revealed = _dragOffset.abs() > _actionWidth * 0.35;
                  _dragOffset = 0;
                });
              },
              child: ColoredBox(color: Theme.of(context).cardColor, child: _TransactionListTile(record: widget.record, currency: widget.currency)),
            ),
          ),
        ],
      ),
    );
  }

  void _hideActions() {
    setState(() {
      _revealed = false;
      _dragOffset = 0;
    });
  }

  void _runAction(ValueChanged<TransactionRecord> action) {
    _hideActions();
    action(widget.record);
  }
}

class _InlineSwipeAction extends StatelessWidget {
  const _InlineSwipeAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: color, padding: EdgeInsets.zero),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 20), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 12))]),
      ),
    );
  }
}

class _TransactionListTile extends StatelessWidget {
  const _TransactionListTile({required this.record, required this.currency});
  final TransactionRecord record;
  final NumberFormat currency;
  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == TransactionType.income;
    final isExpense = record.type == TransactionType.expense;
    final sign = isIncome || record.type == TransactionType.loan ? '+' : isExpense ? '-' : '';
    final color = isIncome ? Colors.deepOrange : Theme.of(context).colorScheme.onSurface;
    final time = DateFormat('HH:mm').format(record.occurredAt);
    final accountText = record.type == TransactionType.transfer ? '${record.fromAccountName ?? record.accountName} → ${record.toAccountName ?? ''}' : record.accountName;
    final subtitleParts = <String>[time, accountText, record.memberName];
    final merchant = record.merchantName.trim();
    if (merchant.isNotEmpty && merchant != '不使用商家') {
      subtitleParts.add(merchant);
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(_iconFor(record.type))),
      title: Text(record.category),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '$sign${currency.format(record.amount)}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
      ),
    );
  }

  IconData _iconFor(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return Icons.savings_outlined;
      case TransactionType.expense:
        return Icons.receipt_long_outlined;
      case TransactionType.transfer:
        return Icons.swap_horiz;
      case TransactionType.loan:
        return Icons.account_balance_wallet_outlined;
    }
  }
}

class _DayGroup {
  const _DayGroup({required this.day, required this.records, required this.total});
  final DateTime day;
  final List<TransactionRecord> records;
  final _PeriodTotal total;
}

class _PeriodTotal {
  const _PeriodTotal({required this.income, required this.expense});
  final double income;
  final double expense;
  double get balance => income - expense;
  factory _PeriodTotal.fromRecords(List<TransactionRecord> records, {bool useBaseAmount = false}) {
    var income = 0.0;
    var expense = 0.0;
    for (final record in records) {
      final value = useBaseAmount ? record.baseAmount : record.amount;
      if (record.type == TransactionType.income) income += value;
      if (record.type == TransactionType.expense) expense += value;
    }
    return _PeriodTotal(income: income, expense: expense);
  }
}

class _LoadingLedgerCard extends StatelessWidget {
  const _LoadingLedgerCard();
  @override
  Widget build(BuildContext context) => const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(message)));
}

List<_DayGroup> _buildDayGroups(List<TransactionRecord> records) {
  final byDay = <DateTime, List<TransactionRecord>>{};
  for (final record in records) {
    final day = DateTime(record.occurredAt.year, record.occurredAt.month, record.occurredAt.day);
    byDay.putIfAbsent(day, () => []).add(record);
  }
  final groups = byDay.entries.map((entry) {
    final dayRecords = [...entry.value]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return _DayGroup(day: entry.key, records: dayRecords, total: _PeriodTotal.fromRecords(dayRecords));
  }).toList();
  groups.sort((a, b) => b.day.compareTo(a.day));
  return groups;
}

_PeriodTotal _monthTotal(List<TransactionRecord> records, DateTime month) => _PeriodTotal.fromRecords(records.where((record) => record.occurredAt.year == month.year && record.occurredAt.month == month.month).toList(), useBaseAmount: true);
String _money(double value) => NumberFormat('#,##0.##').format(value);
