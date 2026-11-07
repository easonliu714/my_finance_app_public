import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v24.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_posting_confirmation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';
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

  testWidgets('production confirmation UI -> formal service -> V24 SQLite: '
      'cancel/stale no-write, general posts once, history survives',
      (tester) async {
    const lkgKey = 'invoice_award.general_lkg.v1.115-05-06';
    SharedPreferences.setMockInitialValues(<String, Object>{
      lkgKey: 'protected-lkg',
      'issue13_remittance_observations_v1': '[]',
    });
    final preferences = await SharedPreferences.getInstance();
    final db = await openDatabase(
      inMemoryDatabasePath,
      singleInstance: false,
      version: canonicalProductionSchemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, _) async {
        // Same transaction-core fixture and canonical V24 extension as the
        // service E2E. NOT the Owner's installed database or production main().
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
    final signals = <int>[];
    final subscription =
        TransactionLedgerRefreshSignal.instance.stream.listen((_) {
      signals.add(1);
    });
    addTearDown(subscription.cancel);

    final legacy = _proposal('historical-cloud500', 'cloud-500', 500);
    final historicalId =
        InvoiceAwardFormalIncomePostingService.stableRecordId(legacy);
    await db.insert('transactions', _record(historicalId, 500).toMap());
    await db.insert('transactions', _record('historical-nt700', 700).toMap());
    final historicalRows = await db.query(
      'transactions',
      where: 'id IN (?, ?)',
      whereArgs: <Object>[historicalId, 'historical-nt700'],
      orderBy: 'id',
    );
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
    final flow =
        InvoiceAwardFormalPostingConfirmation(postingService: service);
    final general = _proposal('general-ui-200', 'general-sixth', 200);
    final receipt = _receipt(general);
    var authorized = true;
    var started = 0;
    Future<bool?>? pending;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return FilledButton(
            key: const Key('launch_formal_post'),
            onPressed: () {
              pending = flow.requestAndPost(
                context: context,
                proposal: general,
                receipt: receipt,
                nowUtc: () => DateTime.utc(2026, 10, 9, 3),
                authorizationStillValid: () => authorized,
                onPostingStarted: () => started++,
              );
            },
            child: const Text('開啟正式入帳確認'),
          );
        }),
      ),
    ));
    final initialChanges =
        (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
    final initialRows = await db.query('transactions', orderBy: 'id');

    // Cancel is a real modal dismissal, not a mocked posting callback.
    await tester.tap(find.byKey(const Key('launch_formal_post')));
    await tester.pumpAndSettle();
    expect(find.text('確認新增正式發票兌獎收入'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await pending, isNull);
    expect(started, 0);
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'],
        initialChanges);

    // The live UI authority can change after the dialog opens.
    await tester.tap(find.byKey(const Key('launch_formal_post')));
    await tester.pumpAndSettle();
    authorized = false;
    final stale = expectLater(
      pending!,
      throwsA(isA<StateError>().having(
        (e) => e.toString(), 'stale UI', contains('UI_AUTHORITY_STALE'))),
    );
    await tester.tap(find.text('確認新增正式收入'));
    await tester.pumpAndSettle();
    await stale;
    expect(started, 0);
    expect(await db.query('transactions', orderBy: 'id'), initialRows);
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'],
        initialChanges);
    expect(signals, isEmpty);

    // Separate explicit approval reaches the actual posting service.
    authorized = true;
    await tester.tap(find.byKey(const Key('launch_formal_post')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認新增正式收入'));
    await tester.pumpAndSettle();
    expect(await pending, isTrue);
    expect(started, 1);
    expect(signals, hasLength(1));
    final generalId =
        InvoiceAwardFormalIncomePostingService.stableRecordId(general);
    expect(await db.query('transactions',
        where: 'id = ?', whereArgs: <Object>[generalId]), hasLength(1));

    // Repeated explicit UI confirmation is still idempotent.
    await tester.tap(find.byKey(const Key('launch_formal_post')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認新增正式收入'));
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(signals, hasLength(1));
    expect(started, 2);
    expect(await db.query('transactions',
        where: 'id IN (?, ?)',
        whereArgs: <Object>[historicalId, 'historical-nt700'],
        orderBy: 'id'), historicalRows);
    expect(preferences.getString(lkgKey), 'protected-lkg');
    expect(preferences.getString('issue13_remittance_observations_v1'), '[]');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
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
      parserRuleVersion: 'ui-v24-e2e',
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
      note: 'historical posted row',
      currency: CurrencyCode.twd,
    );
