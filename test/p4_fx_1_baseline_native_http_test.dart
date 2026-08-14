import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart';

void main() {
  const fixturePath =
      'test/fixtures/taiwan_bank_2026_06_29_usd_view_source_excerpt.html';

  test('baseline Native HTTP directly retrieves and parses official spot rows',
      () async {
    final html = File(fixturePath).readAsStringSync();
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        html,
        200,
        headers: const <String, String>{
          'content-type': 'text/html; charset=utf-8',
        },
      );
    });
    final service = TaiwanBankHistoricalFxRateService(
      client: client,
      maxLookbackDays: 0,
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29, 19, 29, 2),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(
      capturedRequest.url.toString(),
      'https://rate.bot.com.tw/xrt/quote/2026-06-29/USD?Lang=zh-TW',
    );
    final lowerHeaders = <String, String>{
      for (final entry in capturedRequest.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    expect(lowerHeaders['accept'], contains('text/html'));
    expect(lowerHeaders['accept-language'], 'zh-TW,zh;q=0.9,en;q=0.6');
    expect(lowerHeaders['user-agent'] ?? '', isNot(contains('Windows NT 10.0')));
    expect(lowerHeaders, isNot(contains('referer')));
    expect(lowerHeaders, isNot(contains('cookie')));
    expect(
      lowerHeaders.keys.where((key) => key.startsWith('sec-fetch-')),
      isEmpty,
    );
    expect(quote.effectiveQuoteDateTime, DateTime.utc(2026, 6, 29, 16, 2, 1));
    expect(quote.sourceSpotBuyToTwd, 31.815);
    expect(quote.sourceSpotSellToTwd, 31.915);
    expect(quote.sourceToAccountRate, closeTo(31.865, 0.0000001));
  });

  test('Challenge Validation fails closed despite HTTP 200', () async {
    var attempts = 0;
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 7,
      client: MockClient((request) async {
        attempts += 1;
        return http.Response(
          '<html><head><title>Challenge Validation</title></head>'
          '<body>Challenge Validation</body></html>',
          200,
        );
      }),
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
                contains('Challenge Validation'),
                contains('transport=baseline_native_http'),
                contains('challenge=true'),
              ),
            ),
      ),
    );
    expect(attempts, 1);
  });

  test('Challenge failure is evicted and explicit retry performs a new fetch',
      () async {
    final html = File(fixturePath).readAsStringSync();
    var attempts = 0;
    final service = TaiwanBankHistoricalFxRateService(
      maxLookbackDays: 0,
      client: MockClient((request) async {
        attempts += 1;
        if (attempts == 1) {
          return http.Response(
            '<html><title>Challenge Validation</title></html>',
            200,
          );
        }
        return http.Response(
          html,
          200,
          headers: const <String, String>{
            'content-type': 'text/html; charset=utf-8',
          },
        );
      }),
    );

    await expectLater(
      service.quote(
        transactionDate: DateTime(2026, 6, 29, 19, 29, 2),
        sourceCurrency: CurrencyCode.usd,
        accountCurrency: CurrencyCode.twd,
      ),
      throwsA(isA<HistoricalFxRateException>()),
    );

    final quote = await service.quote(
      transactionDate: DateTime(2026, 6, 29, 19, 29, 2),
      sourceCurrency: CurrencyCode.usd,
      accountCurrency: CurrencyCode.twd,
    );

    expect(attempts, 2);
    expect(quote.sourceToAccountRate, closeTo(31.865, 0.0000001));
  });

  test('source contract contains no browser impersonation or session warm-up',
      () {
    final source = File(
      'lib/features/invoice/lab/taiwan_bank_historical_fx_rate_service.dart',
    ).readAsStringSync();

    expect(source, contains("transportId = 'baseline_native_http'"));
    expect(source, contains('_baselineHeaders'));
    expect(source, isNot(contains("'User-Agent':")));
    expect(source, isNot(contains("'Referer':")));
    expect(source, isNot(contains("'Cookie':")));
    expect(source, isNot(contains("'Sec-Fetch-")));
    expect(source, isNot(contains('_ensureBrowserSession')));
    expect(source, isNot(contains('_sessionCookieFuture')));
    expect(source, isNot(contains('_landingUri')));
  });
}
