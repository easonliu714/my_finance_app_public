import 'dart:convert';

import 'package:http/http.dart' as http;

import 'taiwan_tax_id.dart';

enum TaiwanBusinessRegistryEntityType {
  company,
  business,
  branch,
}

enum TaiwanBusinessRegistryLookupStatus {
  found,
  notFound,
  invalidTaxId,
  unauthorized,
  unavailable,
  invalidResponse,
}

enum TaiwanBusinessRegistryNameMatch {
  exact,
  partial,
  conflict,
  missingObservedName,
  notFound,
  unavailable,
}

class TaiwanBusinessRegistryRecord {
  const TaiwanBusinessRegistryRecord({
    required this.taxId,
    required this.name,
    required this.entityType,
    required this.sourceUrl,
  });

  final String taxId;
  final String name;
  final TaiwanBusinessRegistryEntityType entityType;
  final String sourceUrl;
}

class TaiwanBusinessRegistryLookupResult {
  const TaiwanBusinessRegistryLookupResult({
    required this.status,
    required this.taxId,
    this.records = const <TaiwanBusinessRegistryRecord>[],
    this.diagnostic = '',
  });

  final TaiwanBusinessRegistryLookupStatus status;
  final String taxId;
  final List<TaiwanBusinessRegistryRecord> records;
  final String diagnostic;

  bool get found =>
      status == TaiwanBusinessRegistryLookupStatus.found && records.isNotEmpty;
}

class TaiwanBusinessRegistryNameValidation {
  const TaiwanBusinessRegistryNameValidation({
    required this.match,
    required this.taxId,
    required this.observedMerchantName,
    required this.officialNames,
  });

  final TaiwanBusinessRegistryNameMatch match;
  final String taxId;
  final String observedMerchantName;
  final List<String> officialNames;

  bool get supportsCandidateExistence =>
      officialNames.isNotEmpty &&
      match != TaiwanBusinessRegistryNameMatch.notFound &&
      match != TaiwanBusinessRegistryNameMatch.unavailable;

  /// Registry evidence is corroboration only. It must never authorize an OCR
  /// repair by itself because a checksum-valid tax ID may still belong to an
  /// unrelated legal entity.
  bool get authorizesTaxIdRepair => false;

  /// This review layer never authorizes a formal invoice/transaction write.
  bool get authorizesFormalWrite => false;
}

