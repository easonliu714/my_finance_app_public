import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../account/account_record.dart';
import 'credit_card_installment_providers.dart';

final creditCardInstallmentDebugSnapshotProvider = FutureProvider.autoDispose.family<InstallmentDebugSnapshot, String>((ref, cardId) async {
  final databaseProvider = ref.watch(creditCardInstallmentDebugDatabaseProvider);
  final db = await databaseProvider();
  return InstallmentDebugSnapshot.load(db, cardId: cardId);
});

class InstallmentDebugSnapshot {
  const InstallmentDebugSnapshot({
    required this.cardId,
    required this.activePlanCount,
    required this.cancelledPlanCount,
    required this.scheduleItemCount,
    required this.transactionCount,
    required this.statementEventCount,
    required this.accountCount,
    required this.accountEventCount,
    this.latestPlanId = '',
  });

  final String cardId;
  final int activePlanCount;
  final int cancelledPlanCount;
  final int scheduleItemCount;
  final int transactionCount;
  final int statementEventCount;
  final int accountCount;
  final int accountEventCount;
  final String latestPlanId;

  bool get hasInstallmentRows => activePlanCount > 0 || cancelledPlanCount > 0 || scheduleItemCount > 0;

  bool get hasSideEffectRows => transactionCount > 0 || statementEventCount > 0 || accountEventCount > 0;

  static Future<InstallmentDebugSnapshot> load(Database db, {required String cardId}) async {
    final activePlanCount = await _countWhere(db, 'credit_card_installment_plans', 'card_id = ? AND status = ?', <Object?>[cardId, 'active']);
    final cancelledPlanCount = await _countWhere(db, 'credit_card_installment_plans', 'card_id = ? AND status = ?', <Object?>[cardId, 'cancelled']);
    final scheduleItemCount = await _countScheduleItemsForCard(db, cardId);
    final latestPlanId = await _latestPlanIdForCard(db, cardId);
    return InstallmentDebugSnapshot(
      cardId: cardId,
      activePlanCount: activePlanCount,
      cancelledPlanCount: cancelledPlanCount,
      scheduleItemCount: scheduleItemCount,
      transactionCount: await _countAll(db, 'transactions'),
      statementEventCount: await _countAll(db, 'credit_card_statement_events'),
      accountCount: await _countAll(db, 'accounts'),
      accountEventCount: await _countAll(db, 'account_events'),
      latestPlanId: latestPlanId,
    );
  }

  static Future<int> _countAll(Database db, String tableName) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $tableName');
      return _intValue(rows.first['total']);
    } on DatabaseException {
      return 0;
    }
  }

  static Future<int> _countWhere(Database db, String tableName, String where, List<Object?> whereArgs) async {
    try {
      final rows = await db.query(tableName, columns: const <String>['COUNT(*) AS total'], where: where, whereArgs: whereArgs);
      return _intValue(rows.first['total']);
    } on DatabaseException {
      return 0;
    }
  }

  static Future<int> _countScheduleItemsForCard(Database db, String cardId) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COUNT(i.id) AS total
        FROM credit_card_installment_schedule_items i
        JOIN credit_card_installment_plans p ON p.id = i.plan_id
        WHERE p.card_id = ?
        ''',
        <Object?>[cardId],
      );
      return _intValue(rows.first['total']);
    } on DatabaseException {
      return 0;
    }
  }

  static Future<String> _latestPlanIdForCard(Database db, String cardId) async {
    try {
      final rows = await db.query(
        'credit_card_installment_plans',
        columns: const <String>['id'],
        where: 'card_id = ?',
        whereArgs: <Object?>[cardId],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      return rows.isEmpty ? '' : rows.first['id'] as String? ?? '';
    } on DatabaseException {
      return '';
    }
  }
}

class InstallmentDebugDataCheckCard extends ConsumerWidget {
  const InstallmentDebugDataCheckCard({super.key, required this.selectedCard});

  final AccountRecord selectedCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(creditCardInstallmentDebugSnapshotProvider(selectedCard.id));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.fact_check_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text('Debug SQLite 資料檢查', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: '重新檢查',
              onPressed: () => ref.invalidate(creditCardInstallmentDebugSnapshotProvider(selectedCard.id)),
              icon: const Icon(Icons.refresh_outlined),
            ),
          ]),
          const SizedBox(height: 8),
          Text('用於 P2.28.19 手機測試：確認建立/取消 Debug SQLite Plan 只影響分期表，不應新增交易流水、帳單快照或帳戶事件。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          snapshot.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text('讀取 SQLite 檢查資料失敗：$error', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
            data: (data) => _DebugSnapshotBody(snapshot: data),
          ),
        ]),
      ),
    );
  }
}

class _DebugSnapshotBody extends StatelessWidget {
  const _DebugSnapshotBody({required this.snapshot});

  final InstallmentDebugSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final warningStyle = TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w800);
    final okStyle = TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _DebugMetricChip(label: 'Active Plans', value: '${snapshot.activePlanCount}'),
        _DebugMetricChip(label: 'Cancelled Plans', value: '${snapshot.cancelledPlanCount}'),
        _DebugMetricChip(label: 'Schedule Items', value: '${snapshot.scheduleItemCount}'),
        _DebugMetricChip(label: 'Transactions', value: '${snapshot.transactionCount}', highlight: snapshot.transactionCount > 0),
        _DebugMetricChip(label: 'Statement Events', value: '${snapshot.statementEventCount}', highlight: snapshot.statementEventCount > 0),
        _DebugMetricChip(label: 'Account Events', value: '${snapshot.accountEventCount}', highlight: snapshot.accountEventCount > 0),
        _DebugMetricChip(label: 'Accounts', value: '${snapshot.accountCount}'),
      ]),
      const SizedBox(height: 10),
      if (snapshot.latestPlanId.isNotEmpty) Text('Latest Plan：${snapshot.latestPlanId}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Text(snapshot.hasSideEffectRows ? '警示：偵測到交易/帳單/帳戶事件資料，測試時需確認是否為既有資料或非分期流程新增。' : '通過：目前未偵測到交易、帳單快照或帳戶事件資料。', style: snapshot.hasSideEffectRows ? warningStyle : okStyle),
    ]);
  }
}

class _DebugMetricChip extends StatelessWidget {
  const _DebugMetricChip({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Theme.of(context).colorScheme.errorContainer : null;
    return Chip(backgroundColor: color, label: Text('$label：$value'));
  }
}

int _intValue(Object? value) => value is num ? value.toInt() : 0;
