import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FullRestoreService', () {
    test('rejects invalid metadata', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);

      final envelope = _legacyV1Envelope();
      (envelope['metadata']! as Map<String, Object?>)['app_name'] = 'other_app';

      expect(
        () => const FullRestoreService().restoreFromEnvelope(
          db,
          envelope,
          confirmationText: FullRestoreService.destructiveConfirmationText,
        ),
        throwsA(isA<FullRestoreException>()),
      );
    });

    test('rejects restore without typed destructive confirmation', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);
      await _insertOldRows(db);

      expect(
        () => const FullRestoreService().restoreFromEnvelope(
          db,
          _legacyV1Envelope(),
          confirmationText: 'NO',
        ),
        throwsA(isA<FullRestoreException>()),
      );

      expect((await db.query('accounts')).single['id'], 'old-cash');
      expect((await db.query('transactions')).single['id'], 'old-tx');
    });

    test(
      'legacy V1 restore clears old data, writes backup data, and keeps pre-restore backup',
      () async {
        final db = await openDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        await _createRestoreTables(db);
        await _insertOldRows(db);
        Map<String, Object?>? persistedEnvelope;

        final result = await const FullRestoreService().restoreFromEnvelope(
          db,
          _legacyV1Envelope(),
          confirmationText: FullRestoreService.destructiveConfirmationText,
          preRestoreBackupCreatedAt: DateTime.utc(2026, 6, 28, 8, 30),
          sourcePlatform: 'test',
          persistPreRestoreBackup: (envelope) async {
            persistedEnvelope = envelope;
            return '/tmp/pre_restore_backup.json';
          },
        );

        expect(result.audit.passed, isTrue);
        expect(result.preRestoreBackupPath, '/tmp/pre_restore_backup.json');
        expect(persistedEnvelope, isNotNull);
        final preRestoreMetadata =
            result.preRestoreBackupEnvelope['metadata']!
                as Map<String, Object?>;
        expect(preRestoreMetadata['export_format_version'], 2);
        expect(preRestoreMetadata['database_schema_version'], 21);
        expect(preRestoreMetadata['coverage_complete'], isTrue);
        expect(preRestoreMetadata['created_at'], '2026-06-28T08:30:00.000Z');
        expect(
          (result.preRestoreBackupEnvelope['data']!
              as Map<String, Object?>)['accounts'],
          hasLength(1),
        );

        expect(await db.query('accounts'), hasLength(1));
        expect((await db.query('accounts')).single['id'], 'card-1');
        expect(await db.query('transactions'), hasLength(1));
        expect((await db.query('transactions')).single['id'], 'tx-1');
        expect(await db.query('credit_card_installment_plans'), hasLength(1));
        expect(
          await db.query('credit_card_installment_schedule_items'),
          hasLength(1),
        );
        expect(await db.query('account_events'), hasLength(1));
        expect(await db.query('credit_card_bank_rule_profiles'), hasLength(1));
        expect(
          await db.query('credit_card_bank_rule_assignments'),
          hasLength(1),
        );
      },
    );

    test('current V2 envelope restores cloud invoice data', () async {
      final source = await openDatabase(inMemoryDatabasePath);
      await _createRestoreTables(source);
      await _insertV2SourceRows(source);
      final envelope = await const FullBackupService().buildFullBackupEnvelope(
        source,
        createdAt: DateTime.utc(2026, 6, 28, 8),
        sourcePlatform: 'test',
      );
      await source.close();

      final target = await openDatabase(inMemoryDatabasePath);
      addTearDown(target.close);
      await _createRestoreTables(target);
      await _insertOldRows(target);

      final result = await const FullRestoreService().restoreFromEnvelope(
        target,
        envelope,
        confirmationText: FullRestoreService.destructiveConfirmationText,
        sourcePlatform: 'test',
      );

      expect(result.audit.passed, isTrue);
      expect((await target.query('accounts')).single['id'], 'source-cash');
      expect((await target.query('transactions')).single['id'], 'source-tx');
      expect(
        (await target.query('cloud_invoice_drafts')).single['id'],
        'source-draft',
      );
    });

    test('incomplete V2 coverage blocks restore before mutation', () async {
      final source = await openDatabase(inMemoryDatabasePath);
      await _createRestoreTables(source);
      await _insertV2SourceRows(source);
      final envelope = await const FullBackupService().buildFullBackupEnvelope(
        source,
        sourcePlatform: 'test',
      );
      await source.close();
      (envelope['metadata']! as Map<String, Object?>)['coverage_complete'] =
          false;

      final target = await openDatabase(inMemoryDatabasePath);
      addTearDown(target.close);
      await _createRestoreTables(target);
      await _insertOldRows(target);

      await expectLater(
        const FullRestoreService().restoreFromEnvelope(
          target,
          envelope,
          confirmationText: FullRestoreService.destructiveConfirmationText,
        ),
        throwsA(
          isA<FullRestoreException>().having(
            (error) => error.message,
            'message',
            contains('範圍未通過完整性驗證'),
          ),
        ),
      );

      expect((await target.query('accounts')).single['id'], 'old-cash');
      expect((await target.query('transactions')).single['id'], 'old-tx');
      expect(
        (await target.query('cloud_invoice_drafts')).single['id'],
        'old-draft',
      );
    });

    test('legacy V1 restore clears newer managed tables to empty', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);
      await _insertOldRows(db);

      await const FullRestoreService().restoreFromEnvelope(
        db,
        _legacyV1Envelope(),
        confirmationText: FullRestoreService.destructiveConfirmationText,
      );

      expect(await db.query('cloud_invoice_drafts'), isEmpty);
    });

    test('restoreFromJson accepts legacy V1 backup JSON envelope', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);

      final jsonText = jsonEncode(_legacyV1Envelope());
      final result = await const FullRestoreService().restoreFromJson(
        db,
        jsonText,
        confirmationText: FullRestoreService.destructiveConfirmationText,
        sourcePlatform: 'test',
      );

      expect(result.audit.passed, isTrue);
      expect(await db.query('accounts'), hasLength(1));
    });

    test('unsupported newer schema blocks restore before writing data', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);
      await _insertOldRows(db);
      final envelope = _legacyV1Envelope();
      (envelope['metadata']!
              as Map<String, Object?>)['database_schema_version'] =
          FullBackupService.databaseSchemaVersion + 1;

      expect(
        () => const FullRestoreService().restoreFromEnvelope(
          db,
          envelope,
          confirmationText: FullRestoreService.destructiveConfirmationText,
        ),
        throwsA(isA<FullRestoreException>()),
      );

      expect((await db.query('accounts')).single['id'], 'old-cash');
      expect((await db.query('transactions')).single['id'], 'old-tx');
    });

    test('referential integrity failure rolls back original data', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);
      await _insertOldRows(db);
      final envelope = _legacyV1Envelope();
      ((envelope['data']!
                  as Map<String, Object?>)['credit_card_installment_schedule_items']!
              as List<Map<String, Object?>>)
          .single['plan_id'] = 'missing-plan';

      expect(
        () => const FullRestoreService().restoreFromEnvelope(
          db,
          envelope,
          confirmationText: FullRestoreService.destructiveConfirmationText,
        ),
        throwsA(isA<FullRestoreException>()),
      );

      expect((await db.query('accounts')).single['id'], 'old-cash');
      expect((await db.query('transactions')).single['id'], 'old-tx');
      expect(
        await db.query('credit_card_installment_schedule_items'),
        isEmpty,
      );
    });

    test('integrity audit detects orphan references', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createRestoreTables(db);
      await db.insert(
        'credit_card_installment_schedule_items',
        <String, Object?>{
          'id': 'schedule-orphan',
          'plan_id': 'missing-plan',
          'period_number': 1,
          'total_payment': 1000,
          'status': 'pending',
        },
      );
      await db.insert(
        'credit_card_bank_rule_assignments',
        <String, Object?>{
          'card_id': 'missing-card',
          'profile_id': 'missing-profile',
        },
      );

      final audit = await const FullRestoreService()
          .auditReferentialIntegrity(db);
      final codes = audit.issues.map((issue) => issue.code).toSet();

      expect(audit.passed, isFalse);
      expect(codes, contains('orphan_installment_schedule_plan'));
      expect(codes, contains('orphan_bank_rule_assignment_card'));
      expect(codes, contains('orphan_bank_rule_assignment_profile'));
    });
  });
}

