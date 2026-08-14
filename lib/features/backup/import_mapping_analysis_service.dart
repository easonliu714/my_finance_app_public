import 'package:sqflite/sqflite.dart';

import 'readable_import_service.dart';

class ImportMappingAnalysisService {
  const ImportMappingAnalysisService();

  static const String appVersion = '3.18.0+235';
  static const String phase = 'P3.18.0';
  static const List<String> accountReferenceFields = <String>['account_name', 'from_account_name', 'to_account_name'];

  Future<ImportMappingAnalysisResult> analyze(DatabaseExecutor db, ReadableImportDryRunResult dryRunResult) async {
    final accounts = await _loadAccountCandidates(db);
    final rowsForMapping = _rowsThatCanAffectCommit(dryRunResult);
    final accountReferences = _collectAccountReferences(rowsForMapping)
        .map((reference) => _analyzeAccountReference(reference, accounts))
        .toList()
      ..sort((a, b) {
        final fieldCompare = a.fieldName.compareTo(b.fieldName);
        if (fieldCompare != 0) return fieldCompare;
        return a.value.compareTo(b.value);
      });
    final categories = _collectDistinctValues(rowsForMapping, 'category');
    final merchants = _collectMerchantValues(rowsForMapping, accounts);
    return ImportMappingAnalysisResult(
      accountReferences: accountReferences,
      categories: categories,
      merchants: merchants,
      summary: ImportMappingConflictSummary(
        missingAccountCount: accountReferences.where((reference) => reference.status == ImportAccountMappingStatus.missing).length,
        ambiguousAccountCount: accountReferences.where((reference) => reference.status == ImportAccountMappingStatus.ambiguous).length,
        unmappedCategoryCount: categories.length,
        unmappedMerchantCount: merchants.length,
      ),
    );
  }

  ImportAccountReferenceAnalysis _analyzeAccountReference(_ImportAccountReference reference, List<ImportAccountCandidate> accounts) {
    final displayMatches = accounts.where((account) => _accountMatches(account, reference.value, allowNameOnly: false)).toList();
    if (displayMatches.length == 1) {
      return ImportAccountReferenceAnalysis(fieldName: reference.fieldName, value: reference.value, status: ImportAccountMappingStatus.matched, candidates: displayMatches);
    }
    if (displayMatches.length > 1) {
      return ImportAccountReferenceAnalysis(fieldName: reference.fieldName, value: reference.value, status: ImportAccountMappingStatus.ambiguous, candidates: displayMatches);
    }

    final nameMatches = accounts.where((account) => _accountMatches(account, reference.value, allowDisplayName: false)).toList();
    if (nameMatches.length == 1) {
      return ImportAccountReferenceAnalysis(fieldName: reference.fieldName, value: reference.value, status: ImportAccountMappingStatus.matched, candidates: nameMatches);
    }
    if (nameMatches.length > 1) {
      return ImportAccountReferenceAnalysis(fieldName: reference.fieldName, value: reference.value, status: ImportAccountMappingStatus.ambiguous, candidates: nameMatches);
    }
    return ImportAccountReferenceAnalysis(fieldName: reference.fieldName, value: reference.value, status: ImportAccountMappingStatus.missing, candidates: const <ImportAccountCandidate>[]);
  }

  List<ReadableImportRowResult> _rowsThatCanAffectCommit(ReadableImportDryRunResult dryRunResult) {
    return dryRunResult.rows.where((row) => row.status == ReadableImportRowStatus.readyToInsert).toList(growable: false);
  }

  Set<_ImportAccountReference> _collectAccountReferences(Iterable<ReadableImportRowResult> rows) {
    final references = <_ImportAccountReference>{};
    for (final row in rows) {
      for (final fieldName in accountReferenceFields) {
        final value = row.row[fieldName]?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        references.add(_ImportAccountReference(fieldName: fieldName, value: value));
      }
    }
    return references;
  }

  List<String> _collectDistinctValues(Iterable<ReadableImportRowResult> rows, String fieldName) {
    final values = <String>{};
    for (final row in rows) {
      final value = row.row[fieldName]?.toString().trim() ?? '';
      if (value.isNotEmpty) values.add(value);
    }
    return values.toList()..sort();
  }

  List<String> _collectMerchantValues(Iterable<ReadableImportRowResult> rows, List<ImportAccountCandidate> accounts) {
    final accountReferenceValues = _collectAccountReferences(rows).map((reference) => _normalizeLoose(reference.value)).toSet();
    final values = <String>{};
    for (final row in rows) {
      final value = row.row['merchant_name']?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      if (accountReferenceValues.contains(_normalizeLoose(value))) continue;
      if (_looksLikeKnownAccount(value, accounts)) continue;
      values.add(value);
    }
    return values.toList()..sort();
  }

