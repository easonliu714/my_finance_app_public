import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class ReadableImportService {
  const ReadableImportService();

  static const String appVersion = '3.4.2+132';
  static const String phase = 'P3.4.2';
  static const Set<String> supportedTransactionTypes = <String>{'income', 'expense', 'transfer', 'loan'};
  static const List<String> requiredTransactionColumns = <String>['id', 'type', 'occurred_at', 'amount'];

  Future<ReadableImportDryRunResult> dryRunTransactionsCsv(DatabaseExecutor db, String csvText) async {
    final parsed = _parseCsv(csvText);
    if (parsed.isEmpty) return const ReadableImportDryRunResult(totalRows: 0, validRows: 0, invalidRows: 0, duplicateRows: 0, readyToInsertRows: 0, rows: <ReadableImportRowResult>[]);
    final header = parsed.first;
    final results = <ReadableImportRowResult>[];
    for (var index = 1; index < parsed.length; index += 1) {
      final values = parsed[index];
      if (values.every((value) => value.trim().isEmpty)) continue;
      final row = <String, Object?>{};
      for (var columnIndex = 0; columnIndex < header.length; columnIndex += 1) {
        row[header[columnIndex]] = columnIndex < values.length ? values[columnIndex] : '';
      }
      results.add(await _validateTransactionRow(db, row, sourceRowIndex: index + 1));
    }
    return _summarize(results);
  }

  Future<ReadableImportDryRunResult> dryRunTransactionsJson(DatabaseExecutor db, String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) throw const ReadableImportException('JSON root 必須是 object');
    final data = decoded['data'];
    if (data is! List) throw const ReadableImportException('transactions JSON 缺少 data array');
    final results = <ReadableImportRowResult>[];
    for (var index = 0; index < data.length; index += 1) {
      final rawRow = data[index];
      if (rawRow is! Map) {
        results.add(const ReadableImportRowResult(sourceRowIndex: 0, row: <String, Object?>{}, status: ReadableImportRowStatus.invalid, errors: <String>['row 必須是 object']));
        continue;
      }
      results.add(await _validateTransactionRow(db, Map<String, Object?>.from(rawRow), sourceRowIndex: index + 1));
    }
    return _summarize(results);
  }

  Future<ReadableImportCommitResult> commitReadyTransactions(
    DatabaseExecutor db,
    ReadableImportDryRunResult dryRunResult, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw const ReadableImportException('尚未確認匯入，拒絕寫入正式資料');
    if (!await _tableExists(db, 'transactions')) throw const ReadableImportException('找不到 transactions 資料表，無法匯入');

    final commitRows = dryRunResult.rows.where((row) => row.status == ReadableImportRowStatus.readyToInsert).toList();
    var insertedRows = 0;
    var duplicateAtCommitRows = 0;
    final failures = <ReadableImportCommitFailure>[];

    await _runInTransactionIfPossible(db, (executor) async {
      for (final row in commitRows) {
        final id = row.row['id']?.toString().trim() ?? '';
        if (await _transactionIdExists(executor, id)) {
          duplicateAtCommitRows += 1;
          continue;
        }
        try {
          await executor.insert('transactions', _normalizeTransactionRow(row.row), conflictAlgorithm: ConflictAlgorithm.abort);
          insertedRows += 1;
        } catch (error) {
          failures.add(ReadableImportCommitFailure(sourceRowIndex: row.sourceRowIndex, id: id, message: error.toString()));
        }
      }
    });

    final skippedRows = dryRunResult.rows.length - commitRows.length;
    return ReadableImportCommitResult(
      insertedRows: insertedRows,
      skippedRows: skippedRows,
      duplicateAtCommitRows: duplicateAtCommitRows,
      failedRows: failures.length,
      invalidRows: dryRunResult.invalidRows,
      failures: failures,
      blockingIssues: const <String>[],
    );
  }

  Future<ReadableImportRowResult> _validateTransactionRow(DatabaseExecutor db, Map<String, Object?> row, {required int sourceRowIndex}) async {
    final errors = <String>[];
    for (final column in requiredTransactionColumns) {
      if ((row[column]?.toString().trim() ?? '').isEmpty) errors.add('$column 為必填');
    }
    final id = row['id']?.toString().trim() ?? '';
    final type = row['type']?.toString().trim() ?? '';
    if (type.isNotEmpty && !supportedTransactionTypes.contains(type)) errors.add('type 不支援：$type');
    final amountText = row['amount']?.toString().trim() ?? '';
    if (amountText.isNotEmpty && double.tryParse(amountText) == null) errors.add('amount 不是有效數字');
    final occurredAtText = row['occurred_at']?.toString().trim() ?? '';
    if (occurredAtText.isNotEmpty && DateTime.tryParse(occurredAtText) == null) errors.add('occurred_at 不是有效日期');
    if (errors.isNotEmpty) return ReadableImportRowResult(sourceRowIndex: sourceRowIndex, row: row, status: ReadableImportRowStatus.invalid, errors: errors);
    if (await _transactionIdExists(db, id)) return ReadableImportRowResult(sourceRowIndex: sourceRowIndex, row: row, status: ReadableImportRowStatus.duplicate, errors: const <String>[]);
    return ReadableImportRowResult(sourceRowIndex: sourceRowIndex, row: row, status: ReadableImportRowStatus.readyToInsert, errors: const <String>[]);
  }

  ReadableImportDryRunResult _summarize(List<ReadableImportRowResult> rows) {
    final validRows = rows.where((row) => row.status != ReadableImportRowStatus.invalid).length;
    final invalidRows = rows.where((row) => row.status == ReadableImportRowStatus.invalid).length;
    final duplicateRows = rows.where((row) => row.status == ReadableImportRowStatus.duplicate).length;
    final readyRows = rows.where((row) => row.status == ReadableImportRowStatus.readyToInsert).length;
    return ReadableImportDryRunResult(totalRows: rows.length, validRows: validRows, invalidRows: invalidRows, duplicateRows: duplicateRows, readyToInsertRows: readyRows, rows: rows);
  }

  Future<bool> _transactionIdExists(DatabaseExecutor db, String id) async {
    if (id.isEmpty || !await _tableExists(db, 'transactions')) return false;
    final rows = await db.query('transactions', columns: const <String>['id'], where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isNotEmpty;
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.query('sqlite_master', columns: const <String>['name'], where: 'type = ? AND name = ?', whereArgs: <Object?>['table', tableName], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> _runInTransactionIfPossible(DatabaseExecutor db, Future<void> Function(DatabaseExecutor executor) action) async {
    if (db is Database) {
      await db.transaction((txn) => action(txn));
      return;
    }
    await action(db);
  }

  Map<String, Object?> _normalizeTransactionRow(Map<String, Object?> row) {
    final normalized = <String, Object?>{};
    for (final entry in row.entries) {
      final value = entry.value;
      if (entry.key == 'amount' || entry.key == 'base_amount' || entry.key == 'exchange_rate_to_base') {
        normalized[entry.key] = value == null || value.toString().trim().isEmpty ? null : double.parse(value.toString());
      } else {
        normalized[entry.key] = value;
      }
    }
    return normalized;
  }

  List<List<String>> _parseCsv(String csvText) {
    final rows = <List<String>>[];
    var currentRow = <String>[];
    final currentCell = StringBuffer();
    var inQuotes = false;
    for (var index = 0; index < csvText.length; index += 1) {
      final char = csvText[index];
      if (char == '"') {
        final nextIsQuote = inQuotes && index + 1 < csvText.length && csvText[index + 1] == '"';
        if (nextIsQuote) {
          currentCell.write('"');
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        currentRow.add(currentCell.toString());
        currentCell.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && index + 1 < csvText.length && csvText[index + 1] == '\n') index += 1;
        currentRow.add(currentCell.toString());
        rows.add(currentRow);
        currentRow = <String>[];
        currentCell.clear();
      } else {
        currentCell.write(char);
      }
    }
    if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentCell.toString());
      rows.add(currentRow);
    }
    return rows;
  }
}

