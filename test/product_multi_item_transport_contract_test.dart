import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_transport_contract.dart';

void main() {
  group('ProductMultiItemTransportContract', () {
    test('keeps lines optional and out of legacy required fields', () {
      expect(ProductMultiItemTransportContract.fieldName, 'lines');
      final schema = ProductMultiItemTransportContract.responseSchemaProperty;
      expect(schema['type'], contains('null'));
      expect(schema['items'], isA<Map<String, Object?>>());
    });

    test('requires explicit per-line evidence fields when a row is present', () {
      final schema = ProductMultiItemTransportContract.responseSchemaProperty;
      final item = schema['items']! as Map<String, Object?>;
      expect(
        item['required'],
        equals(<String>['name', 'quantity', 'unitPrice', 'subtotal', 'rawEvidence']),
      );
    });

    test('prompt freezes review-only and no-guess boundaries', () {
      final prompt = ProductMultiItemTransportContract.promptAddendum;
      expect(prompt, contains('待人工覆核證據'));
      expect(prompt, contains('不得自行用 quantity × unitPrice 補值'));
      expect(prompt, contains('不得因此建立交易、商家、分類'));
    });
  });
}