Future<void> _createRestoreTables(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      suffix TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute('''
    CREATE TABLE account_events (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      amount REAL NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      note TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute('''
    CREATE TABLE credit_card_statement_events (
      id TEXT PRIMARY KEY,
      card_id TEXT NOT NULL,
      total_balance REAL NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE credit_card_bank_rule_profiles (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      annual_interest_rate REAL NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE credit_card_bank_rule_assignments (
      card_id TEXT PRIMARY KEY,
      profile_id TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE credit_card_installment_plans (
      id TEXT PRIMARY KEY,
      card_id TEXT NOT NULL,
      principal REAL NOT NULL,
      source_transaction_id TEXT,
      source_type TEXT NOT NULL DEFAULT 'purchase_transaction'
    )
  ''');
  await db.execute('''
    CREATE TABLE credit_card_installment_schedule_items (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL,
      period_number INTEGER NOT NULL,
      total_payment REAL NOT NULL,
      generated_transaction_id TEXT,
      status TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE cloud_invoice_drafts (
      id TEXT PRIMARY KEY,
      operation_key TEXT NOT NULL,
      account_id TEXT NOT NULL,
      account_resolution_status TEXT NOT NULL
    )
  ''');
}

Future<void> _insertOldRows(Database db) async {
  await db.insert(
    'accounts',
    <String, Object?>{
      'id': 'old-cash',
      'name': 'Old Cash',
      'type': 'cash',
      'suffix': '',
    },
  );
  await db.insert(
    'transactions',
    <String, Object?>{
      'id': 'old-tx',
      'type': 'expense',
      'amount': 999,
      'note': 'old',
    },
  );
  await db.insert(
    'cloud_invoice_drafts',
    <String, Object?>{
      'id': 'old-draft',
      'operation_key': 'old-draft-op',
      'account_id': 'old-cash',
      'account_resolution_status': 'selected',
    },
  );
}

Future<void> _insertV2SourceRows(Database db) async {
  await db.insert(
    'accounts',
    <String, Object?>{
      'id': 'source-cash',
      'name': 'Source Cash',
      'type': 'cash',
      'suffix': '',
    },
  );
  await db.insert(
    'transactions',
    <String, Object?>{
      'id': 'source-tx',
      'type': 'expense',
      'amount': 120,
      'note': 'source',
    },
  );
  await db.insert(
    'cloud_invoice_drafts',
    <String, Object?>{
      'id': 'source-draft',
      'operation_key': 'source-draft-op',
      'account_id': 'source-cash',
      'account_resolution_status': 'selected',
    },
  );
}

Map<String, Object?> _legacyV1Envelope() {
  return <String, Object?>{
    'metadata': <String, Object?>{
      'export_format_version': 1,
      'app_name': FullBackupService.appName,
      'app_version': '3.1.0+121',
      'phase': 'P3.1',
      'database_schema_version': 12,
      'created_at': '2026-06-01T04:00:00.000Z',
      'source_platform': 'test',
      'export_mode': FullBackupService.exportModeFullBackup,
    },
    'data': <String, Object?>{
      'accounts': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'card-1',
          'name': 'Line',
          'type': 'creditCard',
          'suffix': '4568',
        },
      ],
      'account_events': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'event-1',
          'account_id': 'card-1',
          'amount': 0,
        },
      ],
      'transactions': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'tx-1',
          'type': 'expense',
          'amount': 150,
          'note': '早餐',
        },
      ],
      'credit_card_statement_events': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'statement-1',
          'card_id': 'card-1',
          'total_balance': 3150,
        },
      ],
      'credit_card_bank_rule_profiles': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'rule-1',
          'name': 'Default',
          'annual_interest_rate': 15,
        },
      ],
      'credit_card_bank_rule_assignments': <Map<String, Object?>>[
        <String, Object?>{'card_id': 'card-1', 'profile_id': 'rule-1'},
      ],
      'credit_card_installment_plans': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'plan-1',
          'card_id': 'card-1',
          'principal': 12000,
          'source_transaction_id': 'tx-1',
          'source_type': 'purchase_transaction',
        },
      ],
      'credit_card_installment_schedule_items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'item-1',
          'plan_id': 'plan-1',
          'period_number': 1,
          'total_payment': 2000,
          'generated_transaction_id': 'tx-1',
          'status': 'paid',
        },
      ],
    },
  };
}
