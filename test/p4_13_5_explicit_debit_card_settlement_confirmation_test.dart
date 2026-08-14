import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v19.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/account/debit_card_repository.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement_confirmation.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement_confirmation_service.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Schema V19 adds immutable settlement confirmation audits', () async {
    final db = await _openConfirmationDatabase();
    addTearDown(db.close);

    expect(canonicalProductionSchemaVersion, 19);
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    expect(tables, contains('debit_card_settlement_confirmation_audits'));
    final columns = (await db.rawQuery(
      'PRAGMA table_info(debit_card_settlement_confirmation_audits)',
    ))
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    expect(
      columns,
      containsAll(<String>{
        'request_id',
        'payload_fingerprint',
        'settlement_id',
        'transfer_transaction_id',
        'ledger_balance_before',
        'reserved_before',
        'available_before',
        'ledger_balance_after',
        'reserved_after',
        'available_after',
      }),
    );
  });

  test('confirmation atomically creates transfer, terminal state, and audit',
      () async {
    final db = await _openConfirmationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertAuthorizedPurchase(db, amount: 300);
    final service = DebitCardSettlementConfirmationService(
      databaseProvider: () async => db,
    );

    final receipt = await service.confirm(_request());

    expect(receipt.replayed, isFalse);
    expect(receipt.transferTransaction.type, TransactionType.transfer);
    expect(receipt.transferTransaction.fromAccountName, '薪轉銀行');
    expect(receipt.transferTransaction.toAccountName, '日常簽帳卡');
    expect(receipt.settlement.status, DebitCardSettlementStatus.confirmed);
    expect(
      receipt.settlement.settlementTransferTransactionId,
      'settlement-transfer-1',
    );
    expect(receipt.audit.ledgerBalanceBefore, 1000);
    expect(receipt.audit.reservedBefore, 300);
    expect(receipt.audit.availableBefore, 700);
    expect(receipt.audit.ledgerBalanceAfter, 700);
    expect(receipt.audit.reservedAfter, 0);
    expect(receipt.audit.availableAfter, 700);

    expect(await _count(db, 'transactions'), 2);
    expect(
      await _countWhere(db, 'transactions', 'type = ?', <Object?>['expense']),
      1,
      reason: 'Settlement confirmation must not recognize a second expense.',
    );
    expect(
      await _countWhere(db, 'transactions', 'type = ?', <Object?>['transfer']),
      1,
    );
    expect(
      await _count(db, 'debit_card_settlement_confirmation_audits'),
      1,
    );
  });

  test('failure after transfer insert rolls back every confirmation effect',
      () async {
    final db = await _openConfirmationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertAuthorizedPurchase(db, amount: 300);
    final service = DebitCardSettlementConfirmationService(
      databaseProvider: () async => db,
      writeStageHook: (stage) async {
        if (stage ==
            DebitCardSettlementConfirmationWriteStage.afterTransferInsert) {
          throw StateError('injected transfer failure');
        }
      },
    );

    await expectLater(service.confirm(_request()), throwsA(isA<StateError>()));

    expect(await _count(db, 'transactions'), 1);
    expect(
      (await db.query('debit_card_settlements')).single['status'],
      DebitCardSettlementStatus.pending.name,
    );
    expect(
      (await db.query('debit_card_settlements'))
          .single['settlement_transfer_transaction_id'],
      isNull,
    );
    expect(
      await _count(db, 'debit_card_settlement_confirmation_audits'),
      0,
    );
  });

  test('failure after settlement update rolls back transfer and status',
      () async {
    final db = await _openConfirmationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertAuthorizedPurchase(db, amount: 300);
    final service = DebitCardSettlementConfirmationService(
      databaseProvider: () async => db,
      writeStageHook: (stage) async {
        if (stage ==
            DebitCardSettlementConfirmationWriteStage.afterSettlementUpdate) {
          throw StateError('injected update failure');
        }
      },
    );

    await expectLater(service.confirm(_request()), throwsA(isA<StateError>()));

    expect(await _count(db, 'transactions'), 1);
    expect(
      (await db.query('debit_card_settlements')).single['status'],
      DebitCardSettlementStatus.pending.name,
    );
    expect(
      await _count(db, 'debit_card_settlement_confirmation_audits'),
      0,
    );
  });

  test('identical confirmation replay returns original receipt once', () async {
    final db = await _openConfirmationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertAuthorizedPurchase(db, amount: 300);
    final service = DebitCardSettlementConfirmationService(
      databaseProvider: () async => db,
    );
    final request = _request();

    final first = await service.confirm(request);
    final replay = await service.confirm(request);

    expect(first.replayed, isFalse);
    expect(replay.replayed, isTrue);
    expect(replay.transferTransaction.id, first.transferTransaction.id);
    expect(replay.settlement.terminalAt, first.settlement.terminalAt);
    expect(await _count(db, 'transactions'), 2);
    expect(
      await _count(db, 'debit_card_settlement_confirmation_audits'),
      1,
    );
  });

  test('same request key with changed transfer identity fails closed', () async {
    final db = await _openConfirmationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertAuthorizedPurchase(db, amount: 300);
    final service = DebitCardSettlementConfirmationService(
      databaseProvider: () async => db,
    );
    final original = _request();
    await service.confirm(original);

    final changed = DebitCardSettlementConfirmationRequest(
      requestId: original.requestId,
      settlementId: original.settlementId,
      transferTransactionId: 'different-transfer',
      confirmedAt: original.confirmedAt,
    );
    await expectLater(
      service.confirm(changed),
      throwsA(
        isA<DebitCardSettlementConfirmationException>().having(
          (error) => error.code,
          'code',
          DebitCardSettlementConfirmationErrorCode.replayConflict,
        ),
      ),
    );
    expect(await _count(db, 'transactions'), 2);
  });

  test('confirmed settlement transfer is immutable', () async {
    final db = await _openConfirmationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertAuthorizedPurchase(db, amount: 300);
    final service = DebitCardSettlementConfirmationService(
      databaseProvider: () async => db,
    );
    await service.confirm(_request());

    expect(await service.isConfirmedTransfer('settlement-transfer-1'), isTrue);
    await expectLater(
      service.requireMutableTransfer('settlement-transfer-1'),
      throwsA(
        isA<DebitCardSettlementConfirmationException>().having(
          (error) => error.code,
          'code',
          DebitCardSettlementConfirmationErrorCode.confirmedTransferImmutable,
        ),
      ),
    );
  });
}

