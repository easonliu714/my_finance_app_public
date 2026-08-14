import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/official_invoice_detail_enrichment_sheet.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';

void main() {
  test('selection refresh control has a stable key', () {
    expect(
      OfficialInvoiceDetailEnrichmentSheet.refreshSelectionKey,
      const Key('official_detail_refresh_selection'),
    );
  });

  test('FX exception exposes a stable user-facing status category', () {
    const parseFailure = HistoricalFxRateException(
      'FX_SOURCE_PARSE_FAILED',
      '回應格式無法解析：測試內容',
    );
    expect(parseFailure.statusLabel, '回應格式無法解析');
    expect(parseFailure.userFacingMessage, '回應格式無法解析：測試內容');

    const networkFailure = HistoricalFxRateException(
      'FX_SOURCE_UNAVAILABLE',
      '測試內容',
    );
    expect(networkFailure.statusLabel, '連線失敗');
    expect(networkFailure.userFacingMessage, '連線失敗：測試內容');
  });

  test('failed FX Future is evicted so explicit retry performs a real fetch',
      () async {
    var attempts = 0;
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (uri) async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('temporary network failure');
        }
        return const HistoricalFxHttpPayload(
          statusCode: 200,
          body: '''
<table><tbody><tr>
<td data-table="掛牌日期">2026/07/02 16:00:00</td>
<td data-table="幣別">美元 (USD)</td>
<td data-table="現金匯率-本行買入">0</td>
<td data-table="現金匯率-本行賣出">0</td>
<td data-table="即期匯率-本行買入">31.50</td>
<td data-table="即期匯率-本行賣出">31.60</td>
</tr></tbody></table>
''',
        );
      },
    );

    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 7, 2),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(
        isA<HistoricalFxRateException>()
            .having((error) => error.code, 'code', 'FX_SOURCE_UNAVAILABLE')
            .having(
              (error) => error.message,
              'message',
              contains('連線失敗'),
            ),
      ),
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 7, 2),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(attempts, 2);
    expect(quote.sourceToAccountRate, closeTo(31.55, 0.000001));
    expect(quote.effectiveDate, DateTime.utc(2026, 7, 2));
    expect(quote.effectiveQuoteDateTime, DateTime.utc(2026, 7, 2, 16));
  });

  test('missing historical quote explains date, currencies, and fallback',
      () async {
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async =>
          const HistoricalFxHttpPayload(statusCode: 404, body: ''),
    );

    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 7, 2),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(
        isA<HistoricalFxRateException>()
            .having((error) => error.code, 'code', 'FX_QUOTE_NOT_FOUND')
            .having(
              (error) => error.message,
              'message',
              allOf(
                contains('查無可用歷史匯率'),
                contains('2026-07-02'),
                contains('USD'),
                contains('TWD'),
                contains('實際扣帳金額反推'),
              ),
            ),
      ),
    );
  });
}
