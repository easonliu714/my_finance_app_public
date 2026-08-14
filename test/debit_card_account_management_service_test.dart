import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_event_record.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_management_service.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const service = DebitCardAccountManagementService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('account and profile are saved atomically', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final bank = _bank();
    await db.insert('accounts', bank.toMap());
    final debit = _debit();
    final profile = DebitCardAccountProfile.link(
      debitCardAccountId: debit.id,
      linkedBankAccount: bank,
      debitCardCurrency: debit.currency,
    );

    await service.upsertAccountAndProfile(
      db,
      account: debit,
      profile: profile,
      initialEvent: _initialEvent(debit),
    );

    expect(await db.query('accounts', where: 'id = ?', whereArgs: [debit.id]),
        hasLength(1));
    expect(await db.query('debit_card_profiles'), hasLength(1));
    expect(await db.query('account_events'), hasLength(1));
  });

  test('profile validation failure rolls back account and event', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final notBank = _bank().copyWith(type: AccountType.cash);
    await db.insert('accounts', notBank.toMap());
    final debit = _debit();
    final invalidProfile = DebitCardAccountProfile.fromMap(
      <String, Object?>{
        'debit_card_account_id': debit.id,
        'linked_bank_account_id': notBank.id,
        'currency_code': debit.currency.code,
        'settlement_business_days': 2,
        'is_enabled': 1,
      },
    );

    await expectLater(
      service.upsertAccountAndProfile(
        db,
        account: debit,
        profile: invalidProfile,
        initialEvent: _initialEvent(debit),
      ),
      throwsA(isA<DebitCardAccountLinkException>()),
    );

    expect(await db.query('accounts', where: 'id = ?', whereArgs: [debit.id]),
        isEmpty);
    expect(await db.query('account_events'), isEmpty);
    expect(await db.query('debit_card_profiles'), isEmpty);
  });

  test('enabled debit-card link blocks bank archive', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final bank = _bank();
    final debit = _debit();
    await db.insert('accounts', bank.toMap());
    await db.insert('accounts', debit.toMap());
    await db.insert(
      'debit_card_profiles',
      DebitCardAccountProfile.link(
        debitCardAccountId: debit.id,
        linkedBankAccount: bank,
        debitCardCurrency: debit.currency,
      ).toMap(),
    );

    await expectLater(
      service.archiveAccount(db, bank.id),
      throwsA(isA<DebitCardAccountArchiveException>()),
    );

    expect(
      (await db.query('accounts', where: 'id = ?', whereArgs: [bank.id]))
          .single['is_archived'],
      0,
    );
  });

  test('pending settlement blocks debit-card archive', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final bank = _bank();
    final debit = _debit();
    await db.insert('accounts', bank.toMap());
    await db.insert('accounts', debit.toMap());
    await db.insert(
      'debit_card_profiles',
      DebitCardAccountProfile.link(
        debitCardAccountId: debit.id,
        linkedBankAccount: bank,
        debitCardCurrency: debit.currency,
      ).toMap(),
    );
    await db.insert('debit_card_settlements', <String, Object?>{
      'id': 'settlement-1',
      'debit_card_account_id': debit.id,
      'status': 'pending',
    });

    await expectLater(
      service.archiveAccount(db, debit.id),
      throwsA(isA<DebitCardAccountArchiveException>()),
    );

    expect(
      (await db.query('accounts', where: 'id = ?', whereArgs: [debit.id]))
          .single['is_archived'],
      0,
    );
  });

  test('successful debit-card archive disables its profile', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final bank = _bank();
    final debit = _debit();
    await db.insert('accounts', bank.toMap());
    await db.insert('accounts', debit.toMap());
    await db.insert(
      'debit_card_profiles',
      DebitCardAccountProfile.link(
        debitCardAccountId: debit.id,
        linkedBankAccount: bank,
        debitCardCurrency: debit.currency,
      ).toMap(),
    );

    await service.archiveAccount(db, debit.id);

    expect(
      (await db.query('accounts', where: 'id = ?', whereArgs: [debit.id]))
          .single['is_archived'],
      1,
    );
    expect((await db.query('debit_card_profiles')).single['is_enabled'], 0);
  });
}

AccountRecord _bank() => const AccountRecord(
      id: 'bank-1',
      name: '主要銀行',
      type: AccountType.bank,
      initialBalance: 10000,
      sortOrder: 100,
      currency: CurrencyCode.twd,
    );

AccountRecord _debit() => const AccountRecord(
      id: 'debit-1',
      name: '簽帳金融卡',
      type: AccountType.debitCard,
      initialBalance: 0,
      sortOrder: 110,
      currency: CurrencyCode.twd,
    );

AccountEventRecord _initialEvent(AccountRecord account) => AccountEventRecord(
      id: 'initial-${account.id}',
      accountId: account.id,
      accountName: account.displayName,
      eventType: 'initial_balance',
      amount: 0,
      currency: account.currency,
      exchangeRateToBase: account.currency.defaultRateToTwd,
      occurredAt: DateTime(2000),
      note: '帳戶初始值',
    );

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
      updated_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE account_events (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      account_name TEXT NOT NULL,
      event_type TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      exchange_rate_to_base REAL NOT NULL,
      base_amount REAL NOT NULL,
      occurred_at TEXT NOT NULL,
      note TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_card_profiles (
      debit_card_account_id TEXT PRIMARY KEY,
      linked_bank_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      settlement_business_days INTEGER NOT NULL DEFAULT 2,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_card_settlements (
      id TEXT PRIMARY KEY,
      debit_card_account_id TEXT NOT NULL,
      status TEXT NOT NULL
    )
  ''');
  return db;
}
