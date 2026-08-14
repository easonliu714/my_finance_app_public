import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';

const _desktopJune24Html = '''
<html><body>
<table>
  <thead>
    <tr>
      <th rowspan="2">時間</th>
      <th rowspan="2">幣別</th>
      <th colspan="2">現金匯率</th>
      <th colspan="2">即期匯率</th>
    </tr>
    <tr>
      <th>本行買入</th><th>本行賣出</th>
      <th>本行買入</th><th>本行賣出</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td data-table="時間">2026/06/24 09:01:46</td>
      <td data-table="幣別">美元 (USD)</td>
      <td data-table="現金匯率-本行買入">31.245</td>
      <td data-table="現金匯率-本行賣出">31.915</td>
      <td data-table="即期匯率-本行買入">31.595</td>
      <td data-table="即期匯率-本行賣出">31.695</td>
    </tr>
    <tr>
      <td data-table="時間">2026/06/24 14:19:50</td>
      <td data-table="幣別">美元 (USD)</td>
      <td data-table="現金匯率-本行買入">31.350</td>
      <td data-table="現金匯率-本行賣出">32.020</td>
      <td data-table="即期匯率-本行買入">31.700</td>
      <td data-table="即期匯率-本行賣出">31.800</td>
    </tr>
    <tr>
      <td data-table="時間">2026/06/24 16:03:46</td>
      <td data-table="幣別">美元 (USD)</td>
      <td data-table="現金匯率-本行買入">31.380</td>
      <td data-table="現金匯率-本行賣出">32.050</td>
      <td data-table="即期匯率-本行買入">31.730</td>
      <td data-table="即期匯率-本行賣出">31.830</td>
    </tr>
  </tbody>
</table>
</body></html>
''';

const _desktopJune23Html = '''
<table>
  <thead>
    <tr><th>時間</th><th>幣別</th><th>現金匯率</th><th>現金匯率</th><th>即期匯率</th><th>即期匯率</th></tr>
  </thead>
  <tbody>
    <tr>
      <td>2026/06/23 16:00:00</td><td>美元 (USD)</td>
      <td>31.100</td><td>31.700</td><td>31.450</td><td>31.550</td>
    </tr>
  </tbody>
</table>
''';

const _cashOnlyHtml = '''
<table>
  <thead><tr><th>時間</th><th>現金匯率 本行買入</th><th>現金匯率 本行賣出</th></tr></thead>
  <tbody>
    <tr><td>2026/06/24 09:01:46</td><td>31.245</td><td>31.915</td></tr>
  </tbody>
</table>
<div>幣別：美元 (USD)</div>
''';

void main() {
  test('desktop parser returns all intraday spot rows in time order', () {
    final points = TaiwanBankHistoricalFxRateService.parseSpotRatePoints(
      html: _desktopJune24Html,
      currency: CurrencyCode.usd,
      expectedDate: DateTime(2026, 6, 24),
    );

    expect(points, hasLength(3));
    expect(points.first.quotedAt, DateTime.utc(2026, 6, 24, 9, 1, 46));
    expect(points.first.spotBuyToTwd, 31.595);
    expect(points.first.spotSellToTwd, 31.695);
    expect(points.last.quotedAt, DateTime.utc(2026, 6, 24, 16, 3, 46));
    expect(points.last.midpointToTwd, closeTo(31.78, 0.000001));
  });

  test('transaction during market uses latest quote at or before timestamp',
      () async {
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async => const HistoricalFxHttpPayload(
        statusCode: 200,
        body: _desktopJune24Html,
      ),
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 24, 14, 20),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(quote.effectiveQuoteDateTime, DateTime.utc(2026, 6, 24, 14, 19, 50));
    expect(quote.sourceSpotBuyToTwd, 31.7);
    expect(quote.sourceSpotSellToTwd, 31.8);
    expect(quote.sourceToAccountRate, closeTo(31.75, 0.000001));
    expect(quote.selectionPolicy, 'latest_at_or_before_transaction_time');
  });

  test('transaction after market uses requested date last quote', () async {
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async => const HistoricalFxHttpPayload(
        statusCode: 200,
        body: _desktopJune24Html,
      ),
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 24, 19, 29, 2),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(quote.effectiveQuoteDateTime, DateTime.utc(2026, 6, 24, 16, 3, 46));
    expect(quote.sourceToAccountRate, closeTo(31.78, 0.000001));
    expect(quote.selectionPolicy, 'requested_date_last_quote_after_market');
  });

  test('transaction before first quote falls back to previous business day',
      () async {
    final requestedUris = <Uri>[];
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 1,
      fetcher: (uri) async {
        requestedUris.add(uri);
        return HistoricalFxHttpPayload(
          statusCode: 200,
          body: uri.path.contains('2026-06-24')
              ? _desktopJune24Html
              : _desktopJune23Html,
        );
      },
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 24, 8),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(requestedUris, hasLength(2));
    expect(quote.effectiveDate, DateTime.utc(2026, 6, 23));
    expect(quote.effectiveQuoteDateTime, DateTime.utc(2026, 6, 23, 16));
    expect(quote.sourceToAccountRate, closeTo(31.5, 0.000001));
    expect(quote.selectionPolicy, 'previous_business_day_last_quote');
  });

  test('cash-only response is rejected instead of becoming a spot quote',
      () async {
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async => const HistoricalFxHttpPayload(
        statusCode: 200,
        body: _cashOnlyHtml,
      ),
    );

    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 6, 24, 19),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(
        isA<HistoricalFxRateException>().having(
          (error) => error.code,
          'code',
          'FX_SPOT_COLUMNS_NOT_FOUND',
        ),
      ),
    );
  });

  test('production request uses the baseline Native HTTP contract', () {
    final source = File(
      'lib/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart',
    ).readAsStringSync();

    expect(source, contains("transportId = 'baseline_native_http'"));
    expect(source, contains('_baselineHeaders'));
    expect(source, contains('numeric.length >= 4'));
    expect(source, isNot(contains("'User-Agent':")));
    expect(source, isNot(contains("'Sec-Fetch-Dest':")));
    expect(source, isNot(contains('_ensureBrowserSession')));
  });

  test('promotion audit carries quote time, buy, sell, and policy', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_service.dart',
    ).readAsStringSync();

    expect(page, contains('fxEffectiveDateTime:'));
    expect(page, contains('fxSpotBuyToBase:'));
    expect(page, contains('fxSpotSellToBase:'));
    expect(page, contains('fxSelectionPolicy:'));
    expect(service, contains('臺銀牌告時間：'));
    expect(service, contains('臺銀即期買入：'));
    expect(service, contains('臺銀即期賣出：'));
    expect(service, contains('匯率選取規則：'));
  });
}
