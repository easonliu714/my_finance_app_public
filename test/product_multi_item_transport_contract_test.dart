import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/product_multi_item_transport_contract.dart';

void main() {
  group('ProductMultiItemTransportContract', () {
    test('keeps lines optional and out of legacy required fields', () {
      expect(ProductMultiItemTransportContract.fieldName, 'lines');
      const schema = ProductMultiItemTransportContract.responseSchemaProperty;
      expect(schema['type'], contains('null'));
      expect(schema['items'], isA<Map<String, Object?>>());
    });

    test('requires explicit per-line evidence fields when a row is present', () {
      const schema = ProductMultiItemTransportContract.responseSchemaProperty;
      final item = schema['items']! as Map<String, Object?>;
      expect(
        item['required'],
        equals(<String>['name', 'quantity', 'unitPrice', 'subtotal', 'rawEvidence']),
      );
    });

    test('prompt freezes review-only and no-guess boundaries', () {
      const prompt = ProductMultiItemTransportContract.promptAddendum;
      expect(prompt, contains('待人工覆核證據'));
      expect(prompt, contains('不得自行用 quantity × unitPrice 補值'));
      expect(prompt, contains('不得因此建立交易、商家、分類'));
    });

    test('schema wiring is additive and never mutates legacy properties', () {
      final legacy = <String, Object?>{
        'productName': <String, Object?>{'type': 'string'},
      };
      final wired = ProductMultiItemTransportContract.withOptionalLinesProperty(
        legacy,
      );

      expect(legacy.containsKey('lines'), isFalse);
      expect(wired['productName'], same(legacy['productName']));
      expect(
        wired['lines'],
        same(ProductMultiItemTransportContract.responseSchemaProperty),
      );
    });

    test('prompt wiring preserves legacy instructions before addendum', () {
      const legacy = 'legacy single-item review instructions';
      final wired = ProductMultiItemTransportContract.withPromptAddendum(legacy);

      expect(wired, startsWith(legacy));
      expect(wired, contains(ProductMultiItemTransportContract.promptAddendum));
      expect(wired, contains('不得因此建立交易、商家、分類'));
    });
  });
}
