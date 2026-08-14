import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_settlement_panel.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement_presentation.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement_read_service.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement_reminder.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Taiwan calendar classification is deterministic', () {
    const clock = DebitCardSettlementPresentationClock();
    final settlement = _settlement(
      expected: DateTime.utc(2026, 7, 4, 1),
    );

    expect(
      clock.classify(settlement, now: DateTime.utc(2026, 7, 2, 15, 59)),
      DebitCardSettlementPresentationStatus.upcoming,
    );
    expect(
      clock.classify(settlement, now: DateTime.utc(2026, 7, 3, 16)),
      DebitCardSettlementPresentationStatus.due,
    );
    expect(
      clock.classify(settlement, now: DateTime.utc(2026, 7, 4, 16)),
      DebitCardSettlementPresentationStatus.overdue,
    );
  });

  test('terminal settlement is inactive and never becomes overdue', () {
    const clock = DebitCardSettlementPresentationClock();
    final pending = _settlement(expected: DateTime.utc(2026, 7, 1));
    final confirmed = pending.confirm(DateTime.utc(2026, 7, 2));

    expect(
      clock.classify(confirmed, now: DateTime.utc(2026, 7, 10)),
      DebitCardSettlementPresentationStatus.inactive,
    );
    expect(confirmed.status, DebitCardSettlementStatus.confirmed);
  });

  test('bank read model joins all pending linked-card settlements', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    await _insertAccount(db, id: 'bank-1', name: '薪轉銀行', type: 'bank');
    await _insertAccount(
      db,
      id: 'debit-1',
      name: '日常卡',
      type: 'debitCard',
    );
    await _insertAccount(
      db,
      id: 'debit-2',
      name: '交通卡',
      type: 'debitCard',
    );
    await _insertTransaction(
      db,
      id: 'tx-1',
      accountName: '日常卡',
      merchantName: '早餐店',
      amount: 120,
    );
    await _insertTransaction(
      db,
      id: 'tx-2',
      accountName: '交通卡',
      merchantName: '',
      category: '交通',
      amount: 50,
    );
    await _insertSettlement(
      db,
      id: 'settlement-1',
      debitCardAccountId: 'debit-1',
      transactionId: 'tx-1',
      amount: 120,
      expected: DateTime.utc(2026, 7, 4, 1),
    );
    await _insertSettlement(
      db,
      id: 'settlement-2',
      debitCardAccountId: 'debit-2',
      transactionId: 'tx-2',
      amount: 50,
      expected: DateTime.utc(2026, 7, 3, 1),
    );

    final service = DebitCardSettlementReadService(
      databaseProvider: () async => db,
    );
    const bank = AccountRecord(
      id: 'bank-1',
      name: '薪轉銀行',
      type: AccountType.bank,
      initialBalance: 0,
      sortOrder: 1,
    );
    final rows = await service.loadForAccount(
      bank,
      now: DateTime.utc(2026, 7, 3, 16),
    );

    expect(rows, hasLength(2));
    expect(rows.first.settlement.id, 'settlement-2');
    expect(rows.first.sourceTitle, '交通');
    expect(rows.first.status, DebitCardSettlementPresentationStatus.overdue);
    expect(rows.last.sourceTitle, '早餐店');
    expect(rows.last.status, DebitCardSettlementPresentationStatus.due);
  });

  test('missing source transaction fails closed', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    await _insertAccount(db, id: 'bank-1', name: '薪轉銀行', type: 'bank');
    await _insertAccount(
      db,
      id: 'debit-1',
      name: '日常卡',
      type: 'debitCard',
    );
    await _insertSettlement(
      db,
      id: 'settlement-1',
      debitCardAccountId: 'debit-1',
      transactionId: 'missing',
      amount: 120,
      expected: DateTime.utc(2026, 7, 4),
    );

    final service = DebitCardSettlementReadService(
      databaseProvider: () async => db,
    );

    await expectLater(
      service.loadAllPending(now: DateTime.utc(2026, 7, 3)),
      throwsA(isA<DebitCardSettlementReadException>()),
    );
  });

  test('reminder IDs are stable and reconciliation is idempotent', () async {
    final item = _presentation(
      settlement: _settlement(expected: DateTime.utc(2026, 7, 4, 1)),
      status: DebitCardSettlementPresentationStatus.due,
    );
    const planner = DebitCardSettlementReminderPlanner();
    final firstId = planner.notificationIdFor(item.settlement.id);
    final secondId = planner.notificationIdFor(item.settlement.id);
    final obsoleteId = planner.notificationIdFor('obsolete');
    expect(firstId, secondId);

    final port = _FakeReminderPort(<int>{obsoleteId});
    final service = DebitCardSettlementReminderReconciliationService(
      port: port,
    );
    await service.reconcile(
      settlements: <DebitCardSettlementPresentation>[item],
      now: DateTime.utc(2026, 7, 3, 16),
    );

    expect(port.cancelled, <int>[obsoleteId]);
    expect(port.scheduled, hasLength(1));
    expect(port.scheduled.single.notificationId, firstId);
    expect(port.scheduled.single.title, '今日預計扣款');

    port.cancelled.clear();
    port.scheduled.clear();
    port.pending = <int>{firstId};
    await service.reconcile(
      settlements: <DebitCardSettlementPresentation>[item],
      now: DateTime.utc(2026, 7, 3, 16),
    );
    expect(port.cancelled, isEmpty);
    expect(port.scheduled.single.notificationId, firstId);
  });

  testWidgets('panel shows due state and non-bank-confirmation boundary',
      (tester) async {
    final item = _presentation(
      settlement: _settlement(expected: DateTime.utc(2026, 7, 4, 1)),
      status: DebitCardSettlementPresentationStatus.due,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebitCardSettlementPanel(
            account: item.debitCardAccount,
            value: AsyncData<List<DebitCardSettlementPresentation>>(
              <DebitCardSettlementPresentation>[item],
            ),
          ),
        ),
      ),
    );

    expect(find.text('今日預計扣款'), findsOneWidget);
    expect(find.textContaining('App 依授權紀錄推算'), findsOneWidget);
    expect(find.textContaining('早餐店'), findsOneWidget);
    expect(find.textContaining('預計扣款日'), findsOneWidget);
  });
}