class TaiwanBusinessRegistryHttpPayload {
  const TaiwanBusinessRegistryHttpPayload({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef TaiwanBusinessRegistryJsonFetcher =
    Future<TaiwanBusinessRegistryHttpPayload> Function(Uri uri);

class TaiwanBusinessRegistryService {
  TaiwanBusinessRegistryService({
    http.Client? client,
    TaiwanBusinessRegistryJsonFetcher? fetcher,
    this.requestTimeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _fetcher = fetcher;

  static const String sourceName = '經濟部商工行政資料開放平臺';
  static const String attribution = '資料提供機關：經濟部商業發展署';
  static const String apiHost = 'data.gcis.nat.gov.tw';

  // Official GCIS dataset IDs documented by the platform API guide.
  static const String companyNameDatasetId =
      '9D17AE0D-09B5-4732-A8F4-81ADED04B679';
  static const String businessNameDatasetId =
      '855A3C87-003A-4930-AA4B-2F4130D713DC';
  static const String branchNameDatasetId =
      '367EE769-4D55-4752-AD6E-29164FA8AAB2';

  final http.Client _client;
  final TaiwanBusinessRegistryJsonFetcher? _fetcher;
  final Duration requestTimeout;

  /// Explicit lookup only. No capture/review code should call this method
  /// automatically; GCIS API access is governed by source-IP allowlisting and
  /// usage limits, so mobile capture must remain Local-first and fail-open to
  /// manual review when the registry is unavailable.
  Future<TaiwanBusinessRegistryLookupResult> lookup(String rawTaxId) async {
    final taxId = rawTaxId.replaceAll(RegExp(r'\D'), '');
    if (!isTaiwanTaxIdFormat(taxId) ||
        !hasValidTaiwanTaxIdChecksum(taxId)) {
      return TaiwanBusinessRegistryLookupResult(
        status: TaiwanBusinessRegistryLookupStatus.invalidTaxId,
        taxId: taxId,
        diagnostic: '統編格式或 checksum 未通過；未送出官方查詢。',
      );
    }

    final records = <TaiwanBusinessRegistryRecord>[];
    var sawInvalidResponse = false;
    for (final endpoint in _endpoints) {
      final uri = endpoint.uriFor(taxId);
      TaiwanBusinessRegistryHttpPayload payload;
      try {
        payload = await _fetch(uri);
      } catch (error) {
        return TaiwanBusinessRegistryLookupResult(
          status: TaiwanBusinessRegistryLookupStatus.unavailable,
          taxId: taxId,
          diagnostic: '官方商工資料連線失敗：${error.runtimeType}',
        );
      }

      if (_isUnauthorized(payload)) {
        return TaiwanBusinessRegistryLookupResult(
          status: TaiwanBusinessRegistryLookupStatus.unauthorized,
          taxId: taxId,
          diagnostic: '官方 API 拒絕來源 IP；需完成 GCIS 介接告知與白名單設定。',
        );
      }
      if (payload.statusCode < 200 || payload.statusCode >= 300) {
        return TaiwanBusinessRegistryLookupResult(
          status: TaiwanBusinessRegistryLookupStatus.unavailable,
          taxId: taxId,
          diagnostic: '官方 API 回應 HTTP ${payload.statusCode}。',
        );
      }

      final parsed = _parseOfficialNames(
        body: payload.body,
        nameKeys: endpoint.nameKeys,
      );
      if (!parsed.validJson) {
        sawInvalidResponse = true;
        continue;
      }
      for (final name in parsed.names) {
        records.add(
          TaiwanBusinessRegistryRecord(
            taxId: taxId,
            name: name,
            entityType: endpoint.entityType,
            sourceUrl: uri.toString(),
          ),
        );
      }
    }

    final uniqueRecords = <String, TaiwanBusinessRegistryRecord>{};
    for (final record in records) {
      final key = '${record.entityType.name}|${_normalizeMerchantName(record.name)}';
      uniqueRecords.putIfAbsent(key, () => record);
    }
    if (uniqueRecords.isNotEmpty) {
      return TaiwanBusinessRegistryLookupResult(
        status: TaiwanBusinessRegistryLookupStatus.found,
        taxId: taxId,
        records: List<TaiwanBusinessRegistryRecord>.unmodifiable(
          uniqueRecords.values,
        ),
      );
    }
    if (sawInvalidResponse) {
      return TaiwanBusinessRegistryLookupResult(
        status: TaiwanBusinessRegistryLookupStatus.invalidResponse,
        taxId: taxId,
        diagnostic: '官方 API 回應無法安全解析；未將其視為查無資料。',
      );
    }
    return TaiwanBusinessRegistryLookupResult(
      status: TaiwanBusinessRegistryLookupStatus.notFound,
      taxId: taxId,
      diagnostic: '公司、商業與分公司名稱查詢皆無結果。',
    );
  }

  TaiwanBusinessRegistryNameValidation validateMerchantName({
    required String observedMerchantName,
    required TaiwanBusinessRegistryLookupResult lookupResult,
  }) {
    final observed = observedMerchantName.trim();
    if (lookupResult.status == TaiwanBusinessRegistryLookupStatus.notFound) {
      return TaiwanBusinessRegistryNameValidation(
        match: TaiwanBusinessRegistryNameMatch.notFound,
        taxId: lookupResult.taxId,
        observedMerchantName: observed,
        officialNames: const <String>[],
      );
    }
    if (!lookupResult.found) {
      return TaiwanBusinessRegistryNameValidation(
        match: TaiwanBusinessRegistryNameMatch.unavailable,
        taxId: lookupResult.taxId,
        observedMerchantName: observed,
        officialNames: const <String>[],
      );
    }

    final officialNames = lookupResult.records
        .map((record) => record.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (observed.isEmpty) {
      return TaiwanBusinessRegistryNameValidation(
        match: TaiwanBusinessRegistryNameMatch.missingObservedName,
        taxId: lookupResult.taxId,
        observedMerchantName: observed,
        officialNames: officialNames,
      );
    }

    final normalizedObserved = _normalizeMerchantName(observed);
    if (officialNames.any(
      (name) => _normalizeMerchantName(name) == normalizedObserved,
    )) {
      return TaiwanBusinessRegistryNameValidation(
        match: TaiwanBusinessRegistryNameMatch.exact,
        taxId: lookupResult.taxId,
        observedMerchantName: observed,
        officialNames: officialNames,
      );
    }

    final observedCore = _merchantNameCore(observed);
    final partial = observedCore.length >= 2 &&
        officialNames.any((name) {
          final officialCore = _merchantNameCore(name);
          if (officialCore.length < 2) return false;
          return officialCore.contains(observedCore) ||
              observedCore.contains(officialCore);
        });
    return TaiwanBusinessRegistryNameValidation(
      match: partial
          ? TaiwanBusinessRegistryNameMatch.partial
          : TaiwanBusinessRegistryNameMatch.conflict,
      taxId: lookupResult.taxId,
      observedMerchantName: observed,
      officialNames: officialNames,
    );
  }

  Future<TaiwanBusinessRegistryHttpPayload> _fetch(Uri uri) async {
    final fetcher = _fetcher;
    if (fetcher != null) return fetcher(uri);
    final response = await _client.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
        'Accept-Language': 'zh-TW,zh;q=0.9',
      },
    ).timeout(requestTimeout);
    return TaiwanBusinessRegistryHttpPayload(
      statusCode: response.statusCode,
      body: utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  }

  bool _isUnauthorized(TaiwanBusinessRegistryHttpPayload payload) {
    if (payload.statusCode == 401 || payload.statusCode == 403) return true;
    final text = payload.body.replaceAll(RegExp(r'\s+'), '');
    return text.contains('非授權介接之IP') ||
        text.contains('未向維運團隊提出告知') ||
        text.contains('提出告知之IP不正確');
  }

  ({bool validJson, List<String> names}) _parseOfficialNames({
    required String body,
    required List<String> nameKeys,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return (validJson: false, names: const <String>[]);
    }
    final rows = _jsonRows(decoded);
    final names = <String>{};
    for (final row in rows) {
      for (final key in nameKeys) {
        final value = row[key];
        if (value is! String) continue;
        final name = value.trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
    return (validJson: true, names: List<String>.unmodifiable(names));
  }

  List<Map<String, dynamic>> _jsonRows(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (row) => row.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(growable: false);
    }
    if (decoded is Map) {
      final normalized = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      for (final key in const <String>['row', 'rows', 'data', 'result']) {
        final nested = normalized[key];
        if (nested is List) return _jsonRows(nested);
        if (nested is Map) return _jsonRows(nested);
      }
      return <Map<String, dynamic>>[normalized];
    }
    return const <Map<String, dynamic>>[];
  }

  static final List<_TaiwanBusinessRegistryEndpoint> _endpoints =
      <_TaiwanBusinessRegistryEndpoint>[
        const _TaiwanBusinessRegistryEndpoint(
          datasetId: companyNameDatasetId,
          filterField: 'Business_Accounting_NO',
          entityType: TaiwanBusinessRegistryEntityType.company,
          nameKeys: <String>['Company_Name'],
        ),
        const _TaiwanBusinessRegistryEndpoint(
          datasetId: businessNameDatasetId,
          filterField: 'President_No',
          entityType: TaiwanBusinessRegistryEntityType.business,
          nameKeys: <String>['Business_Name'],
        ),
        const _TaiwanBusinessRegistryEndpoint(
          datasetId: branchNameDatasetId,
          filterField: 'Branch_Office_Business_Accounting_NO',
          entityType: TaiwanBusinessRegistryEntityType.branch,
          nameKeys: <String>['Branch_Office_Name', 'Company_Name'],
        ),
      ];
}

class _TaiwanBusinessRegistryEndpoint {
  const _TaiwanBusinessRegistryEndpoint({
    required this.datasetId,
    required this.filterField,
    required this.entityType,
    required this.nameKeys,
  });

  final String datasetId;
  final String filterField;
  final TaiwanBusinessRegistryEntityType entityType;
  final List<String> nameKeys;

  Uri uriFor(String taxId) => Uri.https(
        TaiwanBusinessRegistryService.apiHost,
        '/od/data/api/$datasetId',
        <String, String>{
          r'$format': 'json',
          r'$filter': '$filterField eq $taxId',
          r'$skip': '0',
          r'$top': '5',
        },
      );
}

String _normalizeMerchantName(String value) => value
    .toUpperCase()
    .replaceAll('　', ' ')
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

String _merchantNameCore(String value) {
  var normalized = _normalizeMerchantName(value);
  for (final suffix in const <String>[
    '股份有限公司',
    '有限公司',
    '有限合夥',
    '分公司',
    '企業社',
    '商行',
    '商號',
  ]) {
    if (normalized.endsWith(suffix)) {
      normalized = normalized.substring(0, normalized.length - suffix.length);
      break;
    }
  }
  return normalized;
}
