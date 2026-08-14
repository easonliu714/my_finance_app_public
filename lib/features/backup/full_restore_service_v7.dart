import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v21_wallet_top_up_execution.dart';
import 'full_backup_scope.dart';
import 'full_restore_service.dart';

class FullRestoreServiceV7 extends FullRestoreService {
  const FullRestoreServiceV7({super.backupService});

  @override
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

  @override
  Future<FullRestoreResult> restoreFromEnvelope(
    Database db,
    Map<String, Object?> envelope, {
    required String confirmationText,
    DateTime? preRestoreBackupCreatedAt,
    String sourcePlatform = 'android',
    Future<String> Function(Map<String, Object?> envelope)?
        persistPreRestoreBackup,
  }) async {
    final normalized = _normalizeScopeV6(envelope);
    _validateExecutionReferences(normalized);
    final hasExecutionTable = await _tableExists(
      db,
      'wallet_top_up_executions',
    );
    if (hasExecutionTable) {
      await dropWalletTopUpExecutionImmutabilityTriggers(db);
    }
    try {
      return await super.restoreFromEnvelope(
        db,
        normalized,
        confirmationText: confirmationText,
        preRestoreBackupCreatedAt: preRestoreBackupCreatedAt,
        sourcePlatform: sourcePlatform,
        persistPreRestoreBackup: persistPreRestoreBackup,
      );
    } finally {
      if (hasExecutionTable) {
        await createWalletTopUpExecutionImmutabilityTriggers(db);
      }
    }
  }

  Map<String, Object?> _normalizeScopeV6(
    Map<String, Object?> envelope,
  ) {
    final metadataRaw = envelope['metadata'];
    final dataRaw = envelope['data'];
    if (metadataRaw is! Map || dataRaw is! Map) return envelope;
    final metadata = Map<String, Object?>.from(metadataRaw);
    final data = Map<String, Object?>.from(dataRaw);
    if (metadata['backup_scope_version'] == 6) {
      metadata['backup_scope_version'] = 7;
      metadata['included_tables'] = FullBackupScope.backupTableNames;
      data.putIfAbsent(
        'wallet_top_up_executions',
        () => const <Object?>[],
      );
    }
    return <String, Object?>{
      ...envelope,
      'metadata': metadata,
      'data': data,
    };
  }

  void _validateExecutionReferences(Map<String, Object?> envelope) {
    final dataRaw = envelope['data'];
    if (dataRaw is! Map) return;
    final data = Map<String, Object?>.from(dataRaw);
    final executions = data['wallet_top_up_executions'];
    if (executions == null) return;
    if (executions is! List) {
      throw const FullRestoreException(
        '備份檔 wallet_top_up_executions 必須是陣列',
      );
    }
    final accountIds = _ids(data['accounts']);
    final transactionIds = _ids(data['transactions']);
    final profileIds = _ids(data['wallet_top_up_profiles']);
    for (final raw in executions) {
      if (raw is! Map) {
        throw const FullRestoreException(
          'wallet_top_up_executions 包含非 object row',
        );
      }
      final row = Map<String, Object?>.from(raw);
      _requireReference(
        row,
        column: 'source_transaction_id',
        ids: transactionIds,
      );
      _requireReference(
        row,
        column: 'generated_transfer_transaction_id',
        ids: transactionIds,
        nullable: true,
      );
      _requireReference(row, column: 'profile_id', ids: profileIds);
      _requireReference(row, column: 'target_account_id', ids: accountIds);
      _requireReference(row, column: 'funding_account_id', ids: accountIds);
    }
  }

  Set<String> _ids(Object? rawRows) {
    if (rawRows is! List) return const <String>{};
    return rawRows
        .whereType<Map>()
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  void _requireReference(
    Map<String, Object?> row, {
    required String column,
    required Set<String> ids,
    bool nullable = false,
  }) {
    final value = row[column]?.toString() ?? '';
    if (nullable && value.isEmpty) return;
    if (value.isEmpty || !ids.contains(value)) {
      throw FullRestoreException(
        'wallet_top_up_executions 參照無效：$column=$value',
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
}
