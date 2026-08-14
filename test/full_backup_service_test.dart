import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/app_build_metadata.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FullBackupService', () {
    test('exports canonical V21 Scope V7 envelope', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createSampleTables(db);
      await _insertSampleRows(db);

      const service = FullBackupService();
      final envelope = await service.buildFullBackupEnvelope(
        db,
        createdAt: DateTime.utc(2026, 6, 28, 7, 10),
        sourcePlatform: 'test',
      );

      final metadata = envelope['metadata']! as Map<String, Object?>;
      expect(metadata['export_format_version'], 2);
      expect(metadata['app_name'], AppBuildMetadata.appName);
      expect(metadata['app_version'], AppBuildMetadata.appVersion);
      expect(metadata['phase'], AppBuildMetadata.phase);
      expect(metadata['database_schema_version'], 21);
      expect(metadata['backup_scope_version'], 7);
      expect(metadata['coverage_complete'], isTrue);
      expect(metadata['unknown_tables'], isEmpty);
      expect(metadata['missing_required_tables'], isEmpty);
      expect(
        metadata['excluded_present_tables'],
        containsAll(<String>[
          'app_settings',
          'production_migration_markers',
          'taiwan_business_calendar_days',
        ]),
      );
      expect(metadata['created_at'], '2026-06-28T07:10:00.000Z');
      expect(metadata['source_platform'], 'test');
      expect(metadata['export_mode'], 'full_backup');

      final data = envelope['data']! as Map<String, Object?>;
      expect(data.keys, containsAll(FullBackupService.backupTableNames));
      expect(data, isNot(contains('app_settings')));
      expect(data, isNot(contains('production_migration_markers')));
      expect(data, isNot(contains('taiwan_business_calendar_days')));
      expect(data['accounts'] as List, hasLength(3));
      expect(data['transactions'] as List, hasLength(1));
      expect(data['merchants'] as List, hasLength(1));
      expect(data['cloud_invoice_drafts'] as List, hasLength(1));
      expect(data['debit_card_profiles'] as List, hasLength(1));
      expect(data['debit_card_settlements'] as List, hasLength(1));
      expect(data['debit_card_authorization_audits'] as List, hasLength(1));
      expect(data['debit_card_settlement_confirmation_audits'], isEmpty);
      expect(data['wallet_top_up_profiles'] as List, hasLength(1));
      expect(data['wallet_top_up_suggestions'] as List, hasLength(1));
      expect(data['wallet_top_up_audits'] as List, hasLength(1));
      expect(data['wallet_top_up_executions'], isEmpty);
      expect(data['cloud_invoice_audits'], isEmpty);
    });

    test('missing approved optional tables are exported as empty arrays', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE transactions (id TEXT PRIMARY KEY, amount REAL NOT NULL)',
      );
      await db.insert(
        'accounts',
        <String, Object?>{'id': 'cash', 'name': '現金'},
      );

      final envelope = await const FullBackupService()
          .buildFullBackupEnvelope(db, sourcePlatform: 'test');
      final metadata = envelope['metadata']! as Map<String, Object?>;
      final data = envelope['data']! as Map<String, Object?>;

      expect(metadata['coverage_complete'], isTrue);
      expect(
        metadata['missing_optional_tables'],
        contains('debit_card_profiles'),
      );
      expect(
        metadata['missing_optional_tables'],
        contains('debit_card_authorization_audits'),
      );
      expect(
        metadata['missing_optional_tables'],
        contains('wallet_top_up_profiles'),
      );
      expect(data['accounts'] as List, hasLength(1));
      expect(data['transactions'], isEmpty);
      expect(data['credit_card_statement_events'], isEmpty);
      expect(data['cloud_invoice_drafts'], isEmpty);
      expect(data['debit_card_profiles'], isEmpty);
      expect(data['debit_card_settlements'], isEmpty);
      expect(data['debit_card_authorization_audits'], isEmpty);
      expect(data['debit_card_settlement_confirmation_audits'], isEmpty);
      expect(data['wallet_top_up_profiles'], isEmpty);
      expect(data['wallet_top_up_suggestions'], isEmpty);
      expect(data['wallet_top_up_audits'], isEmpty);
      expect(data['wallet_top_up_executions'], isEmpty);
    });

    test('unknown user tables block export instead of being omitted', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY)');
      await db.execute(
        'CREATE TABLE unexpected_private_data (id TEXT PRIMARY KEY)',
      );

      await expectLater(
        const FullBackupService().buildFullBackupEnvelope(db),
        throwsA(
          isA<FullBackupCoverageException>().having(
            (error) => error.message,
            'message',
            contains('unexpected_private_data'),
          ),
        ),
      );
    });

    test('missing required core tables block export', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');

      await expectLater(
        const FullBackupService().buildFullBackupEnvelope(db),
        throwsA(
          isA<FullBackupCoverageException>().having(
            (error) => error.message,
            'message',
            contains('transactions'),
          ),
        ),
      );
    });

    test('writes V2 JSON format with Scope V7 metadata', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _createSampleTables(db);
      await _insertSampleRows(db);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'my_finance_backup_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final file = await const FullBackupService().writeFullBackupFile(
        db,
        baseDirectory: tempDirectory,
        createdAt: DateTime.utc(2026, 6, 28, 7, 15),
        sourcePlatform: 'test',
      );

      expect(file.existsSync(), isTrue);
      expect(file.path, contains('/backups/'));
      expect(file.path, contains('_backup_v2_'));
      expect(file.path, endsWith('.json'));
      final decoded = jsonDecode(await file.readAsString())
          as Map<String, Object?>;
      final metadata = decoded['metadata']! as Map<String, Object?>;
      expect(metadata['database_schema_version'], 21);
      expect(metadata['backup_scope_version'], 7);
      expect(metadata['created_at'], '2026-06-28T07:15:00.000Z');
      expect(metadata['coverage_complete'], isTrue);
      expect(
        (decoded['data']! as Map<String, Object?>)['transactions'],
        isA<List>(),
      );
      expect(
        (decoded['data']! as Map<String, Object?>)['wallet_top_up_audits'],
        isA<List>(),
      );
    });
  });
}