class ReadableImportDryRunResult {
  const ReadableImportDryRunResult({required this.totalRows, required this.validRows, required this.invalidRows, required this.duplicateRows, required this.readyToInsertRows, required this.rows});

  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int readyToInsertRows;
  final List<ReadableImportRowResult> rows;
}

class ReadableImportCommitResult {
  const ReadableImportCommitResult({required this.insertedRows, required this.skippedRows, required this.duplicateAtCommitRows, required this.failedRows, this.invalidRows = 0, required this.failures, this.blockingIssues = const <String>[]});

  final int insertedRows;
  final int skippedRows;
  final int duplicateAtCommitRows;
  final int failedRows;
  final int invalidRows;
  final List<ReadableImportCommitFailure> failures;
  final List<String> blockingIssues;

  ReadableImportCommitResult copyWith({int? insertedRows, int? skippedRows, int? duplicateAtCommitRows, int? failedRows, int? invalidRows, List<ReadableImportCommitFailure>? failures, List<String>? blockingIssues}) {
    return ReadableImportCommitResult(
      insertedRows: insertedRows ?? this.insertedRows,
      skippedRows: skippedRows ?? this.skippedRows,
      duplicateAtCommitRows: duplicateAtCommitRows ?? this.duplicateAtCommitRows,
      failedRows: failedRows ?? this.failedRows,
      invalidRows: invalidRows ?? this.invalidRows,
      failures: failures ?? this.failures,
      blockingIssues: blockingIssues ?? this.blockingIssues,
    );
  }
}

class ReadableImportCommitFailure {
  const ReadableImportCommitFailure({required this.sourceRowIndex, required this.id, required this.message});

  final int sourceRowIndex;
  final String id;
  final String message;
}

class ReadableImportRowResult {
  const ReadableImportRowResult({required this.sourceRowIndex, required this.row, required this.status, required this.errors});

  final int sourceRowIndex;
  final Map<String, Object?> row;
  final ReadableImportRowStatus status;
  final List<String> errors;
}

enum ReadableImportRowStatus { invalid, duplicate, readyToInsert }

class ReadableImportException implements Exception {
  const ReadableImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
