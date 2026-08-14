import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v14.dart'
    show createCanonicalProductionV14Tables;
import '../../database/production_schema_v15.dart'
    show createCanonicalProductionV15Tables;
import '../../database/production_schema_v16.dart'
    show createCanonicalProductionV16Tables;
import '../../database/production_schema_v17.dart'
    show createCanonicalProductionV17Tables;
import '../../database/production_schema_v18.dart'
    show createCanonicalProductionV18Tables;
import '../../database/production_schema_v19.dart'
    show createCanonicalProductionV19Tables;
import '../../database/production_schema_v20.dart' show createCanonicalProductionV20Tables;
import '../../database/production_schema_v21.dart';

import '../plan/credit_card_bank_rule_profile.dart';
import '../plan/credit_card_installment_migration.dart';
import '../plan/credit_card_statement_event.dart';
import '../transaction/transaction_record.dart';
import 'account_event_record.dart';
import 'account_record.dart';
import 'account_store.dart';
import 'debit_card_account_management_service.dart';
import 'debit_card_account_store.dart';
import 'debit_card_account_profile.dart';
import 'debit_card_repository.dart';

class AccountRepository implements AccountStore, DebitCardAccountStore {
  AccountRepository._();

  static final AccountRepository instance = AccountRepository._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'my_finance_app.db');
    _database = await openDatabase(
      dbPath,
      version: canonicalProductionSchemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTransactionsTable(db);
        await _createAccountsTable(db);
        await _createAccountEventsTable(db);
        await _createCreditCardStatementEventsTable(db);
        await _createCreditCardBankRuleTables(db);
        await createCreditCardInstallmentTables(db);
        await createCanonicalProductionV21Tables(db);
        await _seedDefaultAccounts(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createAccountsTable(db);
          await _seedDefaultAccounts(db);
        }
        if (oldVersion < 3) await _ensureAccountSuffixColumn(db);
        if (oldVersion < 4) {
          await _ensureAccountCurrencyColumn(db);
          await _createAccountEventsTable(db);
          await _seedInitialBalanceEvents(db);
        }
        if (oldVersion < 5) await _ensureCreditCardSettingColumns(db);
        if (oldVersion < 6) await _ensureLoanSettingColumns(db);
        if (oldVersion < 7) await _ensureRepaymentGroupColumn(db);
        if (oldVersion < 8) await _createCreditCardBankRuleTables(db);
        if (oldVersion < 9) await _ensureLoanDisbursementColumns(db);
        if (oldVersion < 10) {
          await _rebuildAccountsTableForNameSuffixKey(db);
        }
        if (oldVersion < 11) await createCreditCardInstallmentTables(db);
        if (oldVersion < 12) {
          await upgradeCreditCardInstallmentTablesToV12(db);
        }
        if (oldVersion < 13) await createCanonicalProductionV14Tables(db);
        if (oldVersion < 14) await createCanonicalProductionV14Tables(db);
        if (oldVersion < 15) await createCanonicalProductionV15Tables(db);
        if (oldVersion < 16) await createCanonicalProductionV16Tables(db);
        if (oldVersion < 17) await createCanonicalProductionV17Tables(db);
        if (oldVersion < 18) await createCanonicalProductionV18Tables(db);
        if (oldVersion < 19) await createCanonicalProductionV19Tables(db);
        if (oldVersion < 20) await createCanonicalProductionV20Tables(db);
        if (oldVersion < 21) await createCanonicalProductionV21Tables(db);
        await _ensureAccountIdentityIndexes(db);
      },
    );
    return _database!;
  }

  Future<void> _createTransactionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_occurred_at '
      'ON transactions(occurred_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_type '
      'ON transactions(type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_repayment_group '
      'ON transactions(repayment_group_id)',
    );
  }

  Future<void> _createAccountsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
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
    await _ensureAccountIdentityIndexes(db);
  }

  Future<void> _ensureAccountIdentityIndexes(Database db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_name_suffix_unique '
      'ON accounts(name, suffix)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_accounts_sort '
      'ON accounts(is_archived, sort_order, name, suffix)',
    );
  }

  Future<void> _rebuildAccountsTableForNameSuffixKey(Database db) async {
    final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'accounts'",
    );
    if (existing.isEmpty) {
      await _createAccountsTable(db);
      return;
    }
    await _ensureAccountSettingColumns(db);
    await db.execute('DROP INDEX IF EXISTS idx_accounts_sort');
    await db.execute('DROP INDEX IF EXISTS idx_accounts_name_suffix_unique');
    await db.execute('ALTER TABLE accounts RENAME TO accounts_legacy_v10');
    await _createAccountsTable(db);
    await db.execute('''
      INSERT OR IGNORE INTO accounts (
        id, name, type, initial_balance, sort_order, suffix, currency_code,
        credit_limit, statement_day, payment_due_day,
        payment_reminder_enabled, reminder_days_before,
        loan_principal, annual_interest_rate, loan_term_months,
        loan_repayment_method, loan_payment_due_day, loan_reminder_enabled,
        loan_reminder_days_before, loan_start_date,
        loan_disbursement_account_name, loan_handling_fee,
        loan_disbursement_created, note, is_archived, created_at, updated_at
      )
      SELECT
        id, name, type, initial_balance, sort_order, COALESCE(suffix, ''),
        COALESCE(currency_code, 'TWD'), COALESCE(credit_limit, 0),
        COALESCE(statement_day, 1), COALESCE(payment_due_day, 1),
        COALESCE(payment_reminder_enabled, 0), COALESCE(reminder_days_before, 3),
        COALESCE(loan_principal, 0), COALESCE(annual_interest_rate, 0),
        COALESCE(loan_term_months, 0),
        COALESCE(loan_repayment_method, 'equalPrincipalAndInterest'),
        COALESCE(loan_payment_due_day, 1),
        COALESCE(loan_reminder_enabled, 0),
        COALESCE(loan_reminder_days_before, 3), loan_start_date,
        COALESCE(loan_disbursement_account_name, ''),
        COALESCE(loan_handling_fee, 0),
        COALESCE(loan_disbursement_created, 0), COALESCE(note, ''),
        COALESCE(is_archived, 0), COALESCE(created_at, CURRENT_TIMESTAMP),
        COALESCE(updated_at, CURRENT_TIMESTAMP)
      FROM accounts_legacy_v10
    ''');
    await db.execute('DROP TABLE accounts_legacy_v10');
    await _ensureAccountIdentityIndexes(db);
  }

  Future<void> _createAccountEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_events (
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_account_events_account_time '
      'ON account_events(account_name, occurred_at)',
    );
  }

  Future<void> _createCreditCardStatementEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_card_statement_events (
        id TEXT PRIMARY KEY,
        card_id TEXT NOT NULL,
        card_name TEXT NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'TWD',
        statement_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        total_balance REAL NOT NULL DEFAULT 0,
        minimum_payment REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        unpaid_balance REAL NOT NULL DEFAULT 0,
        estimated_revolving_interest REAL NOT NULL DEFAULT 0,
        estimated_late_fee REAL NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_statement_events_card_period '
      'ON credit_card_statement_events(card_id, period_end DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_statement_events_due '
      'ON credit_card_statement_events(due_date DESC)',
    );
  }

  Future<void> _createCreditCardBankRuleTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_card_bank_rule_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'TWD',
        minimum_payment_rate REAL NOT NULL DEFAULT 0,
        revolving_balance_rate REAL NOT NULL DEFAULT 0,
        minimum_payment_floor REAL NOT NULL DEFAULT 0,
        cash_advance_minimum REAL NOT NULL DEFAULT 0,
        fee_minimum REAL NOT NULL DEFAULT 0,
        include_estimated_fees INTEGER NOT NULL DEFAULT 1,
        annual_interest_rate REAL NOT NULL DEFAULT 0,
        days_in_year INTEGER NOT NULL DEFAULT 365,
        estimated_cycle_days INTEGER NOT NULL DEFAULT 30,
        late_fee_tiers TEXT NOT NULL DEFAULT '',
        late_fee_waive_threshold REAL NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        is_verified_against_statement INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_rule_profiles_currency '
      'ON credit_card_bank_rule_profiles(currency_code, name)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_card_bank_rule_assignments (
        card_id TEXT PRIMARY KEY,
        profile_id TEXT,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_rule_assignments_profile '
      'ON credit_card_bank_rule_assignments(profile_id)',
    );
  }

  Future<void> _ensureAccountSuffixColumn(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(accounts)');
    if (!columns.any((column) => column['name'] == 'suffix')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN suffix TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<void> _ensureAccountCurrencyColumn(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(accounts)');
    if (!columns.any((column) => column['name'] == 'currency_code')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'TWD'",
      );
    }
  }

  Future<Set<Object?>> _accountColumnNames(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(accounts)');
    return columns.map((column) => column['name']).toSet();
  }

  Future<void> _ensureCreditCardSettingColumns(Database db) async {
    final names = await _accountColumnNames(db);
    if (!names.contains('credit_limit')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('statement_day')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN statement_day INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!names.contains('payment_due_day')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN payment_due_day INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!names.contains('payment_reminder_enabled')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN payment_reminder_enabled '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('reminder_days_before')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN reminder_days_before '
        'INTEGER NOT NULL DEFAULT 3',
      );
    }
  }

  Future<void> _ensureLoanSettingColumns(Database db) async {
    final names = await _accountColumnNames(db);
    if (!names.contains('loan_principal')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_principal REAL NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('annual_interest_rate')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN annual_interest_rate '
        'REAL NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('loan_term_months')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_term_months '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('loan_repayment_method')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN loan_repayment_method TEXT NOT NULL "
        "DEFAULT 'equalPrincipalAndInterest'",
      );
    }
    if (!names.contains('loan_payment_due_day')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_payment_due_day '
        'INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!names.contains('loan_reminder_enabled')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_reminder_enabled '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('loan_reminder_days_before')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_reminder_days_before '
        'INTEGER NOT NULL DEFAULT 3',
      );
    }
    await _ensureLoanDisbursementColumns(db);
  }

  Future<void> _ensureLoanDisbursementColumns(Database db) async {
    final names = await _accountColumnNames(db);
    if (!names.contains('loan_start_date')) {
      await db.execute('ALTER TABLE accounts ADD COLUMN loan_start_date TEXT');
    }
    if (!names.contains('loan_disbursement_account_name')) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN loan_disbursement_account_name "
        "TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!names.contains('loan_handling_fee')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_handling_fee '
        'REAL NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('loan_disbursement_created')) {
      await db.execute(
        'ALTER TABLE accounts ADD COLUMN loan_disbursement_created '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _ensureAccountSettingColumns(Database db) async {
    await _ensureAccountSuffixColumn(db);
    await _ensureAccountCurrencyColumn(db);
    await _ensureCreditCardSettingColumns(db);
    await _ensureLoanSettingColumns(db);
    await _ensureAccountIdentityIndexes(db);
  }

  Future<void> _ensureRepaymentGroupColumn(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = columns.map((column) => column['name']).toSet();
    if (!names.contains('repayment_group_id')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN repayment_group_id TEXT',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_repayment_group '
      'ON transactions(repayment_group_id)',
    );
  }

  Future<void> _ensureTransactionReadColumns(Database db) async {
    await _ensureRepaymentGroupColumn(db);
  }

  Future<void> _seedDefaultAccounts(Database db) async {
    final countRow = await db.rawQuery('SELECT COUNT(*) AS total FROM accounts');
    final count = (countRow.first['total'] as num).toInt();
    if (count > 0) return;
    const defaults = [
      AccountRecord(
        id: 'cash',
        name: '現金',
        type: AccountType.cash,
        initialBalance: 0,
        sortOrder: 10,
      ),
      AccountRecord(
        id: 'bank',
        name: '銀行帳戶',
        type: AccountType.bank,
        initialBalance: 0,
        sortOrder: 20,
      ),
      AccountRecord(
        id: 'credit-card',
        name: '信用卡',
        type: AccountType.creditCard,
        initialBalance: 0,
        sortOrder: 30,
        creditLimit: 50000,
        statementDay: 15,
        paymentDueDay: 5,
      ),
      AccountRecord(
        id: 'ipass-money',
        name: '一卡通 Money',
        type: AccountType.eWallet,
        initialBalance: 0,
        sortOrder: 40,
      ),
      AccountRecord(
        id: 'easycard',
        name: '悠遊卡',
        type: AccountType.storedValue,
        initialBalance: 0,
        sortOrder: 50,
      ),
    ];
    for (final account in defaults) {
      await db.insert(
        'accounts',
        account.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await _seedInitialBalanceEvents(db);
  }

  Future<void> _seedInitialBalanceEvents(Database db) async {
    final accounts = await db.query('accounts');
    for (final row in accounts) {
      final account = AccountRecord.fromMap(row);
      await db.insert(
        'account_events',
        _initialEventFor(account).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  AccountEventRecord _initialEventFor(AccountRecord account) {
    return AccountEventRecord(
      id: 'initial-${account.id}',
      accountId: account.id,
      accountName: account.displayName,
      eventType: 'initial_balance',
      amount: account.initialBalance,
      currency: account.currency,
      exchangeRateToBase: account.currency.defaultRateToTwd,
      occurredAt: DateTime(2000),
      note: '帳戶初始值',
    );
  }

  @override
  Future<List<AccountRecord>> listAccounts({
    bool includeArchived = false,
  }) async {
    final db = await database;
    await _ensureAccountSettingColumns(db);
    final rows = await db.query(
      'accounts',
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'is_archived ASC, sort_order ASC, name ASC, suffix ASC',
    );
    return rows.map(AccountRecord.fromMap).toList();
  }

  @override
  Future<DebitCardAccountProfile?> getDebitCardProfile(
    String accountId,
  ) async {
    final db = await database;
    return DebitCardRepository(db).getProfile(accountId);
  }

  @override
  Future<void> upsertDebitCardAccount(
    AccountRecord account,
    DebitCardAccountProfile profile,
  ) async {
    final db = await database;
    await const DebitCardAccountManagementService().upsertAccountAndProfile(
      db,
      account: account,
      profile: profile,
      initialEvent: _initialEventFor(account),
    );
  }

  @override
  Future<void> upsertAccount(AccountRecord account) async {
    final db = await database;
    await _ensureAccountSettingColumns(db);
    final map = account.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    final updated = await db.update(
      'accounts',
      map,
      where: 'id = ?',
      whereArgs: [account.id],
    );
    if (updated == 0) {
      await db.insert(
        'accounts',
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    await db.insert(
      'account_events',
      _initialEventFor(account).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> archiveAccount(String id) async {
    final db = await database;
    await const DebitCardAccountManagementService().archiveAccount(db, id);
  }

  @override
  Future<List<AccountEventRecord>> listAccountEvents(
    String accountName,
  ) async {
    final db = await database;
    await _createAccountEventsTable(db);
    final rows = await db.query(
      'account_events',
      where: 'account_name = ?',
      whereArgs: [accountName],
      orderBy: 'occurred_at ASC, created_at ASC',
    );
    return rows.map(AccountEventRecord.fromMap).toList();
  }

  @override
  Future<List<TransactionRecord>> listAccountTransactions(
    String accountName,
  ) async {
    final db = await database;
    await _ensureTransactionReadColumns(db);
    final rows = await db.query(
      'transactions',
      where: 'account_name = ? OR from_account_name = ? '
          'OR to_account_name = ?',
      whereArgs: [accountName, accountName, accountName],
      orderBy: 'occurred_at ASC, created_at ASC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<void> upsertAccountEvent(AccountEventRecord event) async {
    final db = await database;
    await _createAccountEventsTable(db);
    await db.insert(
      'account_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteAccountEvent(String id) async {
    final db = await database;
    await db.delete('account_events', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<CreditCardStatementEvent>> listCreditCardStatementEvents(
    String cardId,
  ) async {
    final db = await database;
    await _createCreditCardStatementEventsTable(db);
    final rows = await db.query(
      'credit_card_statement_events',
      where: 'card_id = ?',
      whereArgs: [cardId],
      orderBy: 'period_end DESC, updated_at DESC',
    );
    return rows.map(CreditCardStatementEvent.fromMap).toList();
  }

  @override
  Future<void> upsertCreditCardStatementEvent(
    CreditCardStatementEvent event,
  ) async {
    final db = await database;
    await _createCreditCardStatementEventsTable(db);
    await db.insert(
      'credit_card_statement_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteCreditCardStatementEvent(String id) async {
    final db = await database;
    await _createCreditCardStatementEventsTable(db);
    await db.delete(
      'credit_card_statement_events',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<CreditCardBankRuleProfile>>
      listCreditCardBankRuleProfiles() async {
    final db = await database;
    await _createCreditCardBankRuleTables(db);
    final rows = await db.query(
      'credit_card_bank_rule_profiles',
      orderBy: 'currency_code ASC, name ASC',
    );
    return rows.map(CreditCardBankRuleProfile.fromMap).toList();
  }

  @override
  Future<void> upsertCreditCardBankRuleProfile(
    CreditCardBankRuleProfile profile,
  ) async {
    final db = await database;
    await _createCreditCardBankRuleTables(db);
    final map = profile.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.insert(
      'credit_card_bank_rule_profiles',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteCreditCardBankRuleProfile(String id) async {
    final db = await database;
    await _createCreditCardBankRuleTables(db);
    await db.delete(
      'credit_card_bank_rule_profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.update(
      'credit_card_bank_rule_assignments',
      {
        'profile_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'profile_id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<String?> getCreditCardBankRuleProfileId(String cardId) async {
    final db = await database;
    await _createCreditCardBankRuleTables(db);
    final rows = await db.query(
      'credit_card_bank_rule_assignments',
      where: 'card_id = ?',
      whereArgs: [cardId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['profile_id'] as String?;
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Future<void> setCreditCardBankRuleProfileId(
    String cardId,
    String? profileId,
  ) async {
    final db = await database;
    await _createCreditCardBankRuleTables(db);
    await db.insert(
      'credit_card_bank_rule_assignments',
      {
        'card_id': cardId,
        'profile_id': profileId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
