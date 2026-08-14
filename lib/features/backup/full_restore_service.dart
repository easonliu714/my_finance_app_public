import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v20_wallet_top_up_tables.dart';

import 'full_backup_scope.dart';
import 'full_backup_service.dart';

class FullRestoreService {
  const FullRestoreService({this.backupService = const FullBackupService()});

  static const String destructiveConfirmationText = 'RESTORE';

  final FullBackupService backupService;

  Future<FullRestoreResult> restoreFromJson(
    Database db,
    String jsonText, {
    required String confirmationText,
    DateTime? preRestoreBackupCreatedAt,
    String sourcePlatform = 'android',
    Future<String> Function(Map<String, Object?> envelope)?
        persistPreRestoreBackup,
  }) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      throw const FullRestoreException(
        '備份檔格式錯誤：root 必須是 JSON object',
      );
    }
    return restoreFromEnvelope(
      db,
      decoded,
      confirmationText: confirmationText,
      preRestoreBackupCreatedAt: preRestoreBackupCreatedAt,
      sourcePlatform: sourcePlatform,
      persistPreRestoreBackup: persistPreRestoreBackup,
    );
  }

  Future<FullRestoreResult> restoreFromEnvelope(
    Database db,
    Map<String, Object?> envelope, {
    required String confirmationText,
    DateTime? preRestoreBackupCreatedAt,
    String sourcePlatform = 'android',
    Future<String> Function(Map<String, Object?> envelope)?
        persistPreRestoreBackup,
  }) async {
    _validateConfirmation(confirmationText);
    _validateEnvelope(envelope);
    final metadata = envelope['metadata']! as Map<String, Object?>;
    final rawData = envelope['data']! as Map<String, Object?>;
    final data = _normalizedManagedData(metadata, rawData);
    final backupCounts = _managedBackupCounts(data);
    final preRestoreBackupEnvelope = await backupService.buildFullBackupEnvelope(
      db,
      createdAt: preRestoreBackupCreatedAt,
      sourcePlatform: sourcePlatform,
    );
    final preRestoreBackupPath = persistPreRestoreBackup == null
        ? null
        : await persistPreRestoreBackup(preRestoreBackupEnvelope);

    ReferentialIntegrityAudit? audit;
    await db.transaction((txn) async {
      await _assertRequiredTablesExist(txn);
      final hasWalletTopUpAudits =
          await _tableExists(txn, 'wallet_top_up_audits');
      if (hasWalletTopUpAudits) {
        await dropWalletTopUpAuditImmutabilityTriggers(txn);
      }
      try {
        await _clearTables(txn);
        for (final tableName in FullBackupService.backupTableNames) {
          await _restoreTableRows(txn, tableName, data[tableName]);
        }
        await _validateRestoredRowCounts(txn, backupCounts);
        final transactionAudit = await auditReferentialIntegrity(txn);
        if (!transactionAudit.passed) {
          throw FullRestoreException(
            '完整還原驗證失敗：'
            '${transactionAudit.blockingIssues.map((issue) => issue.code).join(', ')}',
          );
        }
        audit = transactionAudit;
      } finally {
        if (hasWalletTopUpAudits) {
          await createWalletTopUpAuditImmutabilityTriggers(txn);
        }
      }
    });

    return FullRestoreResult(
      preRestoreBackupEnvelope: preRestoreBackupEnvelope,
      preRestoreBackupPath: preRestoreBackupPath,
      audit: audit ??
          const ReferentialIntegrityAudit(
            issues: <ReferentialIntegrityIssue>[],
          ),
    );
  }

  Future<ReferentialIntegrityAudit> auditReferentialIntegrity(
    DatabaseExecutor db,
  ) async {
    final issues = <ReferentialIntegrityIssue>[];
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_installment_schedule_items',
      childColumn: 'plan_id',
      parentTable: 'credit_card_installment_plans',
      parentColumn: 'id',
      code: 'orphan_installment_schedule_plan',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_installment_schedule_items',
      childColumn: 'generated_transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_installment_generated_transaction',
      ignoreNullOrEmpty: true,
      blocking: false,
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_installment_plans',
      childColumn: 'card_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_installment_card',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_installment_plans',
      childColumn: 'source_transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_installment_source_transaction',
      ignoreNullOrEmpty: true,
      blocking: false,
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_statement_events',
      childColumn: 'card_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_statement_card',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_bank_rule_assignments',
      childColumn: 'card_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_bank_rule_assignment_card',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'credit_card_bank_rule_assignments',
      childColumn: 'profile_id',
      parentTable: 'credit_card_bank_rule_profiles',
      parentColumn: 'id',
      code: 'orphan_bank_rule_assignment_profile',
      ignoreNullOrEmpty: true,
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_profiles',
      childColumn: 'debit_card_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_profile_account',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_profiles',
      childColumn: 'linked_bank_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_profile_bank',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlements',
      childColumn: 'debit_card_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_settlement_account',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlements',
      childColumn: 'linked_bank_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_settlement_bank',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlements',
      childColumn: 'transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_debit_card_settlement_transaction',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlements',
      childColumn: 'settlement_transfer_transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_debit_card_settlement_transfer',
      ignoreNullOrEmpty: true,
      blocking: false,
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_authorization_audits',
      childColumn: 'transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_debit_card_authorization_transaction',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_authorization_audits',
      childColumn: 'settlement_id',
      parentTable: 'debit_card_settlements',
      parentColumn: 'id',
      code: 'orphan_debit_card_authorization_settlement',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_authorization_audits',
      childColumn: 'debit_card_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_authorization_account',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_authorization_audits',
      childColumn: 'linked_bank_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_authorization_bank',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlement_confirmation_audits',
      childColumn: 'settlement_id',
      parentTable: 'debit_card_settlements',
      parentColumn: 'id',
      code: 'orphan_debit_card_confirmation_settlement',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlement_confirmation_audits',
      childColumn: 'source_transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_debit_card_confirmation_source_transaction',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlement_confirmation_audits',
      childColumn: 'transfer_transaction_id',
      parentTable: 'transactions',
      parentColumn: 'id',
      code: 'orphan_debit_card_confirmation_transfer_transaction',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlement_confirmation_audits',
      childColumn: 'debit_card_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_confirmation_account',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'debit_card_settlement_confirmation_audits',
      childColumn: 'linked_bank_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_debit_card_confirmation_bank',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_profiles',
      childColumn: 'target_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_profile_target',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_profiles',
      childColumn: 'funding_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_profile_funding',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_suggestions',
      childColumn: 'profile_id',
      parentTable: 'wallet_top_up_profiles',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_suggestion_profile',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_suggestions',
      childColumn: 'target_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_suggestion_target',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_suggestions',
      childColumn: 'funding_account_id',
      parentTable: 'accounts',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_suggestion_funding',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_audits',
      childColumn: 'profile_id',
      parentTable: 'wallet_top_up_profiles',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_audit_profile',
    );
    await _auditChildReference(
      db,
      issues,
      childTable: 'wallet_top_up_audits',
      childColumn: 'suggestion_id',
      parentTable: 'wallet_top_up_suggestions',
      parentColumn: 'id',
      code: 'orphan_wallet_top_up_audit_suggestion',
      ignoreNullOrEmpty: true,
    );
    await _auditEnabledWalletTopUpArchivedAccounts(db, issues);
    return ReferentialIntegrityAudit(issues: issues);
  }

  void _validateConfirmation(String confirmationText) {
    if (confirmationText.trim() != destructiveConfirmationText) {
      throw const FullRestoreException(
        '完整還原需要輸入 RESTORE 才能覆蓋目前資料',
      );
    }
  }

  void _validateEnvelope(Map<String, Object?> envelope) {
    final metadata = envelope['metadata'];
    final data = envelope['data'];
    if (metadata is! Map<String, Object?>) {
      throw const FullRestoreException('備份檔缺少 metadata');
    }
    if (data is! Map<String, Object?>) {
      throw const FullRestoreException('備份檔缺少 data');
    }
    if (metadata['app_name'] != FullBackupService.appName) {
      throw const FullRestoreException('備份檔 app_name 不相符');
    }

    final exportFormatVersion = metadata['export_format_version'];
    if (exportFormatVersion is! int ||
        !FullBackupScope.supportedExportFormatVersions.contains(
          exportFormatVersion,
        )) {
      throw const FullRestoreException('不支援的備份格式版本');
    }

    final schemaVersion = metadata['database_schema_version'];
    if (schemaVersion is! int) {
      throw const FullRestoreException(
        '備份檔 database_schema_version 格式錯誤',
      );
    }
    if (schemaVersion > FullBackupService.databaseSchemaVersion) {
      throw const FullRestoreException(
        '備份檔 schema version 高於目前 App 支援版本',
      );
    }
    if (metadata['export_mode'] != FullBackupService.exportModeFullBackup) {
      throw const FullRestoreException('目前只支援 full_backup 還原');
    }

    if (exportFormatVersion >= 2) {
      _validateV2Coverage(metadata, data);
    } else {
      _validateLegacyV1Data(data);
    }
  }

  void _validateV2Coverage(
    Map<String, Object?> metadata,
    Map<String, Object?> data,
  ) {
    final scopeVersion = metadata['backup_scope_version'];
    if (scopeVersion is! int ||
        !FullBackupScope.supportedBackupScopeVersions.contains(scopeVersion)) {
      throw const FullRestoreException('不支援的完整備份範圍版本');
    }
    if (metadata['coverage_complete'] != true) {
      throw const FullRestoreException('完整備份範圍未通過完整性驗證');
    }

    final unknownTables = metadata['unknown_tables'];
    final missingRequiredTables = metadata['missing_required_tables'];
    final includedTables = metadata['included_tables'];
    if (unknownTables is! List || unknownTables.isNotEmpty) {
      throw const FullRestoreException('完整備份包含未知資料表狀態');
    }
    if (missingRequiredTables is! List ||
        missingRequiredTables.isNotEmpty) {
      throw const FullRestoreException('完整備份缺少必要資料表');
    }
    if (includedTables is! List) {
      throw const FullRestoreException('完整備份缺少 included_tables');
    }

    final expectedTables = switch (scopeVersion) {
      2 => FullBackupScope.legacyScopeV2TableNames,
      3 => FullBackupScope.legacyScopeV3TableNames,
      4 => FullBackupScope.legacyScopeV4TableNames,
      5 => FullBackupScope.legacyScopeV5TableNames,
      _ => FullBackupService.backupTableNames,
    };
    final includedNames = includedTables.whereType<String>().toSet();
    if (!includedNames.containsAll(expectedTables)) {
      throw const FullRestoreException('完整備份受管資料表清單不完整');
    }

    for (final tableName in expectedTables) {
      if (!data.containsKey(tableName) || data[tableName] is! List) {
        throw FullRestoreException(
          '完整備份 V2 缺少資料表陣列：$tableName',
        );
      }
    }
    for (final tableName in FullBackupService.backupTableNames) {
      final rows = data[tableName];
      if (rows != null && rows is! List) {
        throw FullRestoreException('備份檔 $tableName 必須是陣列');
      }
    }
  }

  void _validateLegacyV1Data(Map<String, Object?> data) {
    for (final tableName in FullBackupService.backupTableNames) {
      final rows = data[tableName];
      if (rows != null && rows is! List) {
        throw FullRestoreException('備份檔 $tableName 必須是陣列');
      }
    }
    if (data['accounts'] is! List) {
      throw const FullRestoreException('備份檔缺少必要核心表 accounts');
    }
    if (data['transactions'] is! List) {
      throw const FullRestoreException(
        '備份檔缺少必要核心表 transactions',
      );
    }
  }

  Map<String, Object?> _normalizedManagedData(
    Map<String, Object?> metadata,
    Map<String, Object?> rawData,
  ) {
    final normalized = Map<String, Object?>.from(rawData);
    final scopeVersion = metadata['backup_scope_version'];
    final isLegacyV1 = metadata['export_format_version'] == 1;
    if (scopeVersion == 2 || isLegacyV1) {
      for (final tableName in FullBackupScope.scopeV3OptionalForLegacyRestore) {
        normalized.putIfAbsent(tableName, () => const <Object?>[]);
      }
    }
    if (scopeVersion == 2 || scopeVersion == 3 || isLegacyV1) {
      for (final tableName in FullBackupScope.scopeV4OptionalForLegacyRestore) {
        normalized.putIfAbsent(tableName, () => const <Object?>[]);
      }
    }
    if (scopeVersion == 2 ||
        scopeVersion == 3 ||
        scopeVersion == 4 ||
        isLegacyV1) {
      for (final tableName in FullBackupScope.scopeV5OptionalForLegacyRestore) {
        normalized.putIfAbsent(tableName, () => const <Object?>[]);
      }
    }
    if (scopeVersion == 2 ||
      scopeVersion == 3 ||
      scopeVersion == 4 ||
      scopeVersion == 5 ||
      isLegacyV1) {
    for (final tableName in FullBackupScope.scopeV6OptionalForLegacyRestore) {
      normalized.putIfAbsent(tableName, () => const <Object?>[]);
    }
  }
  for (final tableName in FullBackupService.backupTableNames) {
    normalized.putIfAbsent(tableName, () => const <Object?>[]);
  }
    return normalized;
  }

  Map<String, int> _managedBackupCounts(Map<String, Object?> data) {
    return <String, int>{
      for (final tableName in FullBackupService.backupTableNames)
        tableName: data[tableName] is List
            ? (data[tableName]! as List).length
            : 0,
    };
  }

  Future<void> _assertRequiredTablesExist(DatabaseExecutor db) async {
    for (final tableName in FullBackupScope.requiredTableNames) {
      if (!await _tableExists(db, tableName)) {
        throw FullRestoreException('目前資料庫缺少必要核心表 $tableName');
      }
    }
  }

  Future<void> _clearTables(DatabaseExecutor db) async {
    for (final tableName in FullBackupService.backupTableNames.reversed) {
      if (await _tableExists(db, tableName)) await db.delete(tableName);
    }
  }

  Future<void> _restoreTableRows(
    DatabaseExecutor db,
    String tableName,
    Object? rawRows,
  ) async {
    if (!await _tableExists(db, tableName)) return;
    final rows = rawRows is List ? rawRows : const <Object?>[];
    final columns = await _tableColumns(db, tableName);
    for (final rawRow in rows) {
      if (rawRow is! Map) {
        throw FullRestoreException(
          '備份檔 $tableName 包含非 object row',
        );
      }
      final row = Map<String, Object?>.from(rawRow)
        ..removeWhere((key, value) => !columns.contains(key));
      await db.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _validateRestoredRowCounts(
    DatabaseExecutor db,
    Map<String, int> backupCounts,
  ) async {
    for (final entry in backupCounts.entries) {
      if (!await _tableExists(db, entry.key)) continue;
      final restoredCount = await _rowCount(db, entry.key);
      if (restoredCount != entry.value) {
        throw FullRestoreException(
          '完整還原驗證失敗：${entry.key} 筆數不一致，'
          '目前 $restoredCount / 備份 ${entry.value}',
        );
      }
    }
  }

  Future<int> _rowCount(DatabaseExecutor db, String tableName) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    final count = rows.first['c'];
    if (count is int) return count;
    if (count is num) return count.toInt();
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  Future<void> _auditEnabledWalletTopUpArchivedAccounts(
    DatabaseExecutor db,
    List<ReferentialIntegrityIssue> issues,
  ) async {
    if (!await _tableExists(db, 'wallet_top_up_profiles') ||
        !await _tableExists(db, 'accounts')) {
      return;
    }
    final rows = await db.rawQuery('''
      SELECT p.id AS profile_id, a.id AS account_id, COUNT(*) AS issue_count
      FROM wallet_top_up_profiles p
      JOIN accounts a
        ON a.id = p.target_account_id OR a.id = p.funding_account_id
      WHERE p.is_enabled = 1 AND a.is_archived = 1
      GROUP BY p.id, a.id
    ''');
    for (final row in rows) {
      issues.add(
        ReferentialIntegrityIssue(
          code: 'enabled_wallet_top_up_profile_archived_account',
          tableName: 'wallet_top_up_profiles',
          columnName: 'target_account_id/funding_account_id',
          value: '${row['profile_id']}:${row['account_id']}',
          count: (row['issue_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
  }

  Future<void> _auditChildReference(
    DatabaseExecutor db,
    List<ReferentialIntegrityIssue> issues, {
    required String childTable,
    required String childColumn,
    required String parentTable,
    required String parentColumn,
    required String code,
    bool ignoreNullOrEmpty = false,
    bool blocking = true,
  }) async {
    if (!await _tableExists(db, childTable) ||
        !await _tableExists(db, parentTable)) {
      return;
    }
    if (!await _columnExists(db, childTable, childColumn) ||
        !await _columnExists(db, parentTable, parentColumn)) {
      return;
    }
    final childValueFilter = ignoreNullOrEmpty
        ? 'AND c.$childColumn IS NOT NULL AND c.$childColumn != ?'
        : '';
    final args = ignoreNullOrEmpty ? <Object?>[''] : null;
    final rows = await db.rawQuery('''
      SELECT c.$childColumn AS child_value, COUNT(*) AS issue_count
      FROM $childTable c
      LEFT JOIN $parentTable p ON c.$childColumn = p.$parentColumn
      WHERE p.$parentColumn IS NULL
      $childValueFilter
      GROUP BY c.$childColumn
    ''', args);
    for (final row in rows) {
      issues.add(
        ReferentialIntegrityIssue(
          code: code,
          tableName: childTable,
          columnName: childColumn,
          value: row['child_value']?.toString() ?? '',
          count: (row['issue_count'] as num?)?.toInt() ?? 0,
          blocking: blocking,
        ),
      );
    }
  }

  Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(
    DatabaseExecutor db,
    String tableName,
    String columnName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows.any((row) => row['name'] == columnName);
  }

  Future<Set<String>> _tableColumns(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
  }
}

class FullRestoreResult {
  const FullRestoreResult({
    required this.preRestoreBackupEnvelope,
    required this.audit,
    this.preRestoreBackupPath,
  });

  final Map<String, Object?> preRestoreBackupEnvelope;
  final String? preRestoreBackupPath;
  final ReferentialIntegrityAudit audit;
}

class ReferentialIntegrityAudit {
  const ReferentialIntegrityAudit({required this.issues});

  final List<ReferentialIntegrityIssue> issues;
  Iterable<ReferentialIntegrityIssue> get blockingIssues =>
      issues.where((issue) => issue.blocking);
  Iterable<ReferentialIntegrityIssue> get warningIssues =>
      issues.where((issue) => !issue.blocking);
  bool get passed => blockingIssues.isEmpty;
}

class ReferentialIntegrityIssue {
  const ReferentialIntegrityIssue({
    required this.code,
    required this.tableName,
    required this.columnName,
    required this.value,
    required this.count,
    this.blocking = true,
  });

  final String code;
  final String tableName;
  final String columnName;
  final String value;
  final int count;
  final bool blocking;
}

class FullRestoreException implements Exception {
  const FullRestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
