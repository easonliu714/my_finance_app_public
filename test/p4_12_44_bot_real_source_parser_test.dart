import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';

void main() {
  const fixturePath =
      'test/fixtures/taiwan_bank_2026_06_29_usd_view_source_excerpt.html';

  test('parses the user-provided BOT browser view-source structure', () {
    final html = File(fixturePath).readAsStringSync();
    final points = TaiwanBankHistoricalFxRateService.parseSpotRatePoints(
      html: html,
      currency: CurrencyCode.usd,
      expectedDate: DateTime.utc(2026, 6, 29),
    );

    expect(points, hasLength(2));
    expect(points.first.quotedAt, DateTime.utc(2026, 6, 29, 9, 2, 37));
    expect(points.first.spotBuyToTwd, 31.82);
    expect(points.first.spotSellToTwd, 31.92);
    expect(points.last.quotedAt, DateTime.utc(2026, 6, 29, 16, 2, 1));
    expect(points.last.spotBuyToTwd, 31.815);
    expect(points.last.spotSellToTwd, 31.915);
    expect(points.last.midpointToTwd, closeTo(31.865, 0.0000001));
  });

  test('19:29 invoice selects the last official quote at 16:02:01', () async {
    final html = File(fixturePath).readAsStringSync();
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async => HistoricalFxHttpPayload(
        statusCode: 200,
        body: html,
      ),
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29, 19, 29, 2),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(
      quote.effectiveQuoteDateTime,
      DateTime.utc(2026, 6, 29, 16, 2, 1),
    );
    expect(quote.sourceSpotBuyToTwd, 31.815);
    expect(quote.sourceSpotSellToTwd, 31.915);
    expect(quote.sourceToAccountRate, closeTo(31.865, 0.0000001));
    expect(
      quote.selectionPolicy,
      'requested_date_last_quote_after_market',
    );
  });

  test('chart-only official sight payload remains a supported fallback', () {
    const html = '''
<div
  data-local='{"series":[{"data":[[1782748921000,31.915]],"name":"本行賣出"},{"data":[[1782748921000,31.815]],"name":"本行買入"}]}'
  data-chart-title="即期匯率"
  class="canvas chart"></div>
''';
    final points = TaiwanBankHistoricalFxRateService.parseSpotRatePoints(
      html: html,
      currency: CurrencyCode.usd,
      expectedDate: DateTime.utc(2026, 6, 29),
    );

    expect(points, hasLength(1));
    expect(points.single.quotedAt, DateTime.utc(2026, 6, 29, 16, 2, 1));
    expect(points.single.spotBuyToTwd, 31.815);
    expect(points.single.spotSellToTwd, 31.915);
  });
}
