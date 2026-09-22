import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_acquisition.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_html_parser.dart';

void main() {
  const period = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 5,
    endMonth: 6,
  );

  const html = '''
  <html><body>
  <h2>115年05-06月中獎號碼單</h2>
  <div>特別獎 38548029 同期統一發票收執聯8位數號碼與特別獎號碼相同者</div>
  <div>特獎 10138845 同期統一發票收執聯8位數號碼與特獎號碼相同者</div>
  <div>頭獎 24121106 28589937 83663333 同期統一發票收執聯8位數號碼與頭獎號碼相同者</div>
  </body></html>
  ''';

  OfficialInvoiceAwardAcquisitionCoordinator coordinator(
    OfficialInvoiceAwardLastKnownGoodStore store,
  ) =>
      OfficialInvoiceAwardAcquisitionCoordinator(
        parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
        validator: const OfficialInvoiceAwardDatasetValidator(),
        store: store,
      );

  test('production service fetches only pinned MOF HTTPS bytes and promotes validated LKG', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    late http.Request observed;
    final service = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((request) async {
        observed = request;
        return http.Response.bytes(utf8.encode(html), 200);
      }),
      coordinator: coordinator(store),
      clock: () => DateTime.utc(2026, 9, 25, 6),
    );

    final result = await service.refresh(period);

    expect(result.isSuccess, isTrue);
    expect(result.replacedLastKnownGood, isTrue);
    expect(observed.method, 'GET');
    expect(observed.url,
        MinistryOfFinanceGeneralAwardHttpAcquisitionService.officialSourceUri);
    expect(observed.url.scheme, 'https');
    expect(observed.url.host, 'invoice.etax.nat.gov.tw');
    expect(observed.bodyBytes, isEmpty);
    expect(store.read(period)?.period.id, period.id);
    expect(store.read(period)?.provenance.contentSha256, hasLength(64));
  });

  test('non-200 preserves existing LKG and does not parse response body', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final seed = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => http.Response(html, 200)),
      coordinator: coordinator(store),
      clock: () => DateTime.utc(2026, 9, 25, 6),
    );
    final seeded = await seed.refresh(period);
    final fingerprint = seeded.dataset!.provenance.contentSha256;

    final failing = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => http.Response('gateway failure', 503)),
      coordinator: coordinator(store),
    );
    final result = await failing.refresh(period);

    expect(result.failure,
        OfficialInvoiceAwardRefreshFailure.httpStatusFailure);
    expect(result.replacedLastKnownGood, isFalse);
    expect(result.dataset?.provenance.contentSha256, fingerprint);
    expect(store.read(period)?.provenance.contentSha256, fingerprint);
  });

  test('network exception preserves existing LKG', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final seed = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => http.Response(html, 200)),
      coordinator: coordinator(store),
      clock: () => DateTime.utc(2026, 9, 25, 6),
    );
    final seeded = await seed.refresh(period);
    final fingerprint = seeded.dataset!.provenance.contentSha256;

    final failing = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => throw const http.ClientException('offline')),
      coordinator: coordinator(store),
    );
    final result = await failing.refresh(period);

    expect(result.failure, OfficialInvoiceAwardRefreshFailure.networkFailure);
    expect(result.replacedLastKnownGood, isFalse);
    expect(result.dataset?.provenance.contentSha256, fingerprint);
  });

  test('wrong-period official HTML fails closed without LKG replacement', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final service = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => http.Response(
          html.replaceAll('115年05-06月', '115年03-04月'), 200)),
      coordinator: coordinator(store),
      clock: () => DateTime.utc(2026, 9, 25, 6),
    );

    final result = await service.refresh(period);

    expect(result.failure, OfficialInvoiceAwardRefreshFailure.parserFailure);
    expect(result.replacedLastKnownGood, isFalse);
    expect(store.read(period), isNull);
  });
}
