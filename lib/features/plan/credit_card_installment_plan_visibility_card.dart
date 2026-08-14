import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../account/account_providers.dart';
import '../account/account_record.dart';
import 'credit_card_installment_providers.dart';
import 'credit_card_installment_repository.dart';

class CreditCardInstallmentPlanVisibilityCard extends ConsumerWidget {
  const CreditCardInstallmentPlanVisibilityCard({super.key, this.onOpenPreview});

  final VoidCallback? onOpenPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountListProvider);
    return accountsState.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (accounts) {
        final creditCards = accounts.where((account) => account.type == AccountType.creditCard && !account.isArchived).toList();
        if (creditCards.isEmpty) return const SizedBox.shrink();
        final repository = ref.watch(creditCardInstallmentRepositoryProvider);
        return FutureBuilder<List<_InstallmentPlanWithSchedule>>(
          future: _loadActivePlans(repository: repository, creditCards: creditCards),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <_InstallmentPlanWithSchedule>[];
            if (snapshot.connectionState != ConnectionState.done && items.isEmpty) {
              return const _InstallmentVisibilityShell(
                child: LinearProgressIndicator(),
              );
            }
            return _InstallmentVisibilityShell(
              child: _InstallmentVisibilityContent(items: items, onOpenPreview: onOpenPreview),
            );
          },
        );
      },
    );
  }
}

class _InstallmentVisibilityShell extends StatelessWidget {
  const _InstallmentVisibilityShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _InstallmentVisibilityContent extends StatelessWidget {
  const _InstallmentVisibilityContent({required this.items, required this.onOpenPreview});

  final List<_InstallmentPlanWithSchedule> items;
  final VoidCallback? onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalPrincipal = items.fold<double>(0, (sum, item) => sum + item.plan.principal * item.plan.currency.defaultRateToTwd);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: items.isEmpty ? null : () => _showInstallmentPlanSheet(context, items),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(Icons.splitscreen_outlined, size: 18, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '信用卡分期',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Chip(label: Text('${items.length} 筆 active')),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('尚無 active 分期計畫。', style: Theme.of(context).textTheme.bodySmall)
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('總本金 ${_money(totalPrincipal)} TWD')),
                Chip(label: Text('最近 ${DateFormat('MM/dd').format(items.first.plan.createdAt)}')),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in items.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${item.plan.cardNameSnapshot}・${_money(item.plan.principal)} ${item.plan.currency.code}・${item.plan.termCount} 期',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onOpenPreview != null)
                TextButton.icon(
                  onPressed: onOpenPreview,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('分期試算'),
                ),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _showInstallmentPlanSheet(context, items),
                  child: const Text('查看明細'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showInstallmentPlanSheet(BuildContext context, List<_InstallmentPlanWithSchedule> items) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text('信用卡分期計畫', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('此區顯示已保存的 active 分期計畫；建立分期不會直接產生付款交易、帳單快照或帳戶餘額異動。'),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text('尚無 active 分期計畫。')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('卡片')),
                      DataColumn(label: Text('本金')),
                      DataColumn(label: Text('期數')),
                      DataColumn(label: Text('期別')),
                      DataColumn(label: Text('狀態')),
                    ],
                    rows: [
                      for (final item in items)
                        DataRow(cells: [
                          DataCell(Text(item.plan.cardNameSnapshot)),
                          DataCell(Text('${_money(item.plan.principal)} ${item.plan.currency.code}')),
                          DataCell(Text('${item.plan.termCount}')),
                          DataCell(Text('${item.scheduleItems.length}')),
                          DataCell(Text(item.plan.status.name)),
                        ]),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallmentPlanWithSchedule {
  const _InstallmentPlanWithSchedule({required this.plan, required this.scheduleItems});

  final InstallmentPlanRecord plan;
  final List<InstallmentScheduleItemRecord> scheduleItems;
}

Future<List<_InstallmentPlanWithSchedule>> _loadActivePlans({
  required CreditCardInstallmentRepository repository,
  required List<AccountRecord> creditCards,
}) async {
  final result = <_InstallmentPlanWithSchedule>[];
  for (final card in creditCards) {
    final plans = await repository.loadPlansByCardId(card.id, status: InstallmentPlanStatus.active);
    for (final plan in plans) {
      final scheduleItems = await repository.loadScheduleItems(plan.id);
      result.add(_InstallmentPlanWithSchedule(plan: plan, scheduleItems: scheduleItems));
    }
  }
  result.sort((a, b) => b.plan.createdAt.compareTo(a.plan.createdAt));
  return List<_InstallmentPlanWithSchedule>.unmodifiable(result);
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
