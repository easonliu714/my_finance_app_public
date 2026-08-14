import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/account_record.dart';

class HistoricalFxRateException implements Exception {
  const HistoricalFxRateException(this.code, this.message);

  final String code;
  final String message;

  String get statusLabel {
    if (code == 'FX_QUOTE_NOT_FOUND') return '查無可用歷史匯率';
    if (code == 'FX_SPOT_COLUMNS_NOT_FOUND') return '找不到臺銀即期匯率欄位';
    if (code == 'FX_SOURCE_UNEXPECTED_PAGE') {
      return '臺銀回應未包含歷史匯率資料';
    }
    if (code == 'FX_SOURCE_UNAVAILABLE') return '連線失敗';
    if (code == 'FX_SOURCE_MAINTENANCE') return '臺銀網站維護中';
    if (code == 'FX_SOURCE_PARSE_FAILED') return '回應格式無法解析';
    if (code.startsWith('FX_SOURCE_HTTP_')) return '臺銀網站回應異常';
    return '匯率查詢失敗';
  }

  String get userFacingMessage =>
      message.startsWith('$statusLabel：') ? message : '$statusLabel：$message';

  @override
  String toString() => '$code: $message';
}

class HistoricalFxHttpPayload {
  const HistoricalFxHttpPayload({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef HistoricalFxTextFetcher = Future<HistoricalFxHttpPayload> Function(
  Uri uri,
);

class HistoricalFxSpotRatePoint {
  const HistoricalFxSpotRatePoint({
    required this.quotedAt,
    required this.currency,
    required this.spotBuyToTwd,
    required this.spotSellToTwd,
  });

  final DateTime quotedAt;
  final CurrencyCode currency;
  final double spotBuyToTwd;
  final double spotSellToTwd;

  double get midpointToTwd => (spotBuyToTwd + spotSellToTwd) / 2;
}

class HistoricalFxRateQuote {
  const HistoricalFxRateQuote({
    required this.requestedDate,
    required this.effectiveDate,
    required this.sourceCurrency,
    required this.accountCurrency,
    required this.sourceMidpointToTwd,
    required this.accountMidpointToTwd,
    required this.sourceToAccountRate,
    required this.sourceName,
    required this.sourceUrl,
    this.requestedDateTime,
    this.effectiveQuoteDateTime,
    this.sourceSpotBuyToTwd,
    this.sourceSpotSellToTwd,
    this.accountSpotBuyToTwd,
    this.accountSpotSellToTwd,
    this.selectionPolicy,
  });

  final DateTime requestedDate;
  final DateTime effectiveDate;
  final CurrencyCode sourceCurrency;
  final CurrencyCode accountCurrency;
  final double sourceMidpointToTwd;
  final double accountMidpointToTwd;
  final double sourceToAccountRate;
  final String sourceName;
  final String sourceUrl;

  /// Wall-clock invoice timestamp represented in UTC fields so comparison does
  /// not depend on the Android device time zone.
  final DateTime? requestedDateTime;

  /// Exact Bank of Taiwan intraday quote selected for the source currency.
  final DateTime? effectiveQuoteDateTime;
  final double? sourceSpotBuyToTwd;
  final double? sourceSpotSellToTwd;
  final double? accountSpotBuyToTwd;
  final double? accountSpotSellToTwd;
  final String? selectionPolicy;

  bool get usedPreviousBusinessDate =>
      _dateKey(requestedDate) != _dateKey(effectiveDate);
}

class TaiwanBankHistoricalFxRateService {
  TaiwanBankHistoricalFxRateService({
    http.Client? client,
    HistoricalFxTextFetcher? fetcher,
    this.maxLookbackDays = 7,
  })  : _client = client ?? http.Client(),
        _fetcher = fetcher;

  static const sourceName = '臺灣銀行歷史匯率（即期買入／賣出中價）';
  static const transportId = 'baseline_native_http';

  final http.Client _client;
  final HistoricalFxTextFetcher? _fetcher;
  final int maxLookbackDays;
  final Map<String, Future<List<HistoricalFxSpotRatePoint>>> _spotQuoteCache =
      <String, Future<List<HistoricalFxSpotRatePoint>>>{};
  String? _lastResponseDiagnostic;

  String? get lastTransportDiagnostic => _lastResponseDiagnostic;

  void clearCache() {
    _spotQuoteCache.clear();
    _lastResponseDiagnostic = null;
  }

  Future<HistoricalFxRateQuote> quote({
    required DateTime transactionDate,
    required CurrencyCode sourceCurrency,
    required CurrencyCode accountCurrency,
  }) async {
    _lastResponseDiagnostic = null;
    final requestedDateTime = _wallClockUtc(transactionDate);
    final requestedDate = _dateOnly(requestedDateTime);

    if (sourceCurrency == CurrencyCode.twd &&
        accountCurrency == CurrencyCode.twd) {
      return HistoricalFxRateQuote(
        requestedDate: requestedDate,
        effectiveDate: requestedDate,
        requestedDateTime: requestedDateTime,
        effectiveQuoteDateTime: requestedDateTime,
        sourceCurrency: sourceCurrency,
        accountCurrency: accountCurrency,
        sourceMidpointToTwd: 1,
        accountMidpointToTwd: 1,
        sourceSpotBuyToTwd: 1,
        sourceSpotSellToTwd: 1,
        accountSpotBuyToTwd: 1,
        accountSpotSellToTwd: 1,
        sourceToAccountRate: 1,
        selectionPolicy: 'same_currency_identity',
        sourceName: sourceName,
        sourceUrl: _quoteUri(requestedDate, sourceCurrency).toString(),
      );
    }

    for (var offset = 0; offset <= maxLookbackDays; offset += 1) {
      final candidateDate = requestedDate.subtract(Duration(days: offset));
      final sourceSelection = await _selectRateToTwd(
        sourceCurrency,
        candidateDate: candidateDate,
        requestedDateTime: requestedDateTime,
        requestedDate: offset == 0,
      );
      if (sourceSelection == null) continue;

      final accountSelection = await _selectRateToTwd(
        accountCurrency,
        candidateDate: candidateDate,
        requestedDateTime: requestedDateTime,
        requestedDate: offset == 0,
      );
      if (accountSelection == null) continue;
      if (sourceSelection.midpointToTwd <= 0 ||
          accountSelection.midpointToTwd <= 0) {
        continue;
      }

      final primarySelection = sourceCurrency == CurrencyCode.twd
          ? accountSelection
          : sourceSelection;
      final referenceCurrency = sourceCurrency == CurrencyCode.twd
          ? accountCurrency
          : sourceCurrency;
      return HistoricalFxRateQuote(
        requestedDate: requestedDate,
        effectiveDate: candidateDate,
        requestedDateTime: requestedDateTime,
        effectiveQuoteDateTime: primarySelection.quotedAt,
        sourceCurrency: sourceCurrency,
        accountCurrency: accountCurrency,
        sourceMidpointToTwd: sourceSelection.midpointToTwd,
        accountMidpointToTwd: accountSelection.midpointToTwd,
        sourceSpotBuyToTwd: sourceSelection.spotBuyToTwd,
        sourceSpotSellToTwd: sourceSelection.spotSellToTwd,
        accountSpotBuyToTwd: accountSelection.spotBuyToTwd,
        accountSpotSellToTwd: accountSelection.spotSellToTwd,
        sourceToAccountRate:
            sourceSelection.midpointToTwd / accountSelection.midpointToTwd,
        selectionPolicy: primarySelection.selectionPolicy,
        sourceName: sourceName,
        sourceUrl: _quoteUri(candidateDate, referenceCurrency).toString(),
      );
    }

    final diagnosticSuffix = _lastResponseDiagnostic == null
        ? ''
        : ' 最後回應診斷：${_lastResponseDiagnostic!}';
    throw HistoricalFxRateException(
      'FX_QUOTE_NOT_FOUND',
      '查無可用歷史匯率：查詢時間 ${_dateTimeKey(requestedDateTime)}；'
          '向前 $maxLookbackDays 日仍找不到 '
          '${sourceCurrency.code} 對 ${accountCurrency.code} 可用的臺銀即期中價。'
          '請手動輸入匯率，或以實際扣帳金額反推。'
          '$diagnosticSuffix',
    );
  }

  Future<_HistoricalFxRateSelection?> _selectRateToTwd(
    CurrencyCode currency, {
    required DateTime candidateDate,
    required DateTime requestedDateTime,
    required bool requestedDate,
  }) async {
    if (currency == CurrencyCode.twd) {
      return _HistoricalFxRateSelection(
        quotedAt: requestedDateTime,
        spotBuyToTwd: 1,
        spotSellToTwd: 1,
        selectionPolicy: 'same_currency_identity',
      );
    }

    final points = await _spotRates(currency, candidateDate);
    if (points.isEmpty) return null;

    if (!requestedDate) {
      return _HistoricalFxRateSelection.fromPoint(
        points.last,
        selectionPolicy: 'previous_business_day_last_quote',
      );
    }

    if (!_hasExplicitTime(requestedDateTime)) {
      return _HistoricalFxRateSelection.fromPoint(
        points.last,
        selectionPolicy: 'requested_date_last_quote_no_time',
      );
    }

    HistoricalFxSpotRatePoint? selected;
    for (final point in points) {
      if (point.quotedAt.isAfter(requestedDateTime)) break;
      selected = point;
    }
    if (selected == null) {
      // Never use a quote published after the transaction timestamp.
      return null;
    }

    final policy = requestedDateTime.isAfter(points.last.quotedAt)
        ? 'requested_date_last_quote_after_market'
        : 'latest_at_or_before_transaction_time';
    return _HistoricalFxRateSelection.fromPoint(
      selected,
      selectionPolicy: policy,
    );
  }

  Future<List<HistoricalFxSpotRatePoint>> _spotRates(
    CurrencyCode currency,
    DateTime date,
  ) async {
    final key = '${_dateKey(date)}|${currency.code}';
    final future = _spotQuoteCache.putIfAbsent(
      key,
      () => _loadSpotRates(currency, date),
    );
    try {
      final result = await future;
      if (result.isEmpty && identical(_spotQuoteCache[key], future)) {
        _spotQuoteCache.remove(key);
      }
      return result;
    } catch (_) {
      if (identical(_spotQuoteCache[key], future)) {
        _spotQuoteCache.remove(key);
      }
      rethrow;
    }
  }

  /// Deliberately minimal request headers.
  ///
  /// P4.FX.0 device evidence showed that browser impersonation (desktop
  /// User-Agent, Sec-Fetch headers, Referer, session warm-up, or WebView cookie
  /// relay) causes Bank of Taiwan to return HTTP 200 `Challenge Validation`.
  /// The baseline Native HTTP request succeeds, so these headers must remain
  /// transport-neutral. The legacy Windows NT 10.0; Win64; x64 contract is
  /// intentionally retired.
  Map<String, String> _baselineHeaders() => const <String, String>{
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.6',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      };

  Future<HistoricalFxHttpPayload> _fetchPayload(Uri uri) async {
    final fetcher = _fetcher;
    if (fetcher != null) return fetcher(uri);

    final response = await _client
        .get(uri, headers: _baselineHeaders())
        .timeout(const Duration(seconds: 12));
    return HistoricalFxHttpPayload(
      statusCode: response.statusCode,
      body: utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  }

  Future<List<HistoricalFxSpotRatePoint>> _loadSpotRates(
    CurrencyCode currency,
    DateTime date,
  ) async {
    final uri = _quoteUri(date, currency);
    HistoricalFxHttpPayload payload;
    try {
      payload = await _fetchPayload(uri);
    } catch (error) {
      throw HistoricalFxRateException(
        'FX_SOURCE_UNAVAILABLE',
        '連線失敗：無法以基礎 Native HTTP 連線至臺灣銀行歷史匯率服務'
            '（日期 ${_dateKey(date)}、幣別 ${currency.code}）：$error。'
            '請確認網路後重試；也可改用實際扣帳金額反推。',
      );
    }

    _lastResponseDiagnostic = _responseDiagnostic(
      html: payload.body,
      statusCode: payload.statusCode,
      date: date,
      currency: currency,
    );

    if (payload.statusCode == 404) {
      return const <HistoricalFxSpotRatePoint>[];
    }
    if (payload.statusCode < 200 || payload.statusCode >= 300) {
      throw HistoricalFxRateException(
        'FX_SOURCE_HTTP_${payload.statusCode}',
        '臺銀網站回應異常：臺灣銀行歷史匯率回應 HTTP '
            '${payload.statusCode}（日期 ${_dateKey(date)}、'
            '幣別 ${currency.code}）。請稍後重試或改用人工覆核。'
            ' 回應診斷：${_lastResponseDiagnostic!}',
      );
    }

    if (_isMaintenancePage(payload.body)) {
      throw const HistoricalFxRateException(
        'FX_SOURCE_MAINTENANCE',
        '臺銀網站維護中：臺灣銀行匯率網站目前顯示系統維護。'
            '請稍後重試，或改用實際扣帳金額／手動匯率。',
      );
    }

    if (_isChallengePage(payload.body)) {
      throw HistoricalFxRateException(
        'FX_SOURCE_UNEXPECTED_PAGE',
        '臺銀回應未包含歷史匯率資料：基礎 Native HTTP 收到 '
            'Challenge Validation，而不是正式歷史匯率頁。'
            '系統已停止解析，且不會把 HTTP 200 誤判為成功。'
            '請稍後重試或改用人工覆核。'
            ' 回應診斷：${_lastResponseDiagnostic!}',
      );
    }

    final parsed = parseSpotRatePoints(
      html: payload.body,
      currency: currency,
      expectedDate: date,
    );
    if (parsed.isNotEmpty) {
      _lastResponseDiagnostic = null;
      return parsed;
    }

    final normalizedHtml = _unwrapBrowserViewSourceIfNeeded(payload.body);
    final bodyText = _plainText(normalizedHtml);
    final lowerBodyText = bodyText.toLowerCase();
    final containsExpectedDate = _dateTokens(date).any(bodyText.contains);
    final containsSpotHeader =
        bodyText.contains('即期匯率') || lowerBodyText.contains('spot');
    final containsCashHeader =
        bodyText.contains('現金匯率') || lowerBodyText.contains('cash');

    if (containsExpectedDate && containsCashHeader && !containsSpotHeader) {
      throw HistoricalFxRateException(
        'FX_SPOT_COLUMNS_NOT_FOUND',
        '找不到臺銀即期匯率欄位：臺灣銀行回應只有現金匯率表'
            '（日期 ${_dateKey(date)}、幣別 ${currency.code}）。'
            '系統不會以現金匯率替代即期匯率；請重試或改用實際扣帳金額。',
      );
    }

    if (containsExpectedDate && containsSpotHeader) {
      throw HistoricalFxRateException(
        'FX_SOURCE_PARSE_FAILED',
        '回應格式無法解析：已連線臺灣銀行並找到即期匯率欄位，'
            '但無法解析 ${_dateKey(date)} ${currency.code} 的盤中買入／賣出資料。'
            '可能是官方頁面格式變更，請改用實際扣帳金額或手動匯率。'
            ' 回應診斷：${_lastResponseDiagnostic!}',
      );
    }

    if (!_isOfficialHistoricalPage(normalizedHtml, bodyText)) {
      throw HistoricalFxRateException(
        'FX_SOURCE_UNEXPECTED_PAGE',
        '臺銀回應未包含歷史匯率資料：收到的頁面不是可辨識的'
            '臺灣銀行歷史匯率頁，已停止解析。'
            ' 回應診斷：${_lastResponseDiagnostic!}',
      );
    }

    // A valid official page can legitimately have no rows on a non-business
    // date. Return an empty list so quote() can continue its bounded lookback.
    return const <HistoricalFxSpotRatePoint>[];
  }

  String _responseDiagnostic({
    required String html,
    required int statusCode,
    required DateTime date,
    required CurrencyCode currency,
  }) {
    final normalizedHtml = _unwrapBrowserViewSourceIfNeeded(html);
    final text = _plainText(normalizedHtml);
    final titleMatch = RegExp(
      r'<title\b[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(normalizedHtml);
    final title = _plainText(titleMatch?.group(1) ?? '');
    final safeTitle = title.length > 80 ? title.substring(0, 80) : title;
    final tableCount = RegExp(
      r'<table\b',
      caseSensitive: false,
    ).allMatches(normalizedHtml).length;
    final rowCount = RegExp(
      r'<tr\b',
      caseSensitive: false,
    ).allMatches(normalizedHtml).length;
    final hasDate = _dateTokens(date).any(text.contains);
    final hasCurrency =
        text.toUpperCase().contains(currency.code.toUpperCase());
    final hasSpot =
        text.contains('即期匯率') || text.toLowerCase().contains('spot');
    final sourceWrapped = normalizedHtml != html;
    final challenge = _isChallengePage(normalizedHtml);
    return 'transport=$transportId, ${_dateKey(date)} ${currency.code}: '
        'HTTP $statusCode, chars=${normalizedHtml.length}, '
        'title=${safeTitle.isEmpty ? '(none)' : safeTitle}, '
        'tables=$tableCount, rows=$rowCount, date=$hasDate, '
        'currency=$hasCurrency, spot=$hasSpot, challenge=$challenge, '
        'browserSourceWrapper=$sourceWrapped';
  }

  Uri _quoteUri(DateTime date, CurrencyCode currency) => Uri.https(
        'rate.bot.com.tw',
        '/xrt/quote/${_dateKey(date)}/${currency.code}',
        const <String, String>{'Lang': 'zh-TW'},
      );

  static List<HistoricalFxSpotRatePoint> parseSpotRatePoints({
    required String html,
    required CurrencyCode currency,
    required DateTime expectedDate,
  }) {
    final normalizedHtml = _unwrapBrowserViewSourceIfNeeded(html);
    final pointsByTimestamp = <String, HistoricalFxSpotRatePoint>{};

    for (final point in _parseOfficialSightChartPoints(
      html: normalizedHtml,
      currency: currency,
      expectedDate: expectedDate,
    )) {
      pointsByTimestamp[point.quotedAt.toIso8601String()] = point;
    }

    for (final point in _parseOfficialSightTablePoints(
      html: normalizedHtml,
      currency: currency,
      expectedDate: expectedDate,
    )) {
      pointsByTimestamp[point.quotedAt.toIso8601String()] = point;
    }

    final points = pointsByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.quotedAt.compareTo(b.quotedAt));
    return List<HistoricalFxSpotRatePoint>.unmodifiable(points);
  }

  static double? parseSpotMidpointToTwd({
    required String html,
    required CurrencyCode currency,
    required DateTime expectedDate,
  }) {
    final points = parseSpotRatePoints(
      html: html,
      currency: currency,
      expectedDate: expectedDate,
    );
    return points.isEmpty ? null : points.last.midpointToTwd;
  }
}

class _HistoricalFxRateSelection {
  const _HistoricalFxRateSelection({
    required this.quotedAt,
    required this.spotBuyToTwd,
    required this.spotSellToTwd,
    required this.selectionPolicy,
  });

  factory _HistoricalFxRateSelection.fromPoint(
    HistoricalFxSpotRatePoint point, {
    required String selectionPolicy,
  }) =>
      _HistoricalFxRateSelection(
        quotedAt: point.quotedAt,
        spotBuyToTwd: point.spotBuyToTwd,
        spotSellToTwd: point.spotSellToTwd,
        selectionPolicy: selectionPolicy,
      );

  final DateTime quotedAt;
  final double spotBuyToTwd;
  final double spotSellToTwd;
  final String selectionPolicy;

  double get midpointToTwd => (spotBuyToTwd + spotSellToTwd) / 2;
}

class _FxHtmlCell {
  const _FxHtmlCell({
    required this.attributes,
    required this.label,
    required this.text,
  });

  final String attributes;
  final String label;
  final String text;
}

class _SightQuoteAccumulator {
  double? buy;
  double? sell;
}

List<HistoricalFxSpotRatePoint> _parseOfficialSightTablePoints({
  required String html,
  required CurrencyCode currency,
  required DateTime expectedDate,
}) {
  final tablePattern = RegExp(
    r'<table\b([^>]*)>([\s\S]*?)</table>',
    caseSensitive: false,
  );
  final rowPattern = RegExp(
    r'<tr\b[^>]*>([\s\S]*?)</tr>',
    caseSensitive: false,
  );
  final cellPattern = RegExp(
    r'<(td|th)\b([^>]*)>([\s\S]*?)</\1>',
    caseSensitive: false,
  );
  final pointsByTimestamp = <String, HistoricalFxSpotRatePoint>{};

  for (final tableMatch in tablePattern.allMatches(html)) {
    final tableAttributes = tableMatch.group(1) ?? '';
    final tableBody = tableMatch.group(2) ?? '';
    final descriptor =
        '${_plainText(tableAttributes)} ${_plainText(tableBody)}'.toLowerCase();
    final lowerTableBody = tableBody.toLowerCase();
    final hasSpotDescriptor = descriptor.contains('即期匯率') ||
        descriptor.contains('spot') ||
        lowerTableBody.contains('即期匯率') ||
        lowerTableBody.contains('spot');
    final hasTimeDescriptor = descriptor.contains('時間') ||
        descriptor.contains('掛牌日期') ||
        descriptor.contains('time') ||
        lowerTableBody.contains('時間') ||
        lowerTableBody.contains('掛牌日期') ||
        lowerTableBody.contains('time');
    final officialHistoricalTable =
        descriptor.contains('歷史本行營業時間牌告匯率') ||
            lowerTableBody.contains('rate-content-sight') ||
            (hasSpotDescriptor && hasTimeDescriptor);
    if (!officialHistoricalTable) continue;

    for (final rowMatch in rowPattern.allMatches(tableBody)) {
      final row = rowMatch.group(1) ?? '';
      final cells = <_FxHtmlCell>[];
      for (final cellMatch in cellPattern.allMatches(row)) {
        final attributes = cellMatch.group(2) ?? '';
        final label = _attributeValue(attributes, 'data-table') ?? '';
        cells.add(
          _FxHtmlCell(
            attributes: attributes,
            label: _plainText(label),
            text: _plainText(cellMatch.group(3) ?? ''),
          ),
        );
      }
      if (cells.isEmpty) continue;

      final quotedAt = _dateTimeFromCells(cells);
      if (quotedAt == null ||
          _dateKey(quotedAt) != _dateKey(expectedDate)) {
        continue;
      }
      final rowText = cells.map((cell) => cell.text).join(' ').toUpperCase();
      if (!rowText.contains(currency.code.toUpperCase())) continue;

      double? spotBuy;
      double? spotSell;
      final sightCells = cells
          .where(
            (cell) => _hasClassToken(
              cell.attributes,
              'rate-content-sight',
            ),
          )
          .map((cell) => _strictNumber(cell.text))
          .whereType<double>()
          .toList(growable: false);
      if (sightCells.length >= 2) {
        spotBuy = sightCells[0];
        spotSell = sightCells[1];
      }

      if (spotBuy == null || spotSell == null) {
        for (final cell in cells) {
          final normalized = _normalizedHeader(cell.label);
          final isSpot =
              normalized.contains('即期') || normalized.contains('spot');
          final isBuy = normalized.contains('買入') ||
              normalized.contains('buying') ||
              normalized.endsWith('buy');
          final isSell = normalized.contains('賣出') ||
              normalized.contains('selling') ||
              normalized.endsWith('sell');
          if (isSpot && isBuy) spotBuy = _strictNumber(cell.text);
          if (isSpot && isSell) spotSell = _strictNumber(cell.text);
        }
      }

      if (spotBuy == null || spotSell == null) {
        final numeric = cells
            .map((cell) => _strictNumber(cell.text))
            .whereType<double>()
            .toList(growable: false);
        if (numeric.length >= 4) {
          spotBuy = numeric[numeric.length - 2];
          spotSell = numeric[numeric.length - 1];
        }
      }

      if (spotBuy == null ||
          spotSell == null ||
          spotBuy <= 0 ||
          spotSell <= 0) {
        continue;
      }

      final point = HistoricalFxSpotRatePoint(
        quotedAt: quotedAt,
        currency: currency,
        spotBuyToTwd: spotBuy,
        spotSellToTwd: spotSell,
      );
      pointsByTimestamp[quotedAt.toIso8601String()] = point;
    }
  }

  final points = pointsByTimestamp.values.toList(growable: false)
    ..sort((a, b) => a.quotedAt.compareTo(b.quotedAt));
  return List<HistoricalFxSpotRatePoint>.unmodifiable(points);
}

List<HistoricalFxSpotRatePoint> _parseOfficialSightChartPoints({
  required String html,
  required CurrencyCode currency,
  required DateTime expectedDate,
}) {
  final divPattern = RegExp(r'<div\b([^>]*)>', caseSensitive: false);
  final accumulators = <int, _SightQuoteAccumulator>{};

  for (final divMatch in divPattern.allMatches(html)) {
    final attributes = divMatch.group(1) ?? '';
    final chartTitle = _plainText(
      _attributeValue(attributes, 'data-chart-title') ?? '',
    );
    if (chartTitle != '即期匯率') continue;

    final dataLocal = _attributeValue(attributes, 'data-local');
    if (dataLocal == null || dataLocal.trim().isEmpty) continue;

    dynamic decoded;
    try {
      decoded = jsonDecode(_decodeHtmlEntities(dataLocal));
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    final series = decoded['series'];
    if (series is! List) continue;

    for (final item in series) {
      if (item is! Map) continue;
      final name = _plainText('${item['name'] ?? ''}').toLowerCase();
      final isBuy = name.contains('買入') || name.contains('buy');
      final isSell = name.contains('賣出') || name.contains('sell');
      if (!isBuy && !isSell) continue;
      final data = item['data'];
      if (data is! List) continue;

      for (final pair in data) {
        if (pair is! List || pair.length < 2) continue;
        final timestampValue = pair[0];
        final rateValue = pair[1];
        if (timestampValue is! num || rateValue is! num) continue;
        final timestamp = timestampValue.round();
        final quotedAt = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        );
        if (_dateKey(quotedAt) != _dateKey(expectedDate)) continue;
        final rate = rateValue.toDouble();
        if (!rate.isFinite || rate <= 0) continue;
        final accumulator =
            accumulators.putIfAbsent(timestamp, _SightQuoteAccumulator.new);
        if (isBuy) accumulator.buy = rate;
        if (isSell) accumulator.sell = rate;
      }
    }
  }

  final points = <HistoricalFxSpotRatePoint>[];
  for (final entry in accumulators.entries) {
    final buy = entry.value.buy;
    final sell = entry.value.sell;
    if (buy == null || sell == null) continue;
    points.add(
      HistoricalFxSpotRatePoint(
        quotedAt: DateTime.fromMillisecondsSinceEpoch(
          entry.key,
          isUtc: true,
        ),
        currency: currency,
        spotBuyToTwd: buy,
        spotSellToTwd: sell,
      ),
    );
  }
  points.sort((a, b) => a.quotedAt.compareTo(b.quotedAt));
  return List<HistoricalFxSpotRatePoint>.unmodifiable(points);
}

bool _isChallengePage(String html) {
  final lower = html.toLowerCase();
  return lower.contains('challenge validation') ||
      lower.contains('<title>challenge</title>');
}

bool _isMaintenancePage(String html) {
  final text = _plainText(html);
  return text.contains('系統維護') || text.contains('網站維護');
}

bool _isOfficialHistoricalPage(String html, String text) {
  final lower = html.toLowerCase();
  return text.contains('歷史本行營業時間牌告匯率') ||
      lower.contains('rate-content-sight') ||
      lower.contains('data-chart-title="即期匯率"') ||
      lower.contains("data-chart-title='即期匯率'");
}

String _unwrapBrowserViewSourceIfNeeded(String html) {
  final lineCellPattern = RegExp(
    r'''<td\b[^>]*class\s*=\s*(["'])[^"']*\bline-content\b[^"']*\1[^>]*>([\s\S]*?)</td>''',
    caseSensitive: false,
  );
  final matches = lineCellPattern.allMatches(html).toList(growable: false);
  if (matches.isEmpty) return html;

  final sourceLines = matches
      .map((match) => _plainText(match.group(2) ?? ''))
      .toList(growable: false);
  final reconstructed = sourceLines.join('\n').trim();
  return reconstructed.isEmpty ? html : reconstructed;
}

String? _attributeValue(String attributes, String name) {
  final pattern = RegExp(
    '''$name\\s*=\\s*(["'])([\\s\\S]*?)\\1''',
    caseSensitive: false,
  );
  return pattern.firstMatch(attributes)?.group(2);
}

bool _hasClassToken(String attributes, String token) {
  final classValue = _attributeValue(attributes, 'class');
  if (classValue == null) return false;
  return classValue
      .split(RegExp(r'\s+'))
      .any((candidate) => candidate == token);
}

DateTime? _dateTimeFromCells(List<_FxHtmlCell> cells) {
  final combined = cells.map((cell) => cell.text).join(' ');
  final yearFirst = RegExp(
    r'(20\d{2})[\/-](\d{1,2})[\/-](\d{1,2})',
  ).firstMatch(combined);
  final monthFirst = yearFirst == null
      ? RegExp(
          r'(\d{1,2})[\/-](\d{1,2})[\/-](20\d{2})',
        ).firstMatch(combined)
      : null;
  final dateMatch = yearFirst ?? monthFirst;
  if (dateMatch == null) return null;
  final timeMatch = RegExp(
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(combined.substring(dateMatch.end));
  if (timeMatch == null) return null;

  final year = yearFirst != null
      ? int.parse(yearFirst.group(1)!)
      : int.parse(monthFirst!.group(3)!);
  final month = yearFirst != null
      ? int.parse(yearFirst.group(2)!)
      : int.parse(monthFirst!.group(1)!);
  final day = yearFirst != null
      ? int.parse(yearFirst.group(3)!)
      : int.parse(monthFirst!.group(2)!);
  return DateTime.utc(
    year,
    month,
    day,
    int.parse(timeMatch.group(1)!),
    int.parse(timeMatch.group(2)!),
    int.parse(timeMatch.group(3) ?? '0'),
  );
}

double? _strictNumber(String value) {
  final normalized = value.replaceAll(',', '').trim();
  if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(normalized)) return null;
  return double.tryParse(normalized);
}

String _normalizedHeader(String value) => value
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[-—–／/]'), '')
    .toLowerCase();

String _decodeHtmlEntities(String value) {
  var text = value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&sol;', '/');
  text = text.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]+);'),
    (match) => String.fromCharCode(
      int.parse(match.group(1)!, radix: 16),
    ),
  );
  text = text.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) => String.fromCharCode(int.parse(match.group(1)!)),
  );
  return text;
}

String _plainText(String value) {
  final withoutTags = value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeHtmlEntities(withoutTags)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

DateTime _wallClockUtc(DateTime value) => DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

bool _hasExplicitTime(DateTime value) =>
    value.hour != 0 || value.minute != 0 || value.second != 0;

Set<String> _dateTokens(DateTime value) => <String>{
      _dateKey(value),
      _dateKey(value).replaceAll('-', '/'),
      '${value.month}/${value.day}/${value.year}',
      '${value.month.toString().padLeft(2, '0')}/'
          '${value.day.toString().padLeft(2, '0')}/${value.year}',
    };

String _dateTimeKey(DateTime value) =>
    '${_dateKey(value)} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';

String _dateKey(DateTime value) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}';
}
