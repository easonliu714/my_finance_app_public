import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v17.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_profile.dart';
import 'package:my_finance_app/features/account/debit_card_repository.dart';
import 'package:my_finance_app/features/transaction/debit_card_settlement.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('profile, calendar and settlement round-trip through V17', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    addTearDown(db.close);
    await _createCoreTables(db);
    await createCanonicalProductionV17Tables(db);

    const bank = AccountRecord(
      id: 'bank-1',
      name: '薪轉銀行',
      type: AccountType.bank,
      initialBalance: 5000,
      sortOrder: 10,
    );
    const debit = AccountRecord(
      id: 'debit-1',
      name: '簽帳金融卡',
      type: AccountType.debitCard,
      initialBalance: 0,
      sortOrder: 20,
    );
    await db.insert('accounts', _accountRow(bank));
    await db.insert('accounts', _accountRow(debit));
    await db.insert('transactions', _transactionRow('purchase-1'));

    final repository = DebitCardRepository(db);
    final profile = DebitCardAccountProfile.link(
      debitCardAccountId: debit.id,
      linkedBankAccount: bank,
      debitCardCurrency: CurrencyCode.twd,
    );
    await repository.upsertProfile(profile);

    final storedProfile = await repository.getProfile(debit.id);
    expect(storedProfile, isNotNull);
    expect(storedProfile!.linkedBankAccountId, bank.id);
    expect(storedProfile.settlementBusinessDays, 2);

    final calendar = await repository.loadBusinessCalendar();
    final planner = DebitCardSettlementPlanner(businessCalendar: calendar);
    final settlement = planner.authorize(
      id: 'settlement-1',
      debitCardAccountId: debit.id,
      linkedBankAccountId: bank.id,
      transactionId: 'purchase-1',
      amount: 800,
      currency: CurrencyCode.twd,
      authorizedAt: DateTime.utc(2026, 9, 24, 10),
      currentBankBalance: 5000,
    );
    expect(
      settlement.expectedSettlementDate,
      DateTime.utc(2026, 9, 30, 10),
    );

    await repository.upsertSettlement(settlement);
    final storedSettlement = await repository.getSettlement(settlement.id);
    expect(storedSettlement, isNotNull);
    expect(storedSettlement!.status, DebitCardSettlementStatus.pending);

    final confirmed = storedSettlement.confirm(
      DateTime.utc(2026, 9, 30, 11),
    );
    await repository.upsertSettlement(confirmed);
    final confirmedRows = await repository.listSettlements(
      debitCardAccountId: debit.id,
      status: DebitCardSettlementStatus.confirmed,
    );
    expect(confirmedRows, hasLength(1));
    expect(confirmedRows.single.reservesAvailableBalance, isFalse);
  });

  test('repository rejects profile whose owner is not a debit card', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    addTearDown(db.close);
    await _createCoreTables(db);
    await createCanonicalProductionV17Tables(db);

    const bank = AccountRecord(
      id: 'bank-1',
      name: '銀行一',
      type: AccountType.bank,
      initialBalance: 0,
      sortOrder: 1,
    );
    const anotherBank = AccountRecord(
      id: 'bank-2',
      name: '銀行二',
      type: AccountType.bank,
      initialBalance: 0,
      sortOrder: 2,
    );
    await db.insert('accounts', _accountRow(bank));
    await db.insert('accounts', _accountRow(anotherBank));

    final profile = DebitCardAccountProfile.link(
      debitCardAccountId: anotherBank.id,
      linkedBankAccount: bank,
      debitCardCurrency: CurrencyCode.twd,
    );
    final repository = DebitCardRepository(db);

    await expectLater(
      repository.upsertProfile(profile),
      throwsA(isA<StateError>()),
    );
  });
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
      note TEXT NOT NULL DEFAULT '',
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
      note TEXT NOT NULL
    )
  ''');
}

Map<String, Object?> _accountRow(AccountRecord account) => <String, Object?>{
      'id': account.id,
      'name': account.name,
      'type': account.type.name,
      'initial_balance': account.initialBalance,
      'sort_order': account.sortOrder,
      'suffix': account.suffix,
      'currency_code': account.currency.code,
      'note': account.note,
      'is_archived': account.isArchived ? 1 : 0,
    };

Map<String, Object?> _transactionRow(String id) => <String, Object?>{
      'id': id,
      'type': 'expense',
      'amount': 800,
      'category': '餐飲',
      'occurred_at': '2026-09-24T10:00:00.000Z',
      'account_name': '簽帳金融卡',
      'member_name': '',
      'merchant_name': '',
      'tag_name': '',
      'note': '',
    };
