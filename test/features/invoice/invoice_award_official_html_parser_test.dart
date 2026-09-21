import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_acquisition.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_html_parser.dart';

void main() {
  const parser = MinistryOfFinanceGeneralAwardHtmlParser();
  const validator = OfficialInvoiceAwardDatasetValidator();
  const period = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 5,
    endMonth: 6,
  );

  OfficialInvoiceAwardRawDocument document(
    String body, {
    String path = '/index.html',
  }) =>
      OfficialInvoiceAwardRawDocument(
        sourceUri: Uri.https('invoice.etax.nat.gov.tw', path),
        fetchedAt: DateTime.utc(2026, 7, 25, 8),
        bytes: Uint8List.fromList(utf8.encode(body)),
      );

  OfficialInvoiceAwardParseContext context() =>
      OfficialInvoiceAwardParseContext(
        expectedPeriod: period,
        fetchedAt: DateTime.utc(2026, 7, 25, 8),
        contentSha256: 'a' * 64,
      );

  test('parses pinned official general-award HTML semantics', () {
    final dataset = parser.parse(document(_officialFixture), context());

    expect(dataset.period.id, '115-05-06');
    expect(dataset.provenance.parserVersion, parser.parserVersion);
    expect(dataset.published, isTrue);
    expect(dataset.complete, isTrue);
    expect(
      dataset.rules
          .where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.special)
          .single
          .number,
      '38548029',
    );
    expect(
      dataset.rules
          .where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.grand)
          .single
          .number,
      '10138845',
    );
    expect(
      dataset.rules
          .where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.first)
          .map((rule) => rule.number)
          .toList(),
      <String>['24121106', '28589937', '83663333'],
    );
    expect(validator.validate(dataset).isValid, isTrue);
  });

  test('embedded markup and whitespace inside first-prize numbers are normalized', () {
    const fixture = '''
      <html><body>
        <h2>115年05-06月中獎號碼單</h2>
        <div>特別獎 <span>38548029</span> 同期統一發票收執聯</div>
        <div>特獎 <span>10138845</span> 同期統一發票收執聯</div>
        <div>頭獎
          <span>24121</span> <span>106</span>
          <span>28589</span> <span>937</span>
          <span>83663</span> <span>333</span>
          同期統一發票收執聯
        </div>
      </body></html>
    ''';

    final dataset = parser.parse(document(fixture), context());

    expect(
      dataset.rules
          .where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.first)
          .map((rule) => rule.number)
          .toList(),
      <String>['24121106', '28589937', '83663333'],
    );
  });

  test('period mismatch fails closed before dataset promotion', () {
    expect(
      () => parser.parse(
        document(_officialFixture.replaceAll('115年05-06月', '115年03-04月')),
        context(),
      ),
      throwsFormatException,
    );
  });

  test('same host but unsupported document path is rejected', () {
    expect(
      () => parser.parse(
        document(_officialFixture, path: '/pdf/not-the-award-page.pdf'),
        context(),
      ),
      throwsFormatException,
    );
  });

  test('missing required official row fails closed', () {
    expect(
      () => parser.parse(
        document(
          _officialFixture.replaceAll(
            '<tr><th>特獎</th><td>10138845 同期統一發票收執聯</td></tr>',
            '',
          ),
        ),
        context(),
      ),
      throwsFormatException,
    );
  });

  test('coordinator fingerprints exact bytes then promotes parsed dataset', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: parser,
      validator: validator,
      store: store,
    );

    final result = await coordinator.ingest(
      document: document(_officialFixture),
      expectedPeriod: period,
    );

    expect(result.isSuccess, isTrue);
    expect(result.replacedLastKnownGood, isTrue);
    expect(result.dataset?.provenance.contentSha256, hasLength(64));
    expect(result.dataset?.provenance.parserVersion, parser.parserVersion);
    expect(store.read(period)?.period.id, period.id);
  });
}

const _officialFixture = '''
<html>
  <body>
    <nav>115年05-06月中獎號碼單</nav>
    <section>
      <table>
        <tr><th>獎別</th><th>中獎號碼</th></tr>
        <tr><th>特別獎</th><td>38548029 同期統一發票收執聯</td></tr>
        <tr><th>特獎</th><td>10138845 同期統一發票收執聯</td></tr>
        <tr>
          <th>頭獎</th>
          <td>24121 106 28589 937 83663 333 同期統一發票收執聯</td>
        </tr>
        <tr><th>二獎</th><td>末7位與頭獎相同</td></tr>
        <tr><th>三獎</th><td>末6位與頭獎相同</td></tr>
        <tr><th>四獎</th><td>末5位與頭獎相同</td></tr>
        <tr><th>五獎</th><td>末4位與頭獎相同</td></tr>
        <tr><th>六獎</th><td>末3位與頭獎相同</td></tr>
      </table>
    </section>
  </body>
</html>
''';