Future<void> _createSampleTables(Database db) async {
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      suffix TEXT NOT NULL DEFAULT ''
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
    CREATE TABLE merchants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE cloud_invoice_drafts (
      id TEXT PRIMARY KEY,
      operation_key TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_card_profiles (
      debit_card_account_id TEXT PRIMARY KEY,
      linked_bank_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      settlement_business_days INTEGER NOT NULL,
      is_enabled INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_card_settlements (
      id TEXT PRIMARY KEY,
      debit_card_account_id TEXT NOT NULL,
      linked_bank_account_id TEXT NOT NULL,
      transaction_id TEXT NOT NULL,
      amount REAL NOT NULL,
      status TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_card_authorization_audits (
      request_id TEXT PRIMARY KEY,
      payload_fingerprint TEXT NOT NULL,
      transaction_id TEXT NOT NULL,
      settlement_id TEXT NOT NULL,
      debit_card_account_id TEXT NOT NULL,
      linked_bank_account_id TEXT NOT NULL,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      ledger_balance_before REAL NOT NULL,
      reserved_before REAL NOT NULL,
      available_before REAL NOT NULL,
      available_after REAL NOT NULL,
      authorized_at TEXT NOT NULL,
      expected_settlement_date TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE wallet_top_up_profiles (
      id TEXT PRIMARY KEY,
      target_account_id TEXT NOT NULL,
      funding_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      threshold_amount REAL NOT NULL,
      amount_mode TEXT NOT NULL,
      target_balance_amount REAL NOT NULL,
      fixed_amount REAL NOT NULL,
      cooldown_seconds INTEGER NOT NULL,
      is_enabled INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE wallet_top_up_suggestions (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      target_account_id TEXT NOT NULL,
      funding_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      amount_mode TEXT NOT NULL,
      current_available_balance REAL NOT NULL,
      funding_available_balance REAL NOT NULL,
      threshold_amount REAL NOT NULL,
      suggested_amount REAL NOT NULL,
      funding_shortfall REAL NOT NULL,
      funding_sufficient INTEGER NOT NULL,
      status TEXT NOT NULL,
      evaluated_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE wallet_top_up_audits (
      id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      profile_id TEXT NOT NULL,
      suggestion_id TEXT,
      details_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE production_migration_markers (
      marker_key TEXT PRIMARY KEY,
      status TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE taiwan_business_calendar_days (
      calendar_date TEXT PRIMARY KEY,
      is_business_day INTEGER NOT NULL
    )
  ''');
}

Future<void> _insertSampleRows(Database db) async {
  await db.insert('accounts', <String, Object?>{
    'id': 'bank-1',
    'name': '薪轉銀行',
    'type': 'bank',
    'suffix': '0001',
  });
  await db.insert('accounts', <String, Object?>{
    'id': 'debit-1',
    'name': '簽帳金融卡',
    'type': 'debitCard',
    'suffix': '1234',
  });
  await db.insert('accounts', <String, Object?>{
    'id': 'wallet-1',
    'name': '電子錢包',
    'type': 'eWallet',
    'suffix': '',
  });
  await db.insert('transactions', <String, Object?>{
    'id': 'tx-1',
    'type': 'expense',
    'amount': 150,
    'note': '早餐',
  });
  await db.insert('merchants', <String, Object?>{
    'id': 'merchant-1',
    'name': '早餐店',
  });
  await db.insert('cloud_invoice_drafts', <String, Object?>{
    'id': 'draft-1',
    'operation_key': 'draft-op-1',
  });
  await db.insert('debit_card_profiles', <String, Object?>{
    'debit_card_account_id': 'debit-1',
    'linked_bank_account_id': 'bank-1',
    'currency_code': 'TWD',
    'settlement_business_days': 2,
    'is_enabled': 1,
  });
  await db.insert('debit_card_settlements', <String, Object?>{
    'id': 'settlement-1',
    'debit_card_account_id': 'debit-1',
    'linked_bank_account_id': 'bank-1',
    'transaction_id': 'tx-1',
    'amount': 150,
    'status': 'pending',
  });
  await db.insert('debit_card_authorization_audits', <String, Object?>{
    'request_id': 'request-1',
    'payload_fingerprint': List<String>.filled(64, 'a').join(),
    'transaction_id': 'tx-1',
    'settlement_id': 'settlement-1',
    'debit_card_account_id': 'debit-1',
    'linked_bank_account_id': 'bank-1',
    'amount': 150,
    'currency_code': 'TWD',
    'ledger_balance_before': 1000,
    'reserved_before': 0,
    'available_before': 1000,
    'available_after': 850,
    'authorized_at': '2026-06-28T07:00:00.000Z',
    'expected_settlement_date': '2026-06-30T07:00:00.000Z',
  });
  await db.insert('wallet_top_up_profiles', <String, Object?>{
    'id': 'profile-1',
    'target_account_id': 'wallet-1',
    'funding_account_id': 'bank-1',
    'currency_code': 'TWD',
    'threshold_amount': 100,
    'amount_mode': 'targetBalance',
    'target_balance_amount': 500,
    'fixed_amount': 0,
    'cooldown_seconds': 21600,
    'is_enabled': 1,
    'created_at': '2026-06-28T07:00:00.000Z',
    'updated_at': '2026-06-28T07:00:00.000Z',
  });
  await db.insert('wallet_top_up_suggestions', <String, Object?>{
    'id': 'suggestion-1',
    'profile_id': 'profile-1',
    'target_account_id': 'wallet-1',
    'funding_account_id': 'bank-1',
    'currency_code': 'TWD',
    'amount_mode': 'targetBalance',
    'current_available_balance': 50,
    'funding_available_balance': 1000,
    'threshold_amount': 100,
    'suggested_amount': 450,
    'funding_shortfall': 0,
    'funding_sufficient': 1,
    'status': 'pending',
    'evaluated_at': '2026-06-28T07:01:00.000Z',
    'created_at': '2026-06-28T07:01:00.000Z',
    'updated_at': '2026-06-28T07:01:00.000Z',
  });
  await db.insert('wallet_top_up_audits', <String, Object?>{
    'id': 'audit-1',
    'event_type': 'suggestionCreated',
    'profile_id': 'profile-1',
    'suggestion_id': 'suggestion-1',
    'details_json': '{}',
    'created_at': '2026-06-28T07:01:00.000Z',
  });
  await db.insert('production_migration_markers', <String, Object?>{
    'marker_key': 'merchant-v13',
    'status': 'completed',
  });
  await db.insert('app_settings', <String, Object?>{
    'key': 'restore_source.uri',
    'value': 'content://device-bound-source',
  });
  await db.insert('taiwan_business_calendar_days', <String, Object?>{
    'calendar_date': '2026-06-29',
    'is_business_day': 1,
  });
}
