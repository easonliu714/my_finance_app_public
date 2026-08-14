import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v18.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/account/debit_card_repository.dart';
import 'package:my_finance_app/features/transaction/debit_card_purchase_authorization.dart';
import 'package:my_finance_app/features/transaction/debit_card_purchase_authorization_service.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Schema V18 adds immutable authorization audit storage', () async {
    final db = await _openAuthorizationDatabase();
    addTearDown(db.close);

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    expect(canonicalProductionSchemaVersion, 18);
    expect(tables, contains('debit_card_authorization_audits'));
    final columns = (await db.rawQuery(
      'PRAGMA table_info(debit_card_authorization_audits)',
    ))
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    expect(
      columns,
      containsAll(<String>{
        'request_id',
        'payload_fingerprint',
        'transaction_id',
        'settlement_id',
        'available_before',
        'available_after',
      }),
    );
  });

  test('sufficient funds atomically persist expense settlement and audit', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
    );
    final request = _request(amount: 300);

    final receipt = await service.authorize(request);

    expect(receipt.replayed, isFalse);
    expect(receipt.audit.ledgerBalanceBefore, 1000);
    expect(receipt.audit.reservedBefore, 0);
    expect(receipt.audit.availableBefore, 1000);
    expect(receipt.audit.availableAfter, 700);
    expect(await _count(db, 'transactions'), 1);
    expect(await _count(db, 'debit_card_settlements'), 1);
    expect(await _count(db, 'debit_card_authorization_audits'), 1);
    expect(
      (await db.query('debit_card_settlements')).single['status'],
      DebitCardSettlementStatus.pending.name,
    );
  });

  test('insufficient funds write no financial or audit rows', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 250);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
    );

    await expectLater(
      service.authorize(_request(amount: 300)),
      throwsA(
        isA<DebitCardPurchaseAuthorizationException>()
            .having(
              (error) => error.code,
              'code',
              DebitCardPurchaseAuthorizationErrorCode
                  .insufficientAvailableBalance,
            )
            .having(
              (error) => error.availableBalance,
              'availableBalance',
              250,
            ),
      ),
    );

    expect(await _count(db, 'transactions'), 0);
    expect(await _count(db, 'debit_card_settlements'), 0);
    expect(await _count(db, 'debit_card_authorization_audits'), 0);
  });

  test('failure after transaction insert rolls back every success row', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
      writeStageHook: (stage) async {
        if (stage == DebitCardAuthorizationWriteStage.afterTransactionInsert) {
          throw StateError('injected failure');
        }
      },
    );

    await expectLater(
      service.authorize(_request(amount: 100)),
      throwsA(isA<StateError>()),
    );

    expect(await _count(db, 'transactions'), 0);
    expect(await _count(db, 'debit_card_settlements'), 0);
    expect(await _count(db, 'debit_card_authorization_audits'), 0);
  });

  test('failure after settlement insert rolls back every success row', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
      writeStageHook: (stage) async {
        if (stage == DebitCardAuthorizationWriteStage.afterSettlementInsert) {
          throw StateError('injected failure');
        }
      },
    );

    await expectLater(
      service.authorize(_request(amount: 100)),
      throwsA(isA<StateError>()),
    );

    expect(await _count(db, 'transactions'), 0);
    expect(await _count(db, 'debit_card_settlements'), 0);
    expect(await _count(db, 'debit_card_authorization_audits'), 0);
  });

  test('shared-bank pending reservations participate in final check', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    await _insertSecondDebitCardReservation(db, amount: 800);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
    );

    await expectLater(
      service.authorize(_request(amount: 250)),
      throwsA(
        isA<DebitCardPurchaseAuthorizationException>()
            .having(
              (error) => error.code,
              'code',
              DebitCardPurchaseAuthorizationErrorCode
                  .insufficientAvailableBalance,
            )
            .having(
              (error) => error.availableBalance,
              'availableBalance',
              200,
            ),
      ),
    );

    expect(await _count(db, 'transactions'), 1);
    expect(await _count(db, 'debit_card_settlements'), 1);
    expect(await _count(db, 'debit_card_authorization_audits'), 0);
  });

  test('same request and payload replay returns original receipt once', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
    );
    final firstRequest = _request(amount: 300);
    final replayRequest = DebitCardPurchaseAuthorizationRequest(
      requestId: firstRequest.requestId,
      settlementId: firstRequest.settlementId,
      debitCardAccountId: firstRequest.debitCardAccountId,
      transaction: firstRequest.transaction,
      requestedAt: firstRequest.requestedAt.add(const Duration(minutes: 5)),
    );

    final first = await service.authorize(firstRequest);
    final replay = await service.authorize(replayRequest);

    expect(first.replayed, isFalse);
    expect(replay.replayed, isTrue);
    expect(replay.audit.requestId, first.audit.requestId);
    expect(replay.settlement.id, first.settlement.id);
    expect(replay.settlement.authorizedAt, first.settlement.authorizedAt);
    expect(await _count(db, 'transactions'), 1);
    expect(await _count(db, 'debit_card_settlements'), 1);
    expect(await _count(db, 'debit_card_authorization_audits'), 1);
  });

  test('same request key with changed payload fails closed', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
    );
    final original = _request(amount: 300);
    await service.authorize(original);
    final changed = DebitCardPurchaseAuthorizationRequest(
      requestId: original.requestId,
      settlementId: original.settlementId,
      debitCardAccountId: original.debitCardAccountId,
      transaction: original.transaction.copyWith(amount: 301),
      requestedAt: original.requestedAt,
    );

    await expectLater(
      service.authorize(changed),
      throwsA(
        isA<DebitCardPurchaseAuthorizationException>().having(
          (error) => error.code,
          'code',
          DebitCardPurchaseAuthorizationErrorCode.replayConflict,
        ),
      ),
    );

    expect(await _count(db, 'transactions'), 1);
    expect(await _count(db, 'debit_card_settlements'), 1);
    expect(await _count(db, 'debit_card_authorization_audits'), 1);
  });

  test('authorized transactions cannot be edited or deleted directly', () async {
    final db = await _openAuthorizationDatabase(bankBalance: 1000);
    addTearDown(db.close);
    final service = DebitCardPurchaseAuthorizationService(
      databaseProvider: () async => db,
    );
    final request = _request(amount: 100);
    await service.authorize(request);

    expect(await service.isAuthorizedTransaction(request.transaction.id), isTrue);
    await expectLater(
      service.requireMutableTransaction(request.transaction.id),
      throwsA(
        isA<DebitCardPurchaseAuthorizationException>().having(
          (error) => error.code,
          'code',
          DebitCardPurchaseAuthorizationErrorCode
              .authorizedTransactionImmutable,
        ),
      ),
    );
  });
}

