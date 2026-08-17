import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';

void main() {
  const checksumValidTaxId = '12345675';

  test('checksum-valid NO header is Live evidence but not frozen authority', () {
    const document = LocalOcrTextDocument(
      fullText: '測試商店\nAB12345678\nNO.12345675',
      lines: <String>['測試商店', 'AB12345678', 'NO.12345675'],
    );

    final evidence = extractTraditionalSellerTaxIdEvidence(
      document.lines,
      invoiceNumber: 'AB12345678',
    );
    expect(evidence?.value, checksumValidTaxId);
    expect(evidence?.source, 'contextual_no_header');
    expect(evidence?.acceptedForLive, isTrue);
    expect(evidence?.acceptedForFrozenSingleFrame, isFalse);

    final parsed = const TraditionalInvoiceTextParser().parse(document);
    expect(parsed.sellerTaxId, isNull);
    expect(parsed.sellerTaxIdSource, isEmpty);
    expect(
      parsed.fieldWarnings.values.expand((warnings) => warnings),
      contains(
        '單次凍結 OCR 僅取得非明確「賣方統編」標籤的 8 碼候選；checksum 不足以單獨升格，已保持空白，需 Live 多幀、Gemini 或人工覆核。',
      ),
    );
  });

  test('explicit seller-tax label may remain frozen authority with checksum', () {
    const document = LocalOcrTextDocument(
      fullText: '測試商店\nAB12345678\n賣方統編：12345675',
      lines: <String>['測試商店', 'AB12345678', '賣方統編：12345675'],
    );

    final evidence = extractTraditionalSellerTaxIdEvidence(
      document.lines,
      invoiceNumber: 'AB12345678',
    );
    expect(evidence?.source, 'explicit_label');
    expect(evidence?.acceptedForFrozenSingleFrame, isTrue);

    final parsed = const TraditionalInvoiceTextParser().parse(document);
    expect(parsed.sellerTaxId, checksumValidTaxId);
    expect(parsed.sellerTaxIdSource, 'explicit_label');
  });
}
