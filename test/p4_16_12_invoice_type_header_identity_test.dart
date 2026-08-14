import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_page.dart';
import 'package:my_finance_app/features/invoice/invoice_live_capture_stabilized_page.dart';

void main() {
  LocalOcrTextLine line(String text, double top) => LocalOcrTextLine(
        text: text,
        left: 20,
        top: top,
        right: 220,
        bottom: top + 20,
      );

  test('semantic electronic evidence does not depend only on QR decode', () {
    expect(
      hasStrongElectronicInvoiceSemanticEvidence(
        const <String>['電子發票證明聯'],
      ),
      isTrue,
    );
    expect(
      hasStrongElectronicInvoiceSemanticEvidence(
        const <String>['電子發票', '隨機碼 1234', '賣方 31655572'],
      ),
      isTrue,
    );
    expect(
      hasStrongElectronicInvoiceSemanticEvidence(
        const <String>['本店支援電子發票', '謝謝光臨'],
      ),
      isFalse,
    );
  });

  test('semantic electronic fallback classifies electronic but QR remains separate', () {
    expect(
      resolveLiveInvoiceClassification(
        hasValidQr: false,
        qrPayloadCount: 0,
        hasStrongElectronicSemanticEvidence: true,
        hasTextEvidence: true,
      ),
      InvoiceLiveClassification.electronic,
    );
    expect(
      resolveLiveInvoiceClassification(
        hasValidQr: false,
        qrPayloadCount: 0,
        hasStrongElectronicSemanticEvidence: false,
        hasTextEvidence: true,
      ),
      InvoiceLiveClassification.traditional,
    );
    expect(
      resolveLiveInvoiceClassification(
        hasValidQr: false,
        qrPayloadCount: 0,
        hasStrongElectronicSemanticEvidence: false,
        hasTextEvidence: false,
      ),
      InvoiceLiveClassification.searching,
    );
  });

  test('unique checksum-valid eight digits below invoice number are accepted', () {
    const lines = <String>[
      '一品現泡茶店',
      'XY90000020',
      '30340553',
      '新北市板橋區',
      '交易明細',
    ];
    final evidence = extractTraditionalSellerTaxIdEvidence(
      lines,
      invoiceNumber: 'XY90000020',
      positionedLines: <LocalOcrTextLine>[
        line(lines[0], 0),
        line(lines[1], 30),
        line(lines[2], 60),
        line(lines[3], 90),
        line(lines[4], 120),
      ],
    );
    expect(evidence, isNotNull);
    expect(evidence!.value, '30340553');
    expect(evidence.source, 'positional_header_8digit');
    expect(evidence.checksumValid, isTrue);
    expect(evidence.acceptedForLive, isTrue);
  });

  test('checksum-invalid positional eight digits fail closed', () {
    const lines = <String>[
      '一品現泡茶店',
      'XY90000020',
      '30349553',
      '交易明細',
    ];
    final evidence = extractTraditionalSellerTaxIdEvidence(
      lines,
      invoiceNumber: 'XY90000020',
      positionedLines: <LocalOcrTextLine>[
        line(lines[0], 0),
        line(lines[1], 30),
        line(lines[2], 60),
        line(lines[3], 90),
      ],
    );
    expect(evidence, isNull);
  });

  test('buyer-side eight digits are not accepted as seller identity', () {
    const lines = <String>[
      'XY90000020',
      '買方',
      '30340553',
      '交易明細',
    ];
    final evidence = extractTraditionalSellerTaxIdEvidence(
      lines,
      invoiceNumber: 'XY90000020',
      positionedLines: <LocalOcrTextLine>[
        line(lines[0], 30),
        line(lines[1], 55),
        line(lines[2], 80),
        line(lines[3], 105),
      ],
    );
    expect(evidence, isNull);
  });

  test('multiple checksum-valid positional candidates remain ambiguous', () {
    const lines = <String>[
      'XY90000020',
      '30340553',
      '31655572',
      '交易明細',
    ];
    final evidence = extractTraditionalSellerTaxIdEvidence(
      lines,
      invoiceNumber: 'XY90000020',
      positionedLines: <LocalOcrTextLine>[
        line(lines[0], 30),
        line(lines[1], 55),
        line(lines[2], 80),
        line(lines[3], 105),
      ],
    );
    expect(evidence, isNull);
  });
}
