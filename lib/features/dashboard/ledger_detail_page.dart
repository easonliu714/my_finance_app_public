import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../transaction/transaction_entry_page.dart';
import '../transaction/transaction_providers.dart';
import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'dashboard_page.dart';

enum _LedgerPeriodMode { all, year, month }

class LedgerDetailPage extends ConsumerStatefulWidget {
  const LedgerDetailPage({super.key});

  static const routeName = 'ledger-detail';
  static const routePath = '/ledger';
  static const backHomeButtonKey = Key('ledger_detail_back_home_button');

  @override
  ConsumerState<LedgerDetailPage> createState() => _LedgerDetailPageState();
}

class _LedgerDetailPageState extends ConsumerState<LedgerDetailPage> {
  _LedgerPeriodMode _mode = _LedgerPeriodMode.month;
  DateTime _anchor = DateTime.now();
  final Set<String> _expandedMonths = <String>{};

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(transactionLedgerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('帳單明細'),
        actions: [
          IconButton(tooltip: '搜尋', onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(tooltip: '篩選', onPressed: () {}, icon: const Icon(Icons.filter_alt_outlined)),
        ],
      ),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('讀取明細失敗：$error')),
        data: (state) {
          final records = _filteredRecords(state.records);
          final total = _PeriodTotal.fromRecords(records);
          return RefreshIndicator(
            onRefresh: () => ref.read(transactionLedgerProvider.notifier).load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _ModeSelector(mode: _mode, onChanged: (mode) => setState(() => _mode = mode)),
                const SizedBox(height: 12),
                _PeriodNavigator(
                  mode: _mode,
                  anchor: _anchor,
                  onPrevious: () => setState(() => _anchor = _shiftAnchor(-1)),
                  onNext: () => setState(() => _anchor = _shiftAnchor(1)),
                ),
                const SizedBox(height: 12),
                _TotalCards(total: total, count: records.length),
                const SizedBox(height: 20),
                Text('帳單明細', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (records.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('此期間尚無記帳資料'))))
                else
                  ..._buildGroups(records),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: LedgerDetailPage.backHomeButtonKey,
        onPressed: () => context.goNamed(DashboardPage.routeName),
        icon: const Icon(Icons.home_outlined),
        label: const Text('回首頁'),
      ),
    );
  }

  DateTime _shiftAnchor(int delta) {
    switch (_mode) {
      case _LedgerPeriodMode.all:
        return _anchor;
      case _LedgerPeriodMode.year:
        return DateTime(_anchor.year + delta, 1);
      case _LedgerPeriodMode.month:
        return DateTime(_anchor.year, _anchor.month + delta);
    }
  }

  List<TransactionRecord> _filteredRecords(List<TransactionRecord> records) {
    switch (_mode) {
      case _LedgerPeriodMode.all:
        return [...records]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      case _LedgerPeriodMode.year:
        return records.where((record) => record.occurredAt.year == _anchor.year).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      case _LedgerPeriodMode.month:
        return records.where((record) => record.occurredAt.year == _anchor.year && record.occurredAt.month == _anchor.month).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    }
  }

  List<Widget> _buildGroups(List<TransactionRecord> records) {
    final currency = NumberFormat('#,##0.##');
    if (_mode == _LedgerPeriodMode.all || _mode == _LedgerPeriodMode.year) return _buildMonthGroups(records, currency);
    return _buildDayGroups(records, currency);
  }

  List<Widget> _buildMonthGroups(List<TransactionRecord> records, NumberFormat currency) {
    final byMonth = <DateTime, List<TransactionRecord>>{};
    for (final record in records) {
      final key = DateTime(record.occurredAt.year, record.occurredAt.month);
      byMonth.putIfAbsent(key, () => []).add(record);
    }
    final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys)
        _MonthTile(
          month: key,
          records: byMonth[key]!..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)),
          currency: currency,
          initiallyExpanded: _expandedMonths.contains('${key.year}-${key.month}'),
          onExpansionChanged: (expanded) => setState(() {
            final id = '${key.year}-${key.month}';
            expanded ? _expandedMonths.add(id) : _expandedMonths.remove(id);
          }),
        ),
    ];
  }

  List<Widget> _buildDayGroups(List<TransactionRecord> records, NumberFormat currency) {
    final byDay = <DateTime, List<TransactionRecord>>{};
    for (final record in records) {
      final key = DateTime(record.occurredAt.year, record.occurredAt.month, record.occurredAt.day);
      byDay.putIfAbsent(key, () => []).add(record);
    }
    final keys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys) _DaySection(day: key, records: byDay[key]!..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)), currency: currency),
    ];
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final _LedgerPeriodMode mode;
  final ValueChanged<_LedgerPeriodMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_LedgerPeriodMode>(
      segments: const [
        ButtonSegment(value: _LedgerPeriodMode.all, label: Text('全部')),
        ButtonSegment(value: _LedgerPeriodMode.year, label: Text('年')),
        ButtonSegment(value: _LedgerPeriodMode.month, label: Text('月')),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({required this.mode, required this.anchor, required this.onPrevious, required this.onNext});

  final _LedgerPeriodMode mode;
  final DateTime anchor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      _LedgerPeriodMode.all => '全部期間',
      _LedgerPeriodMode.year => '${anchor.year}',
      _LedgerPeriodMode.month => DateFormat('yyyy/MM').format(anchor),
    };
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton.filledTonal(onPressed: mode == _LedgerPeriodMode.all ? null : onPrevious, icon: const Icon(Icons.chevron_left)),
      const SizedBox(width: 16),
      Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(width: 16),
      IconButton.filledTonal(onPressed: mode == _LedgerPeriodMode.all ? null : onNext, icon: const Icon(Icons.chevron_right)),
    ]);
  }
}