  Future<List<ImportAccountCandidate>> _loadAccountCandidates(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'accounts')) return const <ImportAccountCandidate>[];
    final columns = await _columnNames(db, 'accounts');
    final rows = await db.query('accounts', orderBy: _accountsOrderBy(columns));
    return rows.map((row) {
      final id = row['id']?.toString() ?? '';
      final name = row['name']?.toString() ?? '';
      final suffix = columns.contains('suffix') ? row['suffix']?.toString() ?? '' : '';
      return ImportAccountCandidate(id: id, name: name, suffix: suffix);
    }).where((account) => account.name.trim().isNotEmpty).toList();
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.query('sqlite_master', columns: const <String>['name'], where: 'type = ? AND name = ?', whereArgs: <Object?>['table', tableName], limit: 1);
    return rows.isNotEmpty;
  }

  Future<Set<String>> _columnNames(DatabaseExecutor db, String tableName) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows.map((row) => row['name']).whereType<String>().toSet();
  }

  String? _accountsOrderBy(Set<String> columns) {
    final orderBy = <String>[];
    if (columns.contains('name')) orderBy.add('name ASC');
    if (columns.contains('suffix')) orderBy.add('suffix ASC');
    if (columns.contains('id')) orderBy.add('id ASC');
    return orderBy.isEmpty ? null : orderBy.join(', ');
  }

  bool _looksLikeKnownAccount(String value, List<ImportAccountCandidate> accounts) {
    return accounts.any((account) => _accountMatches(account, value));
  }

  bool _accountMatches(
    ImportAccountCandidate account,
    String value, {
    bool allowNameOnly = true,
    bool allowDisplayName = true,
  }) {
    final normalizedValue = _normalizeLoose(value);
    final compactValue = _normalizeCompact(value);
    final variants = <String>{};
    if (allowNameOnly) variants.addAll(_accountNameVariants(account));
    if (allowDisplayName) variants.addAll(_accountDisplayVariants(account));
    return variants.any((variant) => _normalizeLoose(variant) == normalizedValue || _normalizeCompact(variant) == compactValue);
  }

  Set<String> _accountNameVariants(ImportAccountCandidate account) {
    return <String>{account.name};
  }

  Set<String> _accountDisplayVariants(ImportAccountCandidate account) {
    final suffix = account.suffix.trim();
    if (suffix.isEmpty) return <String>{account.name};
    return <String>{
      account.displayName,
      '${account.name} $suffix',
      '${account.name} • $suffix',
      '${account.name}・$suffix',
      '${account.name} - $suffix',
      '${account.name}($suffix)',
      '${account.name}（$suffix）',
    };
  }

  String _normalizeLoose(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeCompact(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s•・\-()（）]+'), '');
  }
}

class ImportMappingAnalysisResult {
  const ImportMappingAnalysisResult({required this.accountReferences, required this.categories, required this.merchants, required this.summary});

  final List<ImportAccountReferenceAnalysis> accountReferences;
  final List<String> categories;
  final List<String> merchants;
  final ImportMappingConflictSummary summary;
}

class ImportMappingConflictSummary {
  const ImportMappingConflictSummary({required this.missingAccountCount, required this.ambiguousAccountCount, required this.unmappedCategoryCount, required this.unmappedMerchantCount});

  final int missingAccountCount;
  final int ambiguousAccountCount;
  final int unmappedCategoryCount;
  final int unmappedMerchantCount;
}

class ImportAccountReferenceAnalysis {
  const ImportAccountReferenceAnalysis({required this.fieldName, required this.value, required this.status, required this.candidates});

  final String fieldName;
  final String value;
  final ImportAccountMappingStatus status;
  final List<ImportAccountCandidate> candidates;
}

class ImportAccountCandidate {
  const ImportAccountCandidate({required this.id, required this.name, required this.suffix});

  final String id;
  final String name;
  final String suffix;
  String get displayName => suffix.trim().isEmpty ? name : '$name $suffix';
}

enum ImportAccountMappingStatus { matched, missing, ambiguous }

class _ImportAccountReference {
  const _ImportAccountReference({required this.fieldName, required this.value});

  final String fieldName;
  final String value;

  @override
  bool operator ==(Object other) => identical(this, other) || other is _ImportAccountReference && other.fieldName == fieldName && other.value == value;

  @override
  int get hashCode => Object.hash(fieldName, value);
}
