import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';

void main() {
  test('selection inspection is non-mutating and current-page prep is scoped', () {
    final source = File(
      'lib/features/invoice/lab/disposable_webview_session.dart',
    ).readAsStringSync();
    final inspectStart = source.indexOf(
      'Future<OfficialInvoiceDetailTargetReport> inspectOfficialDetailTargets()',
    );
    final enrichStart = source.indexOf(
      'Future<OfficialInvoiceDetailBatchResult> enrichOfficialInvoiceDetails(',
      inspectStart,
    );
    final cancelStart = source.indexOf(
      'Future<void> cancelOfficialInvoiceDetailEnrichment()',
      enrichStart,
    );
    final inspectSection = source.substring(inspectStart, enrichStart);
    final enrichSection = source.substring(enrichStart, cancelStart);

    expect(inspectSection, isNot(contains('_prepareOfficialDetailPageIfSupported')));
    expect(
      enrichSection,
      contains('scope == OfficialInvoiceDetailSelectionScope.currentPage'),
    );
  });

  test('official desktop row uses sight classes and decodes entities', () {
    const html = '''
<table title="歷史本行營業時間牌告匯率">
  <thead><tr><th>時間</th><th>幣別</th><th>現金買入</th><th>現金賣出</th><th>即期買入</th><th>即期賣出</th></tr></thead>
  <tbody><tr>
    <td>2026&#x2F;06&#x2F;24 16:03:46</td>
    <td>美金 (USD)</td>
    <td class="rate-content-cash">31.38</td>
    <td class="rate-content-cash">32.05</td>
    <td class="rate-content-sight">31.73</td>
    <td class="rate-content-sight">31.83</td>
  </tr></tbody>
</table>
''';
    final points = TaiwanBankHistoricalFxRateService.parseSpotRatePoints(
      html: html,
      currency: CurrencyCode.usd,
      expectedDate: DateTime.utc(2026, 6, 24),
    );

    expect(points, hasLength(1));
    expect(points.single.quotedAt, DateTime.utc(2026, 6, 24, 16, 3, 46));
    expect(points.single.spotBuyToTwd, 31.73);
    expect(points.single.spotSellToTwd, 31.83);
  });

  test('unexpected page fails closed with safe baseline diagnostics', () async {
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      fetcher: (_) async => const HistoricalFxHttpPayload(
        statusCode: 200,
        body: '<html><head><title>Landing</title></head><body>No rows</body></html>',
      ),
    );

    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 6, 29, 19, 29, 2),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(
        isA<HistoricalFxRateException>()
            .having(
              (error) => error.code,
              'code',
              'FX_SOURCE_UNEXPECTED_PAGE',
            )
            .having(
              (error) => error.message,
              'message',
              allOf(
                contains('transport=baseline_native_http'),
                contains('title=Landing'),
                contains('tables=0'),
                contains('date=false'),
              ),
            ),
      ),
    );
  });
}