DebitCardSettlementConfirmationRequest _request() {
  return DebitCardSettlementConfirmationRequest(
    requestId: 'confirmation-request-1',
    settlementId: 'settlement-1',
    transferTransactionId: 'settlement-transfer-1',
    confirmedAt: DateTime.utc(2026, 7, 4, 2),
  );
}

Future<Database> _openConfirmationDatabase({double bankBalance = 0}) async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
  );
  await _createCoreTables(db);
  await createCanonicalProductionV19Tables(db);
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 0,
    sortOrder: 10,
  );
  const debit = AccountRecord(
    id: 'debit-1',
    name: '日常簽帳卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 20,
  );
  await db.insert('accounts', bank.toMap());
  await db.insert('accounts', debit.toMap());
  await db.insert(
    'account_events',
    AccountEventRecord(
      id: 'initial-bank-1',
      accountId: bank.id,
      accountName: bank.displayName,
      eventType: 'initial_balance',
      amount: bankBalance,
      currency: CurrencyCode.twd,
      exchangeRateToBase: 1,
      occurredAt: DateTime.utc(2000),
      note: 'initial',
    ).toMap(),
  );
  await DebitCardRepository(db).upsertProfile(
    DebitCardAccountProfile.link(
      debitCardAccountId: debit.id,
      linkedBankAccount: bank,
      debitCardCurrency: CurrencyCode.twd,
    ),
  );
  return db;
}

Future<void> _insertAuthorizedPurchase(
  Database db, {
  required double amount,
}) async {
  final source = TransactionRecord(
    id: 'purchase-1',
    type: TransactionType.expense,
    amount: amount,
    category: '餐飲',
    occurredAt: DateTime.utc(2026, 7, 2),
    accountName: '日常簽帳卡',
    memberName: '自己',
    merchantName: '早餐店',
    tagName: '日常',
    note: '',
    currency: CurrencyCode.twd,
    exchangeRateToBase: 1,
  );
  final settlement = DebitCardPendingSettlement(
    id: 'settlement-1',
    debitCardAccountId: 'debit-1',
    linkedBankAccountId: 'bank-1',
    transactionId: source.id,
    amount: amount,
    currency: CurrencyCode.twd,
    authorizedAt: DateTime.utc(2026, 7, 2),
    expectedSettlementDate: DateTime.utc(2026, 7, 4),
    status: DebitCardSettlementStatus.pending,
  );
  await db.insert('transactions', source.toMap());
  await db.insert('debit_card_settlements', settlement.toMap());
}

Future<void> _createCoreTables(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      suffix TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      credit_limit REAL NOT NULL DEFAULT 0,
      statement_day INTEGER NOT NULL DEFAULT 1,
      payment_due_day INTEGER NOT NULL DEFAULT 1,
      payment_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_principal REAL NOT NULL DEFAULT 0,
      annual_interest_rate REAL NOT NULL DEFAULT 0,
      loan_term_months INTEGER NOT NULL DEFAULT 0,
      loan_repayment_method TEXT NOT NULL DEFAULT 'equalPrincipalAndInterest',
      loan_payment_due_day INTEGER NOT NULL DEFAULT 1,
      loan_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      loan_reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_start_date TEXT,
      loan_disbursement_account_name TEXT NOT NULL DEFAULT '',
      loan_handling_fee REAL NOT NULL DEFAULT 0,
      loan_disbursement_created INTEGER NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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
      base_amount REAL NOT NULL DEFAULT 0,
      from_account_name TEXT,
      to_account_name TEXT,
      repayment_group_id TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE account_events (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      account_name TEXT NOT NULL,
      event_type TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL DEFAULT 'TWD',
      exchange_rate_to_base REAL NOT NULL DEFAULT 1,
      base_amount REAL NOT NULL DEFAULT 0,
      occurred_at TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

Future<int> _count(Database db, String tableName) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
  return (rows.single['c'] as num).toInt();
}

Future<int> _countWhere(
  Database db,
  String tableName,
  String where,
  List<Object?> whereArgs,
) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM $tableName WHERE $where',
    whereArgs,
  );
  return (rows.single['c'] as num).toInt();
}
