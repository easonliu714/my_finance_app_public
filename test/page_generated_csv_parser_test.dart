import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/ephemeral_authenticated_csv_download.dart';
import 'package:my_finance_app/features/invoice/lab/page_generated_csv_parser.dart';

void main() {
  const parser = PageGeneratedCsvParser(maxBytes: 1024 * 1024);

  test('parses a valid page-generated official CSV without raw persistence', () {
    final source = parser.parse(
      Uint8List.fromList(utf8.encode(_validCsv)),
      fileName: 'download.csv',
    );

    expect(source.fileName, 'download.csv');
    expect(source.preview.supportedInvoiceCount, 1);
    expect(source.preview.invoices.single.candidate?.invoiceNumber, 'AB12345678');
    expect(source.preview.invoices.single.candidate?.rawPayload, isNull);
  });

  test('rejects invalid official header', () {
    expect(
      () => parser.parse(Uint8List.fromList(utf8.encode('wrong,header\n1,2'))),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'code',
          'CSV_SIGNATURE_INVALID',
        ),
      ),
    );
  });

  test('rejects bytes over the configured limit', () {
    const smallParser = PageGeneratedCsvParser(maxBytes: 8);
    expect(
      () => smallParser.parse(Uint8List(9)),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'code',
          'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
        ),
      ),
    );
  });

  test('rejects malformed UTF-8', () {
    expect(
      () => parser.parse(Uint8List.fromList(<int>[0xC3, 0x28])),
      throwsA(
        isA<EphemeralCsvDownloadException>().having(
          (error) => error.code,
          'code',
          'CSV_UTF8_INVALID',
        ),
      ),
    );
  });
}

const _validCsv =
    '載具自訂名稱,發票日期,發票號碼,發票金額,發票狀態,折讓,賣方統一編號,賣方名稱,賣方地址,買方統編,消費明細_數量,消費明細_單價,消費明細_金額,消費明細_品名\n'
    '手機條碼,20260618,AB12345678,47,開立已確認,否,12345678,測試商店,桃園市,,1,47,47,測試商品';
