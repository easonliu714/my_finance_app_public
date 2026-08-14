import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v19.dart'
    show createCanonicalProductionV19Tables;
import 'package:my_finance_app/database/production_schema_v20.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/account/debit_card_account_management_service.dart';
import 'package:my_finance_app/features/account/wallet_top_up_persistence.dart';
import 'package:my_finance_app/features/account/wallet_top_up_recommendation.dart';
import 'package:my_finance_app/features/account/wallet_top_up_repository.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service_v7.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh Schema V20 creates wallet persistence tables and triggers',
      () async {
    final db = await _openV20Database();
    addTearDown(db.close);

    expect(canonicalProductionSchemaVersion, 20);
    final objects = await _schemaObjects(db);
    expect(
      objects,
      containsAll(<String>{
        'wallet_top_up_profiles',
        'wallet_top_up_suggestions',
        'wallet_top_up_audits',
        'trg_wallet_top_up_audits_no_update',
        'trg_wallet_top_up_audits_no_delete',
      }),
    );
  });

  test('V19 to V20 migration is idempotent', () async {
    final db = await _openV19Database();
    addTearDown(db.close);

    await db.transaction((txn) => createCanonicalProductionV20Tables(txn));
    await db.transaction((txn) => createCanonicalProductionV20Tables(txn));

    final objects = await _schemaObjects(db);
    expect(objects, contains('wallet_top_up_profiles'));
    expect(objects, contains('wallet_top_up_suggestions'));
    expect(objects, contains('wallet_top_up_audits'));
  });

  test('injected V20 migration failure rolls back every new object', () async {
    final db = await _openV19Database();
    addTearDown(db.close);

    await expectLater(
      db.transaction((txn) async {
        await createCanonicalProductionV20Tables(
          txn,
          stageHook: (stage) async {
            if (stage ==
                ProductionSchemaV20MigrationStage.afterWalletTopUpTables) {
              throw StateError('injected migration failure');
            }
          },
        );
      }),
      throwsA(isA<StateError>()),
    );

    final objects = await _schemaObjects(db);
    expect(objects, isNot(contains('wallet_top_up_profiles')));
    expect(objects, isNot(contains('wallet_top_up_suggestions')));
    expect(objects, isNot(contains('wallet_top_up_audits')));
  });

  test('profile lifecycle persists one append-only audit per change', () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final createdAt = DateTime.utc(2026, 7, 4, 6);

    final created = await repository.upsertProfile(
      _profile(createdAt: createdAt),
      now: createdAt,
    );
    final updated = await repository.upsertProfile(
      created.copyWith(
        threshold: 150,
        targetBalance: 600,
        updatedAt: createdAt.add(const Duration(minutes: 1)),
      ),
      now: createdAt.add(const Duration(minutes: 1)),
    );
    final disabled = await repository.upsertProfile(
      updated.copyWith(
        isEnabled: false,
        updatedAt: createdAt.add(const Duration(minutes: 2)),
      ),
      now: createdAt.add(const Duration(minutes: 2)),
    );
    await repository.upsertProfile(
      disabled.copyWith(
        isEnabled: true,
        updatedAt: createdAt.add(const Duration(minutes: 3)),
      ),
      now: createdAt.add(const Duration(minutes: 3)),
    );

    expect(await repository.listProfiles(), hasLength(1));
    final audits = await repository.listAudits(profileId: created.id);
    expect(
      audits.map((item) => item.eventType),
      <WalletTopUpAuditEventType>[
        WalletTopUpAuditEventType.profileCreated,
        WalletTopUpAuditEventType.profileUpdated,
        WalletTopUpAuditEventType.profileDisabled,
        WalletTopUpAuditEventType.profileEnabled,
      ],
    );
  });

  test('profile validation fails closed for wrong target role and currency',
      () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final now = DateTime.utc(2026, 7, 4, 6);

    await expectLater(
      repository.upsertProfile(
        _profile(createdAt: now, targetAccountId: 'cash-1'),
        now: now,
      ),
      throwsA(isA<WalletTopUpRecommendationException>()),
    );
    await expectLater(
      repository.upsertProfile(
        _profile(createdAt: now, fundingAccountId: 'usd-bank-1'),
        now: now,
      ),
      throwsA(
        isA<WalletTopUpRecommendationException>().having(
          (error) => error.code,
          'code',
          WalletTopUpRecommendationErrorCode.currencyMismatch,
        ),
      ),
    );
    expect(await repository.listProfiles(), isEmpty);
  });

  test('suggestion replay returns original row without duplicate audit',
      () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final now = DateTime.utc(2026, 7, 4, 6);
    await repository.upsertProfile(_profile(createdAt: now), now: now);
    final suggestion = _suggestion(
      id: 'wallet-top-up-aaa',
      evaluatedAt: now.add(const Duration(minutes: 1)),
    );

    final first = await repository.persistSuggestion(
      profileId: 'profile-1',
      suggestion: suggestion,
      now: now.add(const Duration(minutes: 1)),
    );
    final replay = await repository.persistSuggestion(
      profileId: 'profile-1',
      suggestion: WalletTopUpSuggestion(
        suggestionId: suggestion.suggestionId,
        targetAccountId: suggestion.targetAccountId,
        fundingAccountId: suggestion.fundingAccountId,
        currency: suggestion.currency,
        amountMode: suggestion.amountMode,
        currentAvailableBalance: suggestion.currentAvailableBalance,
        fundingAvailableBalance: 50,
        threshold: suggestion.threshold,
        suggestedAmount: suggestion.suggestedAmount,
        fundingSufficient: false,
        evaluatedAt: now.add(const Duration(hours: 1)),
      ),
      now: now.add(const Duration(hours: 1)),
    );

    expect(first.replayed, isFalse);
    expect(replay.replayed, isTrue);
    expect(await repository.listSuggestions(), hasLength(1));
    final suggestionAudits = await repository.listAudits(
      suggestionId: suggestion.suggestionId,
    );
    expect(
      suggestionAudits
          .where(
            (item) =>
                item.eventType == WalletTopUpAuditEventType.suggestionCreated,
          )
          .length,
      1,
    );
  });

  test('changed suggestion atomically supersedes the prior pending state',
      () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final now = DateTime.utc(2026, 7, 4, 6);
    await repository.upsertProfile(_profile(createdAt: now), now: now);
    await repository.persistSuggestion(
      profileId: 'profile-1',
      suggestion: _suggestion(
        id: 'wallet-top-up-old',
        evaluatedAt: now.add(const Duration(minutes: 1)),
      ),
      now: now.add(const Duration(minutes: 1)),
    );

    final result = await repository.persistSuggestion(
      profileId: 'profile-1',
      suggestion: _suggestion(
        id: 'wallet-top-up-new',
        currentAvailableBalance: 20,
        suggestedAmount: 480,
        evaluatedAt: now.add(const Duration(minutes: 2)),
      ),
      now: now.add(const Duration(minutes: 2)),
    );

    expect(result.supersededSuggestionIds, <String>['wallet-top-up-old']);
    final suggestions = await repository.listSuggestions(profileId: 'profile-1');
    expect(
      suggestions.singleWhere((item) => item.id == 'wallet-top-up-old').status,
      WalletTopUpSuggestionStatus.superseded,
    );
    expect(
      suggestions.singleWhere((item) => item.id == 'wallet-top-up-new').status,
      WalletTopUpSuggestionStatus.pending,
    );
  });

  test('dismissal is explicit and idempotent', () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final now = DateTime.utc(2026, 7, 4, 6);
    await repository.upsertProfile(_profile(createdAt: now), now: now);
    await repository.persistSuggestion(
      profileId: 'profile-1',
      suggestion: _suggestion(
        id: 'wallet-top-up-dismiss',
        evaluatedAt: now.add(const Duration(minutes: 1)),
      ),
      now: now.add(const Duration(minutes: 1)),
    );

    final first = await repository.dismissSuggestion(
      'wallet-top-up-dismiss',
      now: now.add(const Duration(minutes: 2)),
    );
    final replay = await repository.dismissSuggestion(
      'wallet-top-up-dismiss',
      now: now.add(const Duration(minutes: 3)),
    );

    expect(first.replayed, isFalse);
    expect(replay.replayed, isTrue);
    expect(first.suggestion.status, WalletTopUpSuggestionStatus.dismissed);
    final audits = await repository.listAudits(
      suggestionId: 'wallet-top-up-dismiss',
    );
    expect(
      audits
          .where(
            (item) =>
                item.eventType ==
                WalletTopUpAuditEventType.suggestionDismissed,
          )
          .length,
      1,
    );
  });

  test('wallet top-up audits reject direct update and delete', () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final now = DateTime.utc(2026, 7, 4, 6);
    await repository.upsertProfile(_profile(createdAt: now), now: now);
    final auditId = (await repository.listAudits()).single.id;

    await expectLater(
      db.update(
        'wallet_top_up_audits',
        <String, Object?>{'details_json': '{"changed":true}'},
        where: 'id = ?',
        whereArgs: <Object?>[auditId],
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.delete(
        'wallet_top_up_audits',
        where: 'id = ?',
        whereArgs: <Object?>[auditId],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('enabled profile blocks target and funding account archive', () async {
    final db = await _openV20Database();
    addTearDown(db.close);
    final repository = WalletTopUpRepository(db);
    final now = DateTime.utc(2026, 7, 4, 6);
    final profile = await repository.upsertProfile(
      _profile(createdAt: now),
      now: now,
    );
    const management = DebitCardAccountManagementService();

    await expectLater(
      management.archiveAccount(db, 'wallet-1'),
      throwsA(isA<WalletTopUpAccountArchiveException>()),
    );
    await expectLater(
      management.archiveAccount(db, 'bank-1'),
      throwsA(isA<WalletTopUpAccountArchiveException>()),
    );

    await repository.upsertProfile(
      profile.copyWith(isEnabled: false),
      now: now.add(const Duration(minutes: 1)),
    );
    await management.archiveAccount(db, 'wallet-1');
    expect(
      (await db.query(
        'accounts',
        columns: const <String>['is_archived'],
        where: 'id = ?',
        whereArgs: const <Object?>['wallet-1'],
      ))
          .single['is_archived'],
      1,
    );
  });

  test('Scope V6 backup and restore round-trip preserves immutable history',
      () async {
    final source = await _openV20Database();
    final target = await _openV20Database();
    addTearDown(source.close);
    addTearDown(target.close);
    final repository = WalletTopUpRepository(source);
    final now = DateTime.utc(2026, 7, 4, 6);
    await repository.upsertProfile(_profile(createdAt: now), now: now);
    await repository.persistSuggestion(
      profileId: 'profile-1',
      suggestion: _suggestion(
        id: 'wallet-top-up-backup',
        evaluatedAt: now.add(const Duration(minutes: 1)),
      ),
      now: now.add(const Duration(minutes: 1)),
    );

    const backupService = FullBackupService();
    final currentEnvelope = await backupService.buildFullBackupEnvelope(
      source,
      createdAt: now.add(const Duration(minutes: 2)),
    );
    final metadata = Map<String, Object?>.from(
      currentEnvelope['metadata']! as Map<String, Object?>,
    )
      ..['backup_scope_version'] = 6
      ..['database_schema_version'] = 20
      ..['included_tables'] = FullBackupScope.legacyScopeV6TableNames;
    final data = Map<String, Object?>.from(
      currentEnvelope['data']! as Map<String, Object?>,
    )..remove('wallet_top_up_executions');
    final legacyEnvelope = <String, Object?>{
      'metadata': metadata,
      'data': data,
    };
    expect(metadata['backup_scope_version'], 6);
    expect(metadata['database_schema_version'], 20);

    const restoreService = FullRestoreServiceV7();
    final result = await restoreService.restoreFromEnvelope(
      target,
      legacyEnvelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
      preRestoreBackupCreatedAt: now.add(const Duration(minutes: 3)),
    );
    expect(result.audit.passed, isTrue);
    expect(await _count(target, 'wallet_top_up_profiles'), 1);
    expect(await _count(target, 'wallet_top_up_suggestions'), 1);
    expect(await _count(target, 'wallet_top_up_audits'), 2);

    final auditId = (await target.query('wallet_top_up_audits')).first['id'];
    await expectLater(
      target.delete(
        'wallet_top_up_audits',
        where: 'id = ?',
        whereArgs: <Object?>[auditId],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('legacy Scope V5 restore normalizes new tables to empty', () async {
    final source = await _openV20Database();
    final target = await _openV20Database();
    addTearDown(source.close);
    addTearDown(target.close);
    final now = DateTime.utc(2026, 7, 4, 6);
    final repository = WalletTopUpRepository(target);
    await repository.upsertProfile(_profile(createdAt: now), now: now);

    const backupService = FullBackupService();
    final envelope = await backupService.buildFullBackupEnvelope(source);
    final metadata = Map<String, Object?>.from(
      envelope['metadata']! as Map<String, Object?>,
    )
      ..['backup_scope_version'] = 5
      ..['included_tables'] = FullBackupScope.legacyScopeV5TableNames;
    final data = Map<String, Object?>.from(
      envelope['data']! as Map<String, Object?>,
    )
      ..remove('wallet_top_up_profiles')
      ..remove('wallet_top_up_suggestions')
      ..remove('wallet_top_up_audits')
      ..remove('wallet_top_up_executions');
    final legacyEnvelope = <String, Object?>{
      'metadata': metadata,
      'data': data,
    };

    await const FullRestoreService().restoreFromEnvelope(
      target,
      legacyEnvelope,
      confirmationText: FullRestoreService.destructiveConfirmationText,
    );
    expect(await _count(target, 'wallet_top_up_profiles'), 0);
    expect(await _count(target, 'wallet_top_up_suggestions'), 0);
    expect(await _count(target, 'wallet_top_up_audits'), 0);
  });
}

StoredWalletTopUpProfile _profile({
  required DateTime createdAt,
  String targetAccountId = 'wallet-1',
  String fundingAccountId = 'bank-1',
}) {
  return StoredWalletTopUpProfile(
    id: 'profile-1',
    targetAccountId: targetAccountId,
    fundingAccountId: fundingAccountId,
    currency: CurrencyCode.twd,
    threshold: 100,
    amountMode: WalletTopUpAmountMode.targetBalance,
    targetBalance: 500,
    fixedAmount: 0,
    cooldown: const Duration(hours: 6),
    isEnabled: true,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

WalletTopUpSuggestion _suggestion({
  required String id,
  required DateTime evaluatedAt,
  double currentAvailableBalance = 50,
  double suggestedAmount = 450,
}) {
  return WalletTopUpSuggestion(
    suggestionId: id,
    targetAccountId: 'wallet-1',
    fundingAccountId: 'bank-1',
    currency: CurrencyCode.twd,
    amountMode: WalletTopUpAmountMode.targetBalance,
    currentAvailableBalance: currentAvailableBalance,
    fundingAvailableBalance: 1000,
    threshold: 100,
    suggestedAmount: suggestedAmount,
    fundingSufficient: true,
    evaluatedAt: evaluatedAt,
  );
}

Future<Database> _openV19Database() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
    onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
  );
  await _createCoreTables(db);
  await createCanonicalProductionV19Tables(db);
  await _insertAccounts(db);
  return db;
}

Future<Database> _openV20Database() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
    onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
  );
  await _createCoreTables(db);
  await createCanonicalProductionV20Tables(db);
  await _insertAccounts(db);
  return db;
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
}

Future<void> _insertAccounts(Database db) async {
  const accounts = <AccountRecord>[
    AccountRecord(
      id: 'wallet-1',
      name: '電子錢包',
      type: AccountType.eWallet,
      initialBalance: 0,
      sortOrder: 10,
    ),
    AccountRecord(
      id: 'bank-1',
      name: '資金帳戶',
      type: AccountType.bank,
      initialBalance: 0,
      sortOrder: 20,
    ),
    AccountRecord(
      id: 'cash-1',
      name: '現金',
      type: AccountType.cash,
      initialBalance: 0,
      sortOrder: 30,
    ),
    AccountRecord(
      id: 'usd-bank-1',
      name: '美元帳戶',
      type: AccountType.bank,
      initialBalance: 0,
      sortOrder: 40,
      currency: CurrencyCode.usd,
    ),
  ];
  for (final account in accounts) {
    await db.insert('accounts', account.toMap());
  }
}

Future<Set<String>> _schemaObjects(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']).whereType<String>().toSet();
}

Future<int> _count(Database db, String tableName) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
  return (rows.single['c'] as num).toInt();
}
