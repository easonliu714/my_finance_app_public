import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart';

void main() {
  test('line items round-trip with nullable fields', () {
    const items = <CloudInvoiceLineItem>[
      CloudInvoiceLineItem(
        name: '咖啡',
        amount: 80,
        quantity: 2,
        unitPrice: 40,
        rawName: 'Coffee',
        categorySuggestion: '餐飲',
      ),
      CloudInvoiceLineItem(name: '折扣', amount: -10),
    ];

    final decoded = decodeCloudInvoiceLineItems(
      encodeCloudInvoiceLineItems(items),
    );

    expect(decoded, hasLength(2));
    expect(decoded.first.name, '咖啡');
    expect(decoded.first.quantity, 2);
    expect(decoded.first.unitPrice, 40);
    expect(decoded.last.amount, -10);
    expect(decoded.last.quantity, isNull);
  });

  test('unsupported line-item payload version fails closed', () {
    final payload = jsonEncode(<String, Object?>{
      'version': 99,
      'items': const <Object?>[],
    });

    expect(
      () => decodeCloudInvoiceLineItems(payload),
      throwsA(isA<FormatException>()),
    );
  });
}