DebitCardPendingSettlement _settlement({required DateTime expected}) {
  return DebitCardPendingSettlement(
    id: 'settlement-1',
    debitCardAccountId: 'debit-1',
    linkedBankAccountId: 'bank-1',
    transactionId: 'tx-1',
    amount: 120,
    currency: CurrencyCode.twd,
    authorizedAt: DateTime.utc(2026, 7, 2),
    expectedSettlementDate: expected,
    status: DebitCardSettlementStatus.pending,
  );
}

DebitCardSettlementPresentation _presentation({
  required DebitCardPendingSettlement settlement,
  required DebitCardSettlementPresentationStatus status,
}) {
  const debit = AccountRecord(
    id: 'debit-1',
    name: '日常卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 1,
  );
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 0,
    sortOrder: 2,
  );
  final transaction = TransactionRecord(
    id: 'tx-1',
    type: TransactionType.expense,
    amount: 120,
    category: '餐飲',
    occurredAt: DateTime.utc(2026, 7, 2),
    accountName: debit.displayName,
    memberName: '自己',
    merchantName: '早餐店',
    tagName: '',
    note: '',
  );
  return DebitCardSettlementPresentation(
    settlement: settlement,
    debitCardAccount: debit,
    linkedBankAccount: bank,
    transaction: transaction,
    status: status,
  );
}

class _FakeReminderPort implements DebitCardSettlementReminderPort {
  _FakeReminderPort(this.pending);

  Set<int> pending;
  final List<int> cancelled = <int>[];
  final List<DebitCardSettlementReminderRequest> scheduled =
      <DebitCardSettlementReminderRequest>[];

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    pending.remove(notificationId);
  }

  @override
  Future<Set<int>> pendingReminderIds() async => Set<int>.from(pending);

  @override
  Future<void> schedule(DebitCardSettlementReminderRequest request) async {
    scheduled.add(request);
    pending.add(request.notificationId);
  }
}

Future<Database> _openDatabase() async {
  final db = await openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      suffix TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      account_name TEXT NOT NULL,
      member_name TEXT NOT NULL,
      merchant_name TEXT NOT NULL,
      tag_name TEXT NOT NULL,
      note TEXT NOT NULL,
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      exchange_rate_to_base REAL NOT NULL DEFAULT 1,
      from_account_name TEXT,
      to_account_name TEXT,
      repayment_group_id TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_card_settlements (
      id TEXT PRIMARY KEY,
      debit_card_account_id TEXT NOT NULL,
      linked_bank_account_id TEXT NOT NULL,
      transaction_id TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      authorized_at TEXT NOT NULL,
      expected_settlement_date TEXT NOT NULL,
      status TEXT NOT NULL,
      terminal_at TEXT,
      failure_reason TEXT,
      settlement_transfer_transaction_id TEXT
    )
  ''');
  return db;
}

Future<void> _insertAccount(
  Database db, {
  required String id,
  required String name,
  required String type,
}) async {
  await db.insert('accounts', <String, Object?>{
    'id': id,
    'name': name,
    'type': type,
    'initial_balance': 0,
    'sort_order': 0,
    'suffix': '',
    'currency_code': 'TWD',
    'is_archived': 0,
  });
}

Future<void> _insertTransaction(
  Database db, {
  required String id,
  required String accountName,
  required String merchantName,
  required double amount,
  String category = '餐飲',
}) async {
  await db.insert('transactions', <String, Object?>{
    'id': id,
    'type': 'expense',
    'amount': amount,
    'category': category,
    'occurred_at': DateTime.utc(2026, 7, 2).toIso8601String(),
    'account_name': accountName,
    'member_name': '自己',
    'merchant_name': merchantName,
    'tag_name': '',
    'note': '',
    'currency_code': 'TWD',
    'exchange_rate_to_base': 1,
  });
}

Future<void> _insertSettlement(
  Database db, {
  required String id,
  required String debitCardAccountId,
  required String transactionId,
  required double amount,
  required DateTime expected,
}) async {
  await db.insert('debit_card_settlements', <String, Object?>{
    'id': id,
    'debit_card_account_id': debitCardAccountId,
    'linked_bank_account_id': 'bank-1',
    'transaction_id': transactionId,
    'amount': amount,
    'currency_code': 'TWD',
    'authorized_at': DateTime.utc(2026, 7, 2).toIso8601String(),
    'expected_settlement_date': expected.toIso8601String(),
    'status': 'pending',
  });
}
