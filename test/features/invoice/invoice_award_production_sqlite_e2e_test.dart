import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v24.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';
import 'package:my_finance_app/features/invoice/invoice_award_shared_preferences_lkg_repository.dart';
import 'package:my_finance_app/features/transaction/transaction_ledger_refresh_signal.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Owner C receipt -> actual SQLite posting: no-write cloud500, '
      'NT700 and general non-regression', () async {
    final legacy = _proposal('historical-500', 'cloud-500', 500);
    final oldReceipt = _receipt(legacy);
    const lkgKey = 'invoice_award.general_lkg.v1.115-05-06';
    const lkgPayload = 'historical-validated-lkg-sentinel';
    final originalReceiptJson = jsonEncode(<Object>[oldReceipt.toJson()]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'issue13_remittance_observations_v1': originalReceiptJson,
      lkgKey: lkgPayload,
    });
    final preferences = await SharedPreferences.getInstance();
    final receipts = InvoiceAwardRemittanceReceiptRepository(preferences);
    final lkg = SharedPreferencesOfficialInvoiceAwardLkgRepository(preferences);
    final db = await openDatabase(
      inMemoryDatabasePath,
      singleInstance: false,
      version: canonicalProductionSchemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, _) async {
        // Match the production AccountRepository transaction-core columns.
        // This isolated fixture is not the full installed V24 database.
        await database.execute('''
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
        // The real V24 extension is created in an isolated FFI database;
        // the transaction-core fixture is still not a device V24 clone.
        await database.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
            is_archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await createCanonicalProductionV24Tables(database);
      },
    );
    addTearDown(db.close);
    final ledgerSignals = <int>[];
    final signalSubscription = TransactionLedgerRefreshSignal.instance.stream
        .listen((_) => ledgerSignals.add(1));
    addTearDown(signalSubscription.cancel);
    await db.insert('accounts', <String, Object?>{
      'id': 'bank-1', 'name': '測試銀行', 'type': 'bank',
    });
    await db.insert('business_registry_snapshots', <String, Object?>{
      'version': 'isolated-v24-cache',
      'source_dataset': 'synthetic-registry',
      'content_sha256': 'b' * 64,
      'status': 'installed',
      'created_at': '2026-11-07T00:00:00Z',
    });
    await db.insert('business_registry_official_details', <String, Object?>{
      'snapshot_version': 'isolated-v24-cache',
      'jurisdiction': 'TW',
      'seller_identifier': '12345678',
      'official_json': '{"fixture":"must-survive"}',
    });
    expect((await db.rawQuery('PRAGMA user_version')).single['user_version'],
        canonicalProductionSchemaVersion);
    final backupScope = await FullBackupScope.inspect(db);
    expect(backupScope.isComplete, isTrue);
    expect(backupScope.excludedPresentTables,
        contains('business_registry_official_details'));
    final service = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      databaseProvider: () async => db,
      accountsProvider: () async => <AccountRecord>[
        const AccountRecord(
          id: 'bank-1',
          name: '測試銀行',
          type: AccountType.bank,
          initialBalance: 0,
          sortOrder: 0,
        ),
      ],
    );
    final historicalId =
        InvoiceAwardFormalIncomePostingService.stableRecordId(legacy);
    await db.insert('transactions', _record(historicalId, 500).toMap());
    await db.insert('transactions', _record('protected-nt700', 700).toMap());
    final historicalBefore = (await db.query(
      'transactions',
      where: 'id IN (?, ?)',
      whereArgs: <Object>[historicalId, 'protected-nt700'],
      orderBy: 'id',
    )).map((row) => Map<String, Object?>.from(row)).toList();
    expect(await lkg.read('115-05-06'), isNotNull);
    expect(receipts.readForProposal(legacy)?.grossAmount, 500);
    expect(await service.readPostedIds(<InvoiceAwardPayoutBookkeepingProposal>[legacy]),
        contains(historicalId));
    final userBackupBefore = jsonEncode((await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated-test'))['data']);
    expect(ledgerSignals, isEmpty);

    // Both the real SharedPreferences receipt boundary and the actual
    // SQLite-posting service must reject the same malformed legacy aliases.
    for (final tier in <String>[
      'cloud-500', ' CLOUD-500 ', 'cloud-0500', 'cloud500', 'cloud-800',
    ]) {
      final blocked = _proposal('blocked-${tier.trim()}', tier, 500);
      final changesBefore =
          (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
      final rowsBefore = jsonEncode(await db.query('transactions', orderBy: 'id'));
      final prefsBefore = preferences.getString('issue13_remittance_observations_v1');
      await expectLater(
        receipts.confirmObservedCredit(
          proposal: blocked,
          receivedAtUtc: DateTime.utc(2026, 10, 9),
          confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
        ),
        throwsA(isA<StateError>().having(
          (error) => error.toString(),
          'Owner-C receipt gate',
          contains(Cloud500ProductionPolicy.deferredCode),
        )),
      );
      await expectLater(
        service.post(
          proposal: blocked,
          receipt: _receipt(blocked),
          authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
        ),
        throwsA(isA<StateError>().having(
          (error) => error.toString(),
          'Owner-C ledger gate',
          contains(Cloud500ProductionPolicy.deferredCode),
        )),
      );
      expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'],
          changesBefore, reason: tier);
      expect(jsonEncode(await db.query('transactions', orderBy: 'id')),
          rowsBefore, reason: tier);
      expect(preferences.getString('issue13_remittance_observations_v1'),
          prefsBefore, reason: tier);
      expect((await lkg.read('115-05-06'))?.payload, lkgPayload);
      expect(ledgerSignals, isEmpty, reason: 'rejected $tier must not notify Provider');
    }
    expect(jsonEncode((await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated-test'))['data']),
        userBackupBefore, reason: 'Owner C must not mutate V24 backup scope');
    expect((await db.query('business_registry_official_details')).single
        ['official_json'], '{"fixture":"must-survive"}');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    // A separately authorized ordinary prize remains postable exactly once.
    final general = _proposal('general-200', 'general-sixth', 200);
    final generalReceipt = await receipts.confirmObservedCredit(
      proposal: general,
      receivedAtUtc: DateTime.utc(2026, 10, 9),
      confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
    );
    // A stale page may retain the same key after an account change. Its
    // revoke must not erase the valid receipt or mutate isolated V24 state.
    final staleAccountProposal = InvoiceAwardPayoutBookkeepingProposal(
      invoiceIdentity: general.invoiceIdentity,
      awardPeriodId: general.awardPeriodId,
      prizeTier: general.prizeTier,
      grossAmount: general.grossAmount,
      localAccountId: 'stale-other-bank',
      externalRemittanceEligibleAt: general.externalRemittanceEligibleAt,
      officialDatasetFingerprint: general.officialDatasetFingerprint,
      parserRuleVersion: general.parserRuleVersion,
    );
    expect(staleAccountProposal.idempotencyKey, general.idempotencyKey);
    const receiptStoreKey = 'issue13_remittance_observations_v1';
    final beforeStaleRevoke = preferences.getString(receiptStoreKey);
    final beforeStaleRevokeRows = await db.query('transactions', orderBy: 'id');
    final beforeStaleRevokeChanges =
        (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
    await expectLater(
      receipts.revokeForProposal(
        staleAccountProposal, expectedObservation: generalReceipt),
      throwsA(isA<StateError>().having(
        (error) => error.toString(), 'stale revoke rejected',
        contains('REMITTANCE_OBSERVATION_IDENTITY_CONFLICT'),
      )),
    );
    expect(preferences.getString(receiptStoreKey), beforeStaleRevoke);
    expect(receipts.isCurrentObservation(
        proposal: general, observation: generalReceipt), isTrue);
    expect(await db.query('transactions', orderBy: 'id'),
        beforeStaleRevokeRows);
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'],
        beforeStaleRevokeChanges);
    expect(ledgerSignals, isEmpty);
    expect((await lkg.read('115-05-06'))?.payload, lkgPayload);
    // A real SQLite trigger simulates a transaction abort. A failed formal
    // post must leave rows, backups, LKG and Provider state untouched.
    final generalId =
        InvoiceAwardFormalIncomePostingService.stableRecordId(general);
    await db.execute('''
      CREATE TRIGGER reject_general_income BEFORE INSERT ON transactions
      WHEN NEW.id = '$generalId'
      BEGIN SELECT RAISE(ABORT, 'synthetic-rollback'); END
    ''');
    final rollbackChanges =
        (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
    final rollbackRows = jsonEncode(await db.query('transactions', orderBy: 'id'));
    await expectLater(
      service.post(
        proposal: general,
        receipt: generalReceipt,
        authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
      ),
      throwsA(predicate(
          (error) => error.toString().contains('synthetic-rollback'))),
    );
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'],
        rollbackChanges);
    expect(jsonEncode(await db.query('transactions', orderBy: 'id')),
        rollbackRows);
    expect(ledgerSignals, isEmpty, reason: 'aborted SQLite post must not refresh');
    expect((await lkg.read('115-05-06'))?.payload, lkgPayload);
    expect(jsonEncode((await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated-test'))['data']),
        userBackupBefore);
    await db.execute('DROP TRIGGER reject_general_income');

    expect(await service.post(
      proposal: general,
      receipt: generalReceipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
    ), isTrue);
    expect(ledgerSignals, hasLength(1),
        reason: 'one committed income must notify the real ledger Provider');
    expect(await service.post(
      proposal: general,
      receipt: generalReceipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
    ), isFalse);
    expect(ledgerSignals, hasLength(1),
        reason: 'idempotent duplicate must not issue a second refresh');
    expect(await service.readPostedIds(<InvoiceAwardPayoutBookkeepingProposal>[
      legacy, general,
    ]), containsAll(<String>[historicalId, generalId]));
    expect(await db.query('transactions', where: 'id = ?',
        whereArgs: <Object>[generalId]), hasLength(1));
    expect((await db.query('transactions', where: 'id IN (?, ?)',
        whereArgs: <Object>[historicalId, 'protected-nt700'], orderBy: 'id'))
        .map((row) => Map<String, Object?>.from(row)).toList(),
        historicalBefore);
    expect((await lkg.read('115-05-06'))?.payload, lkgPayload);
    expect(receipts.readForProposal(legacy)?.grossAmount, 500);
    final finalBackup = (await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'isolated-test'))['data']!
        as Map<String, Object?>;
    expect(finalBackup['transactions'] as List, hasLength(3));
    expect(finalBackup, isNot(contains('business_registry_official_details')));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

    // Direct service callers cannot bypass durable manual receipt authority.
    // A revoked receipt during an awaited account read also cannot reach the
    // SQLite transaction, even if the UI previously approved the same key.
    final beforeRaceRows = await db.query('transactions', orderBy: 'id');
    final beforeRaceChanges =
        (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
    final beforeRaceSignals = ledgerSignals.length;
    final missing = _proposal('unconfirmed-direct-200', 'general-sixth', 200);
    await expectLater(
      service.post(
        proposal: missing,
        receipt: _receipt(missing),
        authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'durable receipt required',
        contains('INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT'),
      )),
    );
    final racing = _proposal('revoked-inflight-200', 'general-sixth', 200);
    final racingReceipt = await receipts.confirmObservedCredit(
      proposal: racing,
      receivedAtUtc: DateTime.utc(2026, 10, 9),
      confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
    );
    final accountReadStarted = Completer<void>();
    final resumeAccountRead = Completer<void>();
    final racingService = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      databaseProvider: () async => db,
      accountsProvider: () async {
        accountReadStarted.complete();
        await resumeAccountRead.future;
        return <AccountRecord>[
          const AccountRecord(
            id: 'bank-1', name: '測試銀行', type: AccountType.bank,
            initialBalance: 0, sortOrder: 0,
          ),
        ];
      },
    );
    final pendingPost = racingService.post(
      proposal: racing,
      receipt: racingReceipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
    );
    await accountReadStarted.future;
    await receipts.revokeForProposal(
      racing, expectedObservation: racingReceipt);
    resumeAccountRead.complete();
    await expectLater(
      pendingPost,
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'revoked while account read awaited',
        contains('INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT'),
      )),
    );
    expect(await db.query('transactions', orderBy: 'id'), beforeRaceRows);
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'],
        beforeRaceChanges);
    expect(ledgerSignals, hasLength(beforeRaceSignals));
    expect((await lkg.read('115-05-06'))?.payload, lkgPayload);
  });
}

InvoiceAwardPayoutBookkeepingProposal _proposal(
    String invoice, String tier, int amount) =>
    InvoiceAwardPayoutBookkeepingProposal(
      invoiceIdentity: invoice,
      awardPeriodId: '115-05-06',
      prizeTier: tier,
      grossAmount: amount,
      localAccountId: 'bank-1',
      externalRemittanceEligibleAt: DateTime.utc(2026, 8, 5, 16),
      officialDatasetFingerprint: 'a' * 64,
      parserRuleVersion: 'sqlite-e2e-regression',
    );

InvoiceAwardRemittanceReceiptEvidence _receipt(
    InvoiceAwardPayoutBookkeepingProposal proposal) =>
    InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 9),
      confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
    );

TransactionRecord _record(String id, double amount) => TransactionRecord(
      id: id,
      type: TransactionType.income,
      amount: amount,
      category: '發票兌獎',
      occurredAt: DateTime.utc(2026, 10, 9),
      accountName: '測試銀行',
      memberName: '自己',
      merchantName: '',
      tagName: '',
      note: 'preserved historical ledger evidence',
      currency: CurrencyCode.twd,
    );
