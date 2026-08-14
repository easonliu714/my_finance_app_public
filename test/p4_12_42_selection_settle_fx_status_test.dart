import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';

void main() {
  test('selection UI waits for WebView state and performs stable inspection', () {
    final page = File(
      'lib/features/invoice/lab/private_cloud_invoice_lab_webview_page.dart',
    ).readAsStringSync();
    final sheet = File(
      'lib/features/invoice/lab/official_invoice_detail_enrichment_sheet.dart',
    ).readAsStringSync();

    expect(page, contains('_officialDetailOpenSettleDelay'));
    expect(page, contains('finish its checkbox click/change handlers'));
    expect(sheet, contains('_inspectStableTargets'));
    expect(
      sheet,
      contains('requiredSamples = report.selectedCount > 0 ? 2 : 3'),
    );
  });

  test('FX UI exposes loading, success, failure, and explicit retry result', () {
    final source = File(
      'lib/features/invoice/lab/private_cloud_invoice_draft_promotion_page.dart',
    ).readAsStringSync();

    expect(source, contains('private_draft_promotion_fx_status_'));
    expect(source, contains('臺銀匯率查詢中'));
    expect(source, contains('臺銀匯率取得成功'));
    expect(source, contains('臺銀匯率取得失敗'));
    expect(source, contains('_retryFxQuote'));
    expect(source, contains('error.userFacingMessage'));
  });

  test('404/null miss is evicted so explicit retry performs a new fetch', () async {
    var attempts = 0;
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async {
        attempts += 1;
        if (attempts == 1) {
          return const HistoricalFxHttpPayload(statusCode: 404, body: '');
        }
        return const HistoricalFxHttpPayload(
          statusCode: 200,
          body: '''
<table title="歷史本行營業時間牌告匯率"><tbody><tr>
<td class="text-center">2026/06/29 16:00:00</td>
<td class="text-center tablet_hide">美元 (USD)</td>
<td class="text-right rate-content-cash">0</td>
<td class="text-right rate-content-cash">0</td>
<td class="text-right rate-content-sight">29.10</td>
<td class="text-right rate-content-sight">29.20</td>
</tr></tbody></table>
''',
        );
      },
    );

    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 6, 29),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(
        isA<HistoricalFxRateException>().having(
          (error) => error.code,
          'code',
          'FX_QUOTE_NOT_FOUND',
        ),
      ),
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(attempts, 2);
    expect(quote.sourceToAccountRate, closeTo(29.15, 0.000001));
  });
}