DebitCardPurchaseAuthorizationRequest _request({required double amount}) {
  return DebitCardPurchaseAuthorizationRequest(
    requestId: 'request-1',
    settlementId: 'settlement-1',
    debitCardAccountId: 'debit-1',
    requestedAt: DateTime.utc(2026, 7, 3, 10),
    transaction: TransactionRecord(
      id: 'purchase-1',
      type: TransactionType.expense,
      amount: amount,
      category: '餐飲',
      occurredAt: DateTime.utc(2026, 7, 3, 9, 30),
      accountName: '日常簽帳卡',
      memberName: '自己',
      merchantName: '商店',
      tagName: '日常',
      note: '',
      currency: CurrencyCode.twd,
      exchangeRateToBase: 1,
    ),
  );
}

Future<Database> _openAuthorizationDatabase({
  double bankBalance = 0,
}) async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
  );
  await _createCoreTables(db);
  await createCanonicalProductionV18Tables(db);
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

Future<void> _insertSecondDebitCardReservation(
  Database db, {
  required double amount,
}) async {
  const bank = AccountRecord(
    id: 'bank-1',
    name: '薪轉銀行',
    type: AccountType.bank,
    initialBalance: 0,
    sortOrder: 10,
  );
  const debit = AccountRecord(
    id: 'debit-2',
    name: '共用簽帳卡',
    type: AccountType.debitCard,
    initialBalance: 0,
    sortOrder: 30,
  );
  await db.insert('accounts', debit.toMap());
  await DebitCardRepository(db).upsertProfile(
    DebitCardAccountProfile.link(
      debitCardAccountId: debit.id,
      linkedBankAccount: bank,
      debitCardCurrency: CurrencyCode.twd,
    ),
  );
  final transaction = TransactionRecord(
    id: 'existing-purchase',
    type: TransactionType.expense,
    amount: amount,
    category: '購物',
    occurredAt: DateTime.utc(2026, 7, 2),
    accountName: debit.displayName,
    memberName: '自己',
    merchantName: '',
    tagName: '',
    note: '',
  );
  await db.insert('transactions', transaction.toMap());
  await DebitCardRepository(db).upsertSettlement(
    DebitCardPendingSettlement.authorize(
      id: 'existing-settlement',
      debitCardAccountId: debit.id,
      linkedBankAccountId: bank.id,
      transactionId: transaction.id,
      amount: amount,
      currency: CurrencyCode.twd,
      authorizedAt: DateTime.utc(2026, 7, 2),
    ),
  );
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
