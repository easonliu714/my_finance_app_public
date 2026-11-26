import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

void main() {
  const parser = MinistryOfFinanceCloudAwardPublicationHtmlParser();
  final source = Uri.parse(
    'https://invoice.etax.nat.gov.tw/cloudNowNumber.html',
  );

  test('discovers exactly four canonical sorted official cloud artifacts', () {
    final index = parser.parse(
      sourceUri: source,
      html: _fixture,
      expectedPeriodId: '115-05-06',
      fetchedAt: DateTime.utc(2026, 7, 25, 6),
    );

    expect(index.isComplete, isTrue);
    expect(
      index.artifacts.map((item) => item.tierCode).toSet(),
      <String>{
        'cloud-500',
        'cloud-800',
        'cloud-2000',
        'cloud-1000000',
      },
    );
    expect(
      index.artifacts.every(
        (item) =>
            item.sourceUri.host == 'invoice.etax.nat.gov.tw' &&
            item.sourceUri.path.startsWith('/pdf/'),
      ),
      isTrue,
    );
  });

  test('ignores draw-order PDFs and keeps sorted artifact only', () {
    final index = parser.parse(
      sourceUri: source,
      html: _fixture,
      expectedPeriodId: '115-05-06',
      fetchedAt: DateTime.utc(2026, 7, 25, 6),
    );

    expect(index.artifacts, hasLength(4));
    expect(
      index.artifacts.any(
        (item) => item.sourceUri.path.contains('_draw_order_'),
      ),
      isFalse,
    );
  });

  test('wrong expected period fails closed', () {
    expect(
      () => parser.parse(
        sourceUri: source,
        html: _fixture,
        expectedPeriodId: '115-07-08',
        fetchedAt: DateTime.utc(2026, 9, 25, 6),
      ),
      throwsFormatException,
    );
  });

  test('missing one sorted tier fails closed', () {
    expect(
      () => parser.parse(
        sourceUri: source,
        html: _fixture.replaceAll(
          '<a href="/pdf/20260506_20260725124522_sorted_AI_C.pdf">百萬元獎中獎清單PDF檔(已排序)</a>',
          '',
        ),
        expectedPeriodId: '115-05-06',
        fetchedAt: DateTime.utc(2026, 7, 25, 6),
      ),
      throwsFormatException,
    );
  });

  test('non-official artifact host fails closed', () {
    expect(
      () => parser.parse(
        sourceUri: source,
        html: _fixture.replaceAll(
          '/pdf/20260506_20260725124532_sorted_AI_E.pdf',
          'https://example.com/20260506_20260725124532_sorted_AI_E.pdf',
        ),
        expectedPeriodId: '115-05-06',
        fetchedAt: DateTime.utc(2026, 7, 25, 6),
      ),
      throwsFormatException,
    );
  });
  test('official previous-period cloud page is accepted', () {
    final index = parser.parse(
      sourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/cloudLastNumber.html',
      ),
      html: _fixture,
      expectedPeriodId: '115-05-06',
      fetchedAt: DateTime.utc(2026, 9, 25, 6),
    );
    expect(index.isComplete, isTrue);
  });
}

const _fixture = '''
<html>
  <body>
    <h2>115年05-06月中獎號碼單</h2>
    <a href="/pdf/20260506_20260725124620_sorted_AI_D.pdf">五百元獎中獎號碼清單PDF檔(已排序)</a>
    <a href="/pdf/20260506_20260725124621_draw_order_AI_D.pdf">五百元獎中獎號碼清單PDF檔(依開獎順序)</a>
    <a href="/pdf/20260506_20260725124532_sorted_AI_E.pdf">八百元獎中獎號碼清單PDF檔(已排序)</a>
    <a href="/pdf/20260506_20260725124533_draw_order_AI_E.pdf">八百元獎中獎號碼清單PDF檔(依開獎順序)</a>
    <a href="/pdf/20260506_20260725124524_sorted_AI_B.pdf">兩千元獎中獎號碼清單PDF檔(已排序)</a>
    <a href="/pdf/20260506_20260725124525_draw_order_AI_B.pdf">兩千元獎中獎號碼清單PDF檔(依開獎順序)</a>
    <a href="/pdf/20260506_20260725124522_sorted_AI_C.pdf">百萬元獎中獎清單PDF檔(已排序)</a>
    <a href="/pdf/20260506_20260725124523_draw_order_AI_C.pdf">百萬元獎中獎清單PDF檔(依開獎順序)</a>
  </body>
</html>
''';