class _TotalCards extends StatelessWidget {
  const _TotalCards({required this.total, required this.count});

  final _PeriodTotal total;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        _MetricCard(label: '結餘', value: _money(total.balance), emphasized: true),
        _MetricCard(label: '支出($count)', value: _money(total.expense)),
        _MetricCard(label: '收入', value: _money(total.income)),
      ]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          side: emphasized ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5) : BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.blueGrey)),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.month, required this.records, required this.currency, required this.initiallyExpanded, required this.onExpansionChanged});

  final DateTime month;
  final List<TransactionRecord> records;
  final NumberFormat currency;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final total = _PeriodTotal.fromRecords(records);
    return Card(
      child: ExpansionTile(
        key: PageStorageKey<String>('ledger-month-${month.year}-${month.month}'),
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        leading: CircleAvatar(child: Text('${month.month}月')),
        title: Text(DateFormat('yyyy/MM').format(month)),
        subtitle: Text('收 ${_money(total.income)} ｜ 支 ${_money(total.expense)}'),
        trailing: FittedBox(fit: BoxFit.scaleDown, child: Text(_money(total.balance), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        children: [for (final record in records) _TransactionTile(record: record, currency: currency)],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.records, required this.currency});

  final DateTime day;
  final List<TransactionRecord> records;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final total = _PeriodTotal.fromRecords(records);
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${DateFormat('MM/dd').format(day)} 週$weekday', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('收 ${_money(total.income)}  支 ${_money(total.expense)}', style: const TextStyle(color: Colors.blueGrey)),
          ]),
          const Divider(),
          for (final record in records) _TransactionTile(record: record, currency: currency),
        ]),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.record, required this.currency});

  final TransactionRecord record;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == TransactionType.income;
    final isExpense = record.type == TransactionType.expense;
    final sign = isIncome ? '+' : isExpense ? '-' : '';
    final time = DateFormat('HH:mm').format(record.occurredAt);
    final accountText = record.type == TransactionType.transfer ? '${record.fromAccountName ?? record.accountName} → ${record.toAccountName ?? ''}' : record.accountName;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.pushNamed(
        TransactionEntryPage.routeName,
        extra: record,
      ),
      leading: CircleAvatar(child: Icon(_iconFor(record.type))),
      title: Text(record.category),
      subtitle: Text('$time · $accountText · ${record.memberName} · ${record.merchantName}${record.note.isEmpty ? '' : ' · ${record.note}'}'),
      trailing: Text('$sign${currency.format(record.amount)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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

class _PeriodTotal {
  const _PeriodTotal({required this.income, required this.expense});

  final double income;
  final double expense;

  double get balance => income - expense;

  factory _PeriodTotal.fromRecords(List<TransactionRecord> records) {
    var income = 0.0;
    var expense = 0.0;
    for (final record in records) {
      if (record.type == TransactionType.income) income += record.amount;
      if (record.type == TransactionType.expense) expense += record.amount;
    }
    return _PeriodTotal(income: income, expense: expense);
  }
}

String _money(double value) => NumberFormat('#,##0.00').format(value);
