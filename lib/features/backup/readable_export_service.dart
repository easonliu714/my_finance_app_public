import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ReadableExportService {
  const ReadableExportService();

  static const String appVersion = '3.3.0+125';
  static const String phase = 'P3.3';

  static const List<String> transactionCsvColumns = <String>[
    'id',
    'type',
    'occurred_at',
    'amount',
    'currency_code',
    'base_amount',
    'category',
    'account_name',
    'from_account_name',
    'to_account_name',
    'member_name',
    'merchant_name',
    'tag_name',
    'note',
    'repayment_group_id',
    'created_at',
  ];

  Future<String> exportTransactionsCsv(DatabaseExecutor db) async {
    final rows = await _queryTable(db, 'transactions', orderBy: 'occurred_at ASC, created_at ASC, id ASC');
    final buffer = StringBuffer()..writeln(transactionCsvColumns.map(_escapeCsv).join(','));
    for (final row in rows) {
      buffer.writeln(transactionCsvColumns.map((column) => _escapeCsv(row[column])).join(','));
    }
    return buffer.toString();
  }

  Future<String> exportTransactionsJson(DatabaseExecutor db) async {
    final rows = await _queryTable(db, 'transactions', orderBy: 'occurred_at ASC, created_at ASC, id ASC');
    return _encodeReadableJson('transactions', rows);
  }

  Future<String> exportAccountsJson(DatabaseExecutor db) async {
    final rows = await _queryTable(db, 'accounts', orderBy: 'sort_order ASC, name ASC, suffix ASC, id ASC');
    return _encodeReadableJson('accounts', rows);
  }

  Future<File> writeTransactionsCsvFile(DatabaseExecutor db, {Directory? baseDirectory, DateTime? createdAt}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(p.join(root.path, 'readable_exports'));
    if (!exportDirectory.existsSync()) exportDirectory.createSync(recursive: true);
    final file = File(p.join(exportDirectory.path, _readableFileName('transactions', 'csv', createdAt ?? DateTime.now().toUtc())));
    return file.writeAsString(await exportTransactionsCsv(db), flush: true);
  }

  Future<File> writeTransactionsJsonFile(DatabaseExecutor db, {Directory? baseDirectory, DateTime? createdAt}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(p.join(root.path, 'readable_exports'));
    if (!exportDirectory.existsSync()) exportDirectory.createSync(recursive: true);
    final file = File(p.join(exportDirectory.path, _readableFileName('transactions', 'json', createdAt ?? DateTime.now().toUtc())));
    return file.writeAsString(await exportTransactionsJson(db), flush: true);
  }

  Future<File> writeAccountsJsonFile(DatabaseExecutor db, {Directory? baseDirectory, DateTime? createdAt}) async {
    final root = baseDirectory ?? await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(p.join(root.path, 'readable_exports'));
    if (!exportDirectory.existsSync()) exportDirectory.createSync(recursive: true);
    final file = File(p.join(exportDirectory.path, _readableFileName('accounts', 'json', createdAt ?? DateTime.now().toUtc())));
    return file.writeAsString(await exportAccountsJson(db), flush: true);
  }

  Future<List<Map<String, Object?>>> _queryTable(DatabaseExecutor db, String tableName, {String? orderBy}) async {
    if (!await _tableExists(db, tableName)) return <Map<String, Object?>>[];
    final safeOrderBy = await _safeOrderBy(db, tableName, orderBy);
    return db.query(tableName, orderBy: safeOrderBy);
  }

  Future<String?> _safeOrderBy(DatabaseExecutor db, String tableName, String? requestedOrderBy) async {
    if (requestedOrderBy == null) return null;
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final names = columns.map((column) => column['name']).whereType<String>().toSet();
    final parts = <String>[];
    for (final clause in requestedOrderBy.split(',')) {
      final trimmed = clause.trim();
      if (trimmed.isEmpty) continue;
      final columnName = trimmed.split(RegExp(r'\s+')).first;
      if (names.contains(columnName)) parts.add(trimmed);
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.query('sqlite_master', columns: const <String>['name'], where: 'type = ? AND name = ?', whereArgs: <Object?>['table', tableName], limit: 1);
    return rows.isNotEmpty;
  }

  String _encodeReadableJson(String exportType, List<Map<String, Object?>> rows) {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'metadata': <String, Object?>{
        'export_type': exportType,
        'app_name': 'my_finance_app',
        'app_version': appVersion,
        'phase': phase,
        'export_format': 'readable_json',
      },
      'data': rows,
    });
  }

  String _escapeCsv(Object? value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') || escaped.contains('\n') || escaped.contains('\r') || escaped.contains('"')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _readableFileName(String exportType, String extension, DateTime timestamp) {
    final safeTimestamp = timestamp.toUtc().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    return 'my_finance_app_${exportType}_readable_$safeTimestamp.$extension';
  }
}